#!/usr/bin/env bash
# wait_for_copilot_test.sh - Fixture-driven test suite for wait_for_copilot.sh
#
# The shared Copilot-wait state machine (.just/lib/wait_for_copilot.sh) sits
# on the critical path of every `just pr` / `just again` /
# `just copilot_refresh` run, but had no automated test - unlike its siblings
# pr_body_test.sh, template_sync_test.sh, and cue_sync_test.sh. It needed two
# rounds of GraphQL/state-machine bug fixes in v8.4 alone; this suite would
# have caught the set -e/gum and stale-sentinel bugs before they shipped.
# See issue #330.
#
# Design: the production script runs byte-for-byte unmodified. `gh` and
# `sleep` are intercepted via a PATH shim directory (the same mocking
# precedent template_sync_test.sh uses for curl), so:
#
#   - mock gh plays fixture responses in order and applies the real --jq
#     filter with real jq, exercising the exact response shaping the
#     production script relies on
#   - mock sleep is a no-op; wait_for_copilot.sh advances `elapsed` with
#     shell arithmetic, so poll loops still terminate instantly
#
# Each fixture directory holds:
#   responses/N.json  - GraphQL response for poll N (1-based, in order)
#   responses/N.null  - a failed API call for poll N (gh exits nonzero)
#                       beyond the last numbered response, the final one
#                       repeats (lets "still in progress" fixtures loop)
#   args              - optional: space-separated overrides of MODE (default
#                       fatal) and USING_GUM (default 0), in that order
#   expected_exit     - required: expected exit code (0 or 1)
#   expected_output.txt - optional: lines that must appear in order
#   sentinel_expected - optional: "present" or "absent" (default absent);
#                       whether the stale sentinel survives the run
#
# The production script derives its sentinel path as
# /tmp/copilot_stale_${OWNER}_${NAME}_${PR}; this suite uses unique per-run
# tokens so concurrent runs cannot clobber each other's sentinel state, and
# pre-creates the sentinel before each test so the "cleared on clean exit"
# behavior (Claude review of PR #300, Potential bug 2) is actually asserted.

set -uo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NORMAL='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly SCRIPT_UNDER_TEST="$SCRIPT_DIR/wait_for_copilot.sh"
readonly FIXTURES_DIR="$SCRIPT_DIR/../test/fixtures/wait_for_copilot"

# Unique tokens for this run (see header comment)
readonly TEST_OWNER="wfc-test-org-$$"
readonly TEST_NAME="wfc-test-repo-$$"
readonly TEST_PR="$$"
readonly HEAD_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
readonly OLD_SHA="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
readonly STALE_SENTINEL="/tmp/copilot_stale_${TEST_OWNER}_${TEST_NAME}_${TEST_PR}"

PASSED=0
FAILED=0

# Write the PATH shim scripts into the workspace. The mock's poll counter
# lives next to it so state persists across separate gh invocations.
build_shims() {
	local shim_dir="$1"

	cat > "$shim_dir/gh" <<'EOF'
#!/usr/bin/env bash
# Mock gh api graphql for wait_for_copilot_test.sh
shim_dir="${BASH_SOURCE[0]%/*}"
counter_file="$shim_dir/poll_count"
[[ -f "$counter_file" ]] || echo 0 > "$counter_file"
count=$(cat "$counter_file")
echo $((count + 1)) > "$counter_file"
count=$((count + 1))

# Locate the response for this poll: N.json is a real GraphQL response,
# N.null marks a failed API call. Past the last numbered response the
# final one repeats (in-progress fixtures loop until timeout).
if [[ -f "$shim_dir/responses/$count.json" ]]; then
	response="$shim_dir/responses/$count.json"
elif [[ -f "$shim_dir/responses/$count.null" ]]; then
	exit 1
else
	last=$(ls "$shim_dir/responses" | sed 's/\..*//' | sort -n | tail -1)
	if [[ -f "$shim_dir/responses/$last.null" ]]; then
		exit 1
	fi
	response="$shim_dir/responses/$last.json"
fi

# Apply the real --jq filter with real jq, exactly as production gh does
jq_filter=""
args=("$@")
for (( i = 0; i < ${#args[@]}; i++ )); do
	if [[ "${args[$i]}" == "--jq" ]]; then
		jq_filter="${args[$(( i + 1 ))]}"
		break
	fi
done

jq -r "$jq_filter" "$response"
EOF
	chmod +x "$shim_dir/gh"

	# no-op sleep: the script advances elapsed arithmetically, not by clock
	printf '#!/usr/bin/env bash\n# no-op sleep for wait_for_copilot_test.sh\nexit 0\n' \
		> "$shim_dir/sleep"
	chmod +x "$shim_dir/sleep"
}

# Run one fixture. Args: $1 = fixture name
run_test() {
	local name="$1"
	local fixture_dir="$FIXTURES_DIR/$name"

	if [[ ! -d "$fixture_dir/responses" ]]; then
		echo -e "${RED}✗${NORMAL} $name - no responses/ directory"
		(( FAILED += 1 ))
		return
	fi
	if [[ ! -f "$fixture_dir/expected_exit" ]]; then
		echo -e "${RED}✗${NORMAL} $name - missing expected_exit"
		(( FAILED += 1 ))
		return
	fi

	local mode="fatal"
	local using_gum=0
	if [[ -f "$fixture_dir/args" ]]; then
		# shellcheck disable=SC2207  # fixture-controlled, two known tokens max
		read -r -a extra_args <<< "$(cat "$fixture_dir/args")"
		[[ ${#extra_args[@]} -gt 0 ]] && mode="${extra_args[0]}"
		[[ ${#extra_args[@]} -gt 1 ]] && using_gum="${extra_args[1]}"
	fi
	local expected_exit
	expected_exit=$(cat "$fixture_dir/expected_exit")

	# Build the shim workspace and copy responses with original basenames
	local workspace
	workspace=$(mktemp -d -t wfc_test.XXXXXX)
	mkdir -p "$workspace/responses"
	local response_file
	for response_file in "$fixture_dir/responses"/*; do
		[[ -f "$response_file" ]] && cp "$response_file" "$workspace/responses/"
	done
	build_shims "$workspace"

	# Pre-create the sentinel so the clean-exit removal path is exercised
	touch "$STALE_SENTINEL"

	local output="" actual_exit=0
	output=$(PATH="$workspace:$PATH" "$SCRIPT_UNDER_TEST" \
		"$TEST_OWNER" "$TEST_NAME" "$TEST_PR" "$HEAD_SHA" \
		30 5 0 "$using_gum" "$mode" 2>&1) || actual_exit=$?

	local ok=true

	# Exit code assertion
	if [[ "$actual_exit" != "$expected_exit" ]]; then
		echo -e "${RED}✗${NORMAL} $name - expected exit $expected_exit, got $actual_exit"
		echo "    --- output ---"
		printf '%s\n' "$output" | sed 's/^/    /'
		echo "    --- end ---"
		rm -rf "$workspace"
		rm -f "$STALE_SENTINEL"
		(( FAILED += 1 ))
		return
	fi

	# Expected-output lines (in order, like template_sync_test.sh)
	if [[ -f "$fixture_dir/expected_output.txt" ]]; then
		local normalized
		# The script prints HEAD_SHA truncated to 7 chars in stale messages;
		# normalize both the full and truncated forms so fixtures can state
		# the expected line as "HEAD is HEAD_SHA".
		normalized=$(echo "$output" | sed "s/${HEAD_SHA:0:7}/HEAD_SHA/g; s/$HEAD_SHA/HEAD_SHA/g; s/${OLD_SHA:0:7}/OLD_SHA/g; s/$OLD_SHA/OLD_SHA/g")
		local search_start=1 line line_num
		while IFS= read -r line || [[ -n "$line" ]]; do
			[[ -n "$line" ]] || continue
			line_num=$(echo "$normalized" | grep -nF "$line" | awk -F: -v s="$search_start" '$1 >= s {print $1; exit}')
			if [[ -z "$line_num" ]]; then
				echo -e "${RED}✗${NORMAL} $name - missing expected line: $line"
				ok=false
				break
			fi
			search_start=$((line_num + 1))
		done < "$fixture_dir/expected_output.txt"
	fi

	# Sentinel assertion: default "absent" covers both the timeout path
	# (never written) and the clean exit-0 path (pre-existing one removed)
	local sentinel_expected="absent"
	if [[ -f "$fixture_dir/sentinel_expected" ]]; then
		sentinel_expected=$(cat "$fixture_dir/sentinel_expected")
	fi
	if [[ "$sentinel_expected" == "present" ]]; then
		if [[ ! -f "$STALE_SENTINEL" ]]; then
			echo -e "${RED}✗${NORMAL} $name - stale sentinel was not written"
			ok=false
		fi
	elif [[ -f "$STALE_SENTINEL" ]]; then
		echo -e "${RED}✗${NORMAL} $name - stale sentinel not cleaned up on exit $actual_exit"
		ok=false
	fi

	rm -f "$STALE_SENTINEL"
	rm -rf "$workspace"

	if [[ "$ok" == true ]]; then
		echo -e "${GREEN}✓${NORMAL} $name"
		(( PASSED += 1 ))
	else
		(( FAILED += 1 ))
	fi
}

main() {
	echo -e "${BLUE}Running wait_for_copilot tests...${NORMAL}"
	echo

	if [[ ! -x "$SCRIPT_UNDER_TEST" ]]; then
		echo -e "${RED}Error: $SCRIPT_UNDER_TEST not found or not executable${NORMAL}" >&2
		exit 1
	fi
	if [[ ! -d "$FIXTURES_DIR" ]]; then
		echo -e "${YELLOW}No test fixtures found at $FIXTURES_DIR${NORMAL}"
		echo "Tests skipped"
		exit 0
	fi

	local fixture
	for fixture in "$FIXTURES_DIR"/*/; do
		[[ -d "$fixture" ]] || continue
		run_test "$(basename "$fixture")"
	done

	echo
	echo -e "Results: ${GREEN}$PASSED passed${NORMAL}, ${RED}$FAILED failed${NORMAL}"

	[[ "$FAILED" -gt 0 ]] && exit 1
	exit 0
}

main "$@"
