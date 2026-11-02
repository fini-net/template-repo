#!/usr/bin/env bash
# Test suite for template synchronization system
#
# Two fixture modes share this runner:
#
#   - update-script mode (legacy, fixtures 01-04): drives a patched copy of
#     template_update.sh with a mocked curl, as before
#   - recipe mode (fixtures 05+): drives the actual `just checksums_verify`
#     / `checksums_diff` recipes in a temp workspace holding a copy of the
#     real .just/template-sync.just, so the validate_filepath gates that
#     live in the recipe bodies are exercised too (#354 - flagged as a
#     coverage gap in the Claude review of #352, since template_update.sh
#     tests never touch the recipe-level gates)
#
# Fixture layout is shared: input/, manifest.json, template_versions/,
# expected_output.txt, expected_state/. Recipe fixtures add:
#
#   recipe         - required: recipe to run, first word is the recipe name
#                     and remaining words are its arguments (e.g.
#                     "checksums_verify" or "checksums_diff ../evil.txt")
#   expected_exit  - optional: expected exit code (default 0 for recipe
#                     mode; update-script mode ignores failures as before)
#   modules        - optional: space-separated .just module basenames to
#                     copy into the workspace and import (default:
#                     "template-sync"; e.g. "gh-process" or "claude
#                     template-sync"). Each module's import line lands in
#                     the scaffolded justfile.
#   bare_justfile  - optional: any content; when present the scaffolded
#                     workspace justfile omits `set positional-arguments
#                     := true`, exactly mirroring a derived repo whose
#                     root justfile never ships (#368). Pins the
#                     invariant: tracked modules must be self-contained -
#                     no recipe may depend on root-justfile configuration
#                     that doesn't ship (#367).
#   shims/         - optional: executable scripts copied into the
#                     workspace and prepended to PATH, shadowing both the
#                     harness's mock curl and real tools (the same PATH
#                     shim precedent wait_for_copilot_test.sh uses for
#                     gh/sleep). Fixture shims win over the harness mock
#                     because the whole workspace dir sits first on PATH.
#   stdin          - optional: file piped to the recipe's stdin, for
#                     recipes that prompt (copilot_rollback's selection
#                     read, #382). Absent, stdin is /dev/null, so a
#                     recipe run can never hang on a TTY waiting for
#                     input; recipes that never read stdin (the
#                     checksums_* fixtures) are unaffected by EOF.
set -euo pipefail

# shellcheck source=.just/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NORMAL='\033[0m'

readonly FIXTURES_DIR=".just/test/fixtures/template_sync"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

passed=0
failed=0

# Run a single test
run_test() {
	local test_name="$1"
	local test_dir="$FIXTURES_DIR/$test_name"

	if [[ ! -d "$test_dir" ]]; then
		echo -e "${RED}✗${NORMAL} $test_name - directory not found"
		(( failed += 1 ))
		return
	fi

	# Absolutize before we cd into the workspace, so fixture checks
	# below still resolve after the working directory changes
	test_dir="$(cd "$test_dir" && pwd)"

	# Recipe mode (#354): drive the real just recipes. Falls back to a
	# yellow skip (counted as a failure so the gap stays visible) when
	# just is not installed.
	if [[ -f "$test_dir/recipe" ]]; then
		run_recipe_test "$test_name" "$test_dir"
		return
	fi

	run_update_test "$test_name" "$test_dir"
}

# Write the shared mock curl into a target directory. Contract:
#   - a call without -o fails and serves nothing: the CHECKSUMS.json
#     branch sits inside the -o branch, so a manifest fetch without
#     -o falls through to failure too (both real call sites use -o;
#     noted in #377 after the branch nesting narrowed)
#   - a call with -o writes to the given output file; a URL ending
#     in .just/CHECKSUMS.json serves the fixture manifest
#   - with -o, any other URL serves template_versions/<basename> if
#     present
# Both the recipe-mode and update-script-mode mocks must honor this
# exact contract, so it lives in one place (Claude review of #360,
# finding 2 - it was two copy-pasted heredocs that could drift).
write_mock_curl() {
	local target_dir="$1"
	local mock_curl="$target_dir/curl"
	cat > "$mock_curl" <<'MOCK_EOF'
#!/usr/bin/env bash
# Mock curl for testing
if [[ "$*" == *"-o"* ]]; then
	# Extract output file: the argument after -o
	output_file=""
	next=0
	for arg in "$@"; do
		if [[ "$next" == 1 ]]; then
			output_file="$arg"
			break
		fi
		if [[ "$arg" == "-o" ]]; then
			next=1
		fi
	done
	# The URL is the last non-flag argument
	source_path=""
	for arg in "$@"; do
		if [[ "$arg" != -* && "$arg" != "$output_file" ]]; then
			source_path="$arg"
		fi
	done
	if [[ "$source_path" == *".just/CHECKSUMS.json" ]]; then
		manifest_path="${BASH_SOURCE[0]%/*}/manifest.json"
		if [[ -f "$manifest_path" ]]; then
			# The update-script mode points MANIFEST_FILE straight at
			# this fixture-copied manifest (sed patch), so source and
			# destination can be the same file - cat-ing a file onto
			# itself would truncate it. No-op in that case.
			if [[ ! "$manifest_path" -ef "$output_file" ]]; then
				cat "$manifest_path" > "$output_file"
			fi
			exit 0
		fi
		exit 1
	fi
	filename="${source_path##*/}"
	template_file="${BASH_SOURCE[0]%/*}/template_versions/$filename"
	if [[ -f "$template_file" ]]; then
		cat "$template_file" > "$output_file"
		exit 0
	fi
	exit 1
fi
exit 1
MOCK_EOF
	chmod +x "$mock_curl"
}

# Expected-output check shared by both fixture modes (#377): every
# non-empty line in expected_output.txt must appear, in order, in the
# normalized output. On a mismatch, builds the failure diagnostic in
# $output_mismatch - the first expected line with no match at/after
# the search position, plus both sides dumped with the exact
# normalization the matcher uses (mktemp/pid paths already scrubbed)
# - so a red fixture answers "what did it actually print" without a
# manual re-run (#376).
#
# Globals set: output_ok, output_mismatch
match_expected_output() {
	local output="$1" test_dir="$2" test_name="$3"
	output_ok=true
	output_mismatch=""
	[[ -f "$test_dir/expected_output.txt" ]] || return 0

	# Normalize output (remove color codes, blank lines, temp paths).
	# The mismatch dump below reuses this exact normalization so
	# expected and actual compare line for line.
	local normalized_output
	# shellcheck disable=SC2016  # awk script is intentionally single-quoted
	normalized_output=$(echo "$output" | LC_ALL=C awk '{ gsub(/\033\[[0-9;]*m/, ""); print }' | \
		grep -v "^$" | \
		sed 's|/tmp/[^[:space:]]*||g')

	# Every non-empty expected line must appear in order in the output
	local expected_lines=()
	local line
	while IFS= read -r line || [[ -n "$line" ]]; do
		[[ -n "$line" ]] && expected_lines+=("$line")
	done < "$test_dir/expected_output.txt"

	if [[ ${#expected_lines[@]} -eq 0 ]]; then
		echo -e "${YELLOW}!${NORMAL} $test_name - expected_output.txt is empty, output not checked"
		return 0
	fi

	local search_start=1
	local line_num i=1
	for line in "${expected_lines[@]}"; do
		# -e: expected lines may start with dashes (e.g. diff output).
		# grep exits 1 when the line is missing - a handled case here,
		# not a crash - but under `set -euo pipefail` the substitution
		# would abort the whole suite before the mismatch could be
		# reported (a latent harness bug surfaced by the bare-justfile
		# fixtures, #368, whose whole point is failing recipes). The
		# `|| true` guard keeps the loop alive; the -z check below
		# reports the mismatch.
		line_num=$(echo "$normalized_output" | grep -nF -e "$line" | awk -F: -v s="$search_start" '$1 >= s {print $1; exit}') \
			|| true
		if [[ -z "$line_num" ]]; then
			output_ok=false
			# First-difference hint, then both sides, normalized (#376)
			output_mismatch=$(
				echo "      First unmatched expected line $i: \"$line\""
				echo "      (searched for it from normalized output line $search_start onward)"
				echo "      expected:"
				printf '        %s\n' "${expected_lines[@]}"
				echo "      actual:"
				if [[ -n "$normalized_output" ]]; then
					printf '%s\n' "$normalized_output" | sed 's/^/        /'
				fi
			)
			return 0
		fi
		search_start=$((line_num + 1))
		i=$((i + 1))
	done
}

# Expected-state check shared by both fixture modes (#377): every file
# under expected_state/ must exist in the workspace with an identical
# checksum. On a mismatch, records the offending path and reason in
# $state_mismatch so the failure report names the file the fix loop
# needs (the state counterpart of the output dump, #376).
#
# Globals set: state_ok, state_mismatch
verify_expected_state() {
	local workspace="$1" test_dir="$2"
	state_ok=true
	state_mismatch=""
	[[ -d "$test_dir/expected_state" ]] || return 0

	local expected_file
	# LC_ALL=C sort: find's order is filesystem-dependent, and the
	# mismatch report names the first offender, so the reported file
	# must not vary between runs or machines (review round, #433)
	while IFS= read -r expected_file; do
		# Quoted pattern (SC2295): the pre-extraction run_update_test
		# copy had drifted to the unquoted form (#377)
		local rel_path="${expected_file#"$test_dir"/expected_state/}"
		if [[ ! -f "$workspace/$rel_path" ]]; then
			state_ok=false
			state_mismatch="missing: $rel_path"
			return 0
		fi

		local expected_sum actual_sum
		expected_sum=$(compute_checksum "$expected_file")
		actual_sum=$(compute_checksum "$workspace/$rel_path")

		if [[ "$expected_sum" != "$actual_sum" ]]; then
			state_ok=false
			state_mismatch="differs: $rel_path"
			return 0
		fi
	done < <(find "$test_dir/expected_state" -type f | LC_ALL=C sort)
}

# Self-test for the shared matchers (review round, #433): the
# mismatch diagnostics only print when a fixture fails, and no
# fixture is supposed to fail, so the dump and state-reason paths
# would otherwise carry no coverage. Drives the helpers against a
# deliberately wrong scratch fixture and asserts the diagnostics
# fire - and stay silent on a clean run - reporting through the
# same passed/failed counters as a fixture. Applies the v10.5
# compliance suite's run-on-every-run self-test precedent here.
harness_selftest() {
	local scratch ws reasons=()
	scratch=$(mktemp -d)
	ws=$(mktemp -d)

	# Scratch fixture: two expected lines, one expected-state file
	mkdir -p "$scratch/expected_state/.just" "$ws/.just"
	printf 'alpha line\nomega line\n' > "$scratch/expected_output.txt"
	printf 'state one\n' > "$scratch/expected_state/.just/state.just"

	# Red case: second expected line missing from the output
	match_expected_output "alpha line" "$scratch" "harness_selftest"
	[[ "$output_ok" == false ]] || reasons+=("red output: output_ok not false")
	[[ "$output_mismatch" == *"First unmatched expected line 2"* ]] \
		|| reasons+=("red output: dump lacks first-unmatched marker")
	[[ "$output_mismatch" == *"searched for it from normalized output line 2 onward"* ]] \
		|| reasons+=("red output: dump lacks search-position hint")

	# Green case: every expected line present in order
	match_expected_output "alpha line
omega line" "$scratch" "harness_selftest"
	[[ "$output_ok" == true ]] || reasons+=("green output: output_ok not true")
	[[ -z "$output_mismatch" ]] || reasons+=("green output: mismatch detail not empty")

	# Green state: identical checksums
	printf 'state one\n' > "$ws/.just/state.just"
	verify_expected_state "$ws" "$scratch"
	[[ "$state_ok" == true ]] || reasons+=("green state: state_ok not true")
	[[ -z "$state_mismatch" ]] || reasons+=("green state: mismatch detail not empty")

	# Red state: content differs
	printf 'state one changed\n' > "$ws/.just/state.just"
	verify_expected_state "$ws" "$scratch"
	[[ "$state_ok" == false ]] || reasons+=("differs state: state_ok not false")
	[[ "$state_mismatch" == "differs: .just/state.just" ]] \
		|| reasons+=("differs state: got '$state_mismatch'")

	# Red state: file missing
	rm "$ws/.just/state.just"
	verify_expected_state "$ws" "$scratch"
	[[ "$state_ok" == false ]] || reasons+=("missing state: state_ok not false")
	[[ "$state_mismatch" == "missing: .just/state.just" ]] \
		|| reasons+=("missing state: got '$state_mismatch'")

	rm -rf "$scratch" "$ws"

	if [[ ${#reasons[@]} -eq 0 ]]; then
		echo -e "${GREEN}✓${NORMAL} harness_selftest"
		(( passed += 1 ))
	else
		echo -e "${RED}✗${NORMAL} harness_selftest"
		local reason
		for reason in "${reasons[@]}"; do
			echo "    $reason"
		done
		(( failed += 1 ))
	fi
}

# Self-test for the security-boundary functions in common.sh (#382):
# validate_filepath is the gate every manifest key passes before any
# filesystem use (#347), and sanitize_for_display is what keeps a
# rejected key from spoofing output lines or injecting terminal escape
# sequences when it is printed. Recipe fixtures exercise both
# end-to-end through the checksums gates, but nothing pinned the
# specific rejection classes, and the escaping here is dense enough
# that a future "simplifying" edit could drop a class without any
# fixture going red. common.sh is already sourced at the top of this
# harness, so this asserts against the real shipped functions - the
# v10.6 harness_selftest precedent applied to product code. Reports
# through the same passed/failed counters as a fixture. Verified to
# behave identically on bash 3.2 (macOS) and bash 5 (CI).
security_boundary_selftest() {
	local reasons=()
	local path rc out

	# Accept: anything under the .just/ charter, including odd-but-
	# legal whole segment names like "..." (only whole ".." segments
	# are traversal)
	for path in ".just/foo.just" ".just/lib/common.sh" ".just/a/b.sh" ".just/..."; do
		rc=0
		validate_filepath "$path" || rc=$?
		[[ $rc -eq 0 ]] || reasons+=("expected accept, got reject: $path")
	done

	# Reject: anything not under .just/, relative or absolute (the
	# prefix check is what makes absolute paths safe)
	for path in "just/foo.just" "src/main.rs" "/etc/passwd" "../outside.sh"; do
		rc=0
		validate_filepath "$path" || rc=$?
		[[ $rc -ne 0 ]] || reasons+=("non-.just/ path accepted: $path")
	done

	# Reject: whole ".." segments - leading, mid-path, and final
	for path in ".just/../evil.sh" ".just/a/../b.sh" ".just/.."; do
		rc=0
		validate_filepath "$path" || rc=$?
		[[ $rc -ne 0 ]] || reasons+=("traversal accepted: $path")
	done

	# Reject: double quotes and backslashes (both break jq string
	# interpolation). A single quote is deliberately accepted: call
	# sites pass keys with jq --arg, which is quote-safe - pin that
	# so the rejection set can't creep wider without this going red.
	rc=0
	validate_filepath '.just/a"b.sh' || rc=$?
	[[ $rc -ne 0 ]] || reasons+=("double quote accepted: .just/a\"b.sh")
	rc=0
	validate_filepath '.just/a\b.sh' || rc=$?
	[[ $rc -ne 0 ]] || reasons+=("backslash accepted: .just/a\\b.sh")
	rc=0
	validate_filepath ".just/a'b.sh" || rc=$?
	[[ $rc -eq 0 ]] || reasons+=("single quote rejected (call sites use jq --arg): .just/a'b.sh")

	# Reject: control characters - tab, ESC, and the embedded newline
	# a NUL-delimited manifest key can carry (spoofs extra output
	# lines). Keep these out of the failure messages: printing them
	# would be the bug under test.
	for path in $'.just/a\tb.sh' $'.just/a\033b.sh' $'.just/a\nb.sh'; do
		rc=0
		validate_filepath "$path" || rc=$?
		[[ $rc -ne 0 ]] || reasons+=("control-character key accepted")
	done

	# sanitize_for_display: control bytes stripped, printables intact.
	# ESC's literal "[31m" tail is deliberately not part of the input:
	# the contract strips raw control bytes only (the call sites' printf
	# '%s' handles any remaining literal backslash text).
	out=$(sanitize_for_display $'ab\ncd\033ef\tgh')
	[[ "$out" == "abcdefgh" ]] || reasons+=("sanitize_for_display: expected 'abcdefgh', got '$out'")
	out=$(sanitize_for_display "plain-key.just")
	[[ "$out" == "plain-key.just" ]] || reasons+=("sanitize_for_display mangled plain text: '$out'")

	if [[ ${#reasons[@]} -eq 0 ]]; then
		echo -e "${GREEN}✓${NORMAL} security_boundary_selftest"
		(( passed += 1 ))
	else
		echo -e "${RED}✗${NORMAL} security_boundary_selftest"
		local reason
		for reason in "${reasons[@]}"; do
			echo "    $reason"
		done
		(( failed += 1 ))
	fi
}

# Recipe mode: run the real `just <recipe> <args...>` inside a temp
# workspace that mirrors a derived repo (minimal justfile importing a
# copy of the real template-sync.just + common.sh), with mocked curl
# serving the fixture manifest/template versions.
run_recipe_test() {
	local test_name="$1"
	local test_dir="$2"

	if ! command -v just &>/dev/null; then
		echo -e "${YELLOW}!${NORMAL} $test_name - just not installed, recipe gate untested"
		(( failed += 1 ))
		return
	fi

	# Create temp workspace
	local workspace
	workspace=$(mktemp -d)

	# Copy input files to workspace (including hidden files)
	if [[ -d "$test_dir/input" ]]; then
		shopt -s dotglob
		cp -r "$test_dir/input/"* "$workspace/" 2>/dev/null || true
		shopt -u dotglob
	fi

	# Scaffold a minimal derived-repo justfile importing the real modules.
	# Fixture `modules` picks which (default: template-sync); fixture
	# `bare_justfile` drops the `set positional-arguments` line so the
	# workspace mirrors a derived repo's justfile exactly (#367/#368)
	local module_list="template-sync"
	if [[ -f "$test_dir/modules" ]]; then
		if [[ ! -s "$test_dir/modules" ]]; then
			echo -e "${RED}✗${NORMAL} $test_name - modules file is empty"
			rm -rf "$workspace"
			(( failed += 1 ))
			return
		fi
		module_list=$(cat "$test_dir/modules")
	fi
	mkdir -p "$workspace/.just/lib"
	local module
	for module in $module_list; do
		if [[ ! -f "$SCRIPT_DIR/../$module.just" ]]; then
			echo -e "${RED}✗${NORMAL} $test_name - unknown module: $module"
			rm -rf "$workspace"
			(( failed += 1 ))
			return
		fi
		cp "$SCRIPT_DIR/../$module.just" "$workspace/.just/"
	done
	cp "$SCRIPT_DIR/common.sh" "$workspace/.just/lib/"
	{
		if [[ ! -f "$test_dir/bare_justfile" ]]; then
			echo "set positional-arguments := true"
		fi
		for module in $module_list; do
			echo "import '.just/$module.just'"
		done
	} > "$workspace/justfile"

	# Mock curl serving fixture data (shared contract - see write_mock_curl)
	write_mock_curl "$workspace"

	# Fixture shims: copied in executable and prepended to PATH below,
	# ahead of the harness mock curl (whole-workspace dir first on PATH)
	if [[ -d "$test_dir/shims" ]]; then
		local shim
		for shim in "$test_dir"/shims/*; do
			[[ -f "$shim" ]] || continue
			cp "$shim" "$workspace/"
			chmod +x "$workspace/$(basename "$shim")"
		done
	fi

	# Copy manifest + template versions (curl mock resolves these)
	[[ -f "$test_dir/manifest.json" ]] && cp "$test_dir/manifest.json" "$workspace/"
	if [[ -d "$test_dir/template_versions" ]]; then
		mkdir -p "$workspace/template_versions"
		cp -r "$test_dir/template_versions/"* "$workspace/template_versions/" 2>/dev/null || true
	fi

	# Parse the recipe line: first word = recipe name, rest = arguments.
	# Guard against an empty recipe file under set -u.
	local recipe_name recipe_line=()
	if [[ ! -s "$test_dir/recipe" ]]; then
		echo -e "${RED}✗${NORMAL} $test_name - recipe file is empty"
		rm -rf "$workspace"
		(( failed += 1 ))
		return
	fi
	read -r -a recipe_line <<< "$(cat "$test_dir/recipe")"
	recipe_name="${recipe_line[0]}"
	local recipe_args=("${recipe_line[@]:1}")

	# Run the recipe with the workspace first on PATH (fixture shims
	# shadow both the harness mock curl and real tools). The if/else
	# branch keeps empty-argument recipes working under set -u on bash
	# 3.2 (macOS), where "empty_array[@]" is an unbound-variable error.
	# stdin comes from the fixture's `stdin` file when present, else
	# /dev/null, so interactive prompts (copilot_rollback's selection
	# read, #382) get deterministic input and a run can never hang on a
	# TTY; recipes that never read stdin are unaffected by EOF.
	cd "$workspace"
	local output actual_exit=0
	local stdin_file="/dev/null"
	[[ -f "$test_dir/stdin" ]] && stdin_file="$test_dir/stdin"
	if [[ ${#recipe_args[@]} -gt 0 ]]; then
		output=$(PATH="$workspace:$PATH" just "$recipe_name" "${recipe_args[@]}" < "$stdin_file" 2>&1) \
			|| actual_exit=$?
	else
		output=$(PATH="$workspace:$PATH" just "$recipe_name" < "$stdin_file" 2>&1) \
			|| actual_exit=$?
	fi

	# Expected exit code (default 0)
	local expected_exit=0
	if [[ -f "$test_dir/expected_exit" ]]; then
		expected_exit=$(cat "$test_dir/expected_exit")
	fi

	# Check expected output and state through the shared helpers, so
	# the two runner modes cannot drift (#376/#377)
	match_expected_output "$output" "$test_dir" "$test_name"
	verify_expected_state "$workspace" "$test_dir"

	# Cleanup
	cd - >/dev/null
	rm -rf "$workspace"

	# Report result
	local exit_ok=true
	[[ "$actual_exit" == "$expected_exit" ]] || exit_ok=false

	if [[ "$exit_ok" == true && "$output_ok" == true && "$state_ok" == true ]]; then
		echo -e "${GREEN}✓${NORMAL} $test_name"
		(( passed += 1 ))
	else
		echo -e "${RED}✗${NORMAL} $test_name"
		[[ "$exit_ok" == false ]] && echo "    Exit mismatch: expected $expected_exit, got $actual_exit"
		[[ "$output_ok" == false ]] && { echo "    Output mismatch:"; echo "$output_mismatch"; }
		[[ "$state_ok" == false ]] && echo "    State mismatch: $state_mismatch"
		(( failed += 1 ))
	fi
}

# Update-script mode (legacy): drive a patched copy of template_update.sh
run_update_test() {
	local test_name="$1"
	local test_dir="$2"

	# Create temp workspace
	local workspace
	workspace=$(mktemp -d)

	# Copy input files to workspace (including hidden files)
	if [[ -d "$test_dir/input" ]]; then
		shopt -s dotglob
		cp -r "$test_dir/input/"* "$workspace/" 2>/dev/null || true
		shopt -u dotglob
	fi

	# Mock curl to return fixture data (shared contract - see write_mock_curl)
	write_mock_curl "$workspace"

	# Copy manifest to workspace
	if [[ -f "$test_dir/manifest.json" ]]; then
		cp "$test_dir/manifest.json" "$workspace/"
	fi

	# Copy template versions if they exist
	if [[ -d "$test_dir/template_versions" ]]; then
		mkdir -p "$workspace/template_versions"
		cp -r "$test_dir/template_versions/"* "$workspace/template_versions/" 2>/dev/null || true
	fi

	# Run update logic with mocked curl
	cd "$workspace"
	export PATH="$workspace:$PATH"

	# Copy common.sh to workspace so sourcing works
	cp "$SCRIPT_DIR/common.sh" "$workspace/"

	# Create a modified version of template_update.sh that uses our workspace
	local test_script="$workspace/test_update.sh"
	# Escape pipe characters in workspace path to prevent sed command breaking
	local escaped_workspace="${workspace//|/\\|}"
	sed 's|readonly MANIFEST_FILE=\$(mktemp)|readonly MANIFEST_FILE="'"$escaped_workspace"'/manifest.json"|g' \
		"$SCRIPT_DIR/template_update.sh" > "$test_script"
	chmod +x "$test_script"

	# Capture output
	local output
	output=$("$test_script" 2>&1 || true)

	# Check expected output and state through the shared helpers, so
	# the two runner modes cannot drift (#376/#377)
	match_expected_output "$output" "$test_dir" "$test_name"
	verify_expected_state "$workspace" "$test_dir"

	# Cleanup
	cd - >/dev/null
	rm -rf "$workspace"

	# Report result
	if [[ "$output_ok" == true && "$state_ok" == true ]]; then
		echo -e "${GREEN}✓${NORMAL} $test_name"
		(( passed += 1 ))
	else
		echo -e "${RED}✗${NORMAL} $test_name"
		[[ "$output_ok" == false ]] && { echo "    Output mismatch:"; echo "$output_mismatch"; }
		[[ "$state_ok" == false ]] && echo "    State mismatch: $state_mismatch"
		(( failed += 1 ))
	fi
}

# Main execution
main() {
	echo -e "${BLUE}Running template sync tests...${NORMAL}"
	echo

	# Check if fixtures directory exists
	if [[ ! -d "$FIXTURES_DIR" ]]; then
		echo -e "${YELLOW}No test fixtures found at $FIXTURES_DIR${NORMAL}"
		echo "Tests skipped"
		return 0
	fi

	# Self-test the matcher/state helpers before the fixture pass: the
	# mismatch diagnostics only print on failure, and no fixture is
	# supposed to fail, so the dump and state-reason paths need their
	# own coverage (review round, #433)
	harness_selftest

	# Assert the common.sh security boundary before the fixture pass:
	# validate_filepath / sanitize_for_display are the sync system's
	# actual gate (#347), and no fixture pins their rejection classes
	# individually (#382)
	security_boundary_selftest

	# Run each test
	for test_dir in "$FIXTURES_DIR"/*; do
		if [[ -d "$test_dir" ]]; then
			test_name=$(basename "$test_dir")
			run_test "$test_name"
		fi
	done

	# Summary
	echo
	echo "Results: ${GREEN}$passed passed${NORMAL}, ${RED}$failed failed${NORMAL}"

	if [[ $failed -gt 0 ]]; then
		exit 1
	fi
}

main "$@"
