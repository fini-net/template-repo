#!/usr/bin/env bash
# Test suite for the repo-toml shellcheck stub sandboxing (#372).
#
# Recipe-mode cases drive the real shellcheck recipe in a temp workspace
# with a failing cue shim first on PATH (deterministic on machines that
# do have cue - CI installs it), so repo_toml_generate fails and the
# recipe's fallback stub path is exercised:
#
#   - the lint still passes (shellcheck resolves the recipes'
#     'source .just/repo-toml.sh' lines through the sandboxed stub via
#     -P, so no SC1091/SC2154 noise), and
#   - the real .just/repo-toml.sh path is NOT created - pre-v10.2 the
#     stub landed there, repo_toml_check's -nt test read it as fresh,
#     and every sourcing recipe inherited its default FLAG_* values
#
# A second recipe-mode section drives the real repo_toml_check:
#
#   - a stub-marked file (fresh, so -nt alone would pass) must be
#     rejected as a shellcheck stub - the legacy-checkout heal
#   - a generated-looking file passes when fresh, is flagged stale when
#     .repo.toml is newer, and a missing file still fails (pins the
#     pre-existing behavior)
#
# Source assertions pin the wiring in shellcheck.just and repo-toml.just:
# the stub write target lives under CHECKS_TMPDIR, no write to the real
# path remains, the shellcheck invocation carries -P, and the sentinel
# grep runs before the -nt staleness test.
#
# The recipe modes need just and shellcheck; without them a section is
# skipped rather than failed (source assertions always run).
set -euo pipefail

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NORMAL='\033[0m'

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly REPO_ROOT
readonly SHELLCHECK_JUST="$REPO_ROOT/.just/shellcheck.just"
readonly REPO_TOML_JUST="$REPO_ROOT/.just/repo-toml.just"

passed=0
failed=0
skipped=0

pass() {
	echo -e "${GREEN}✓${NORMAL} $1"
	((passed += 1))
}

fail() {
	echo -e "${RED}✗${NORMAL} $1"
	((failed += 1))
}

# Report a recipe-mode case: $1 label, $2 accumulated problem string,
# $3 captured recipe output (printed on failure for debugging).
report_recipe_case() {
	local label="$1" problems="$2" out="$3"

	if [[ -z "$problems" ]]; then
		pass "$label"
	else
		fail "$label - $problems"
		echo "    --- recipe output ---"
		echo "    ${out//$'\n'/$'\n'    }"
		echo "    --- end output ---"
	fi
}

recipe_tools_available() {
	local tool
	for tool in "$@"; do
		command -v "$tool" >/dev/null 2>&1 || return 1
	done
	return 0
}

# Build a workspace whose shellcheck recipe is the real one, with
# gh-process.just present so the extracted recipes genuinely contain
# 'source .just/repo-toml.sh' lines for the sandboxed stub to satisfy.
# A real .repo.toml plus the cue schema makes repo_toml_generate fail at
# 'cue vet' under the shim - the same exit-1 path as a machine without
# cue - instead of failing earlier on a missing file.
build_shellcheck_workspace() {
	local ws="$1"

	mkdir -p "$ws/.just" "$ws/docs" "$ws/shims"
	cp "$SHELLCHECK_JUST" "$ws/.just/"
	cp "$REPO_TOML_JUST" "$ws/.just/"
	cp "$REPO_ROOT/.just/gh-process.just" "$ws/.just/"
	cp "$REPO_ROOT/docs/repo-toml.cue" "$ws/docs/"
	cp "$REPO_ROOT/.repo.toml" "$ws/.repo.toml"

	{
		printf '%s\n' "import '.just/shellcheck.just'"
		printf '%s\n' "import '.just/repo-toml.just'"
		printf '%s\n' "import '.just/gh-process.just'"
	} >"$ws/justfile"

	write_cue_shim "$ws"
}

# A cue shim first on PATH that always fails: repo_toml_generate exits
# nonzero at 'cue vet' exactly like a missing or broken cue would, on
# machines where the real cue is installed too.
write_cue_shim() {
	local ws="$1"

	cat >"$ws/shims/cue" <<'EOF'
#!/usr/bin/env bash
echo "cue shim: forcing repo_toml_generate failure (#372 test)" >&2
exit 1
EOF
	chmod +x "$ws/shims/cue"
}

# Build a minimal workspace around the real repo_toml_check. The
# .repo.toml content is irrelevant to the recipe (only its mtime
# matters for the -nt test), but the file must exist for staleness
# semantics.
build_check_workspace() {
	local ws="$1"

	mkdir -p "$ws/.just"
	cp "$REPO_TOML_JUST" "$ws/.just/"
	printf '%s\n' "import '.just/repo-toml.just'" >"$ws/justfile"
	printf '%s\n' "# placeholder - only mtime matters to repo_toml_check" >"$ws/.repo.toml"
}

# The first line of the stub the pre-v10.2 shellcheck recipe wrote to
# the real path - the marker repo_toml_check now refuses.
write_stub_file() {
	local ws="$1"

	{
		echo "# Stub written by 'just shellcheck' - generation failed"
		echo "FLAG_CLAUDE=false"
	} >"$ws/.just/repo-toml.sh"
}

# A plausible generated file - the header repo_toml_generate writes.
write_generated_file() {
	local ws="$1"

	{
		echo "# Auto-generated from .repo.toml by 'just repo_toml_generate'"
		echo "FLAG_CLAUDE=true"
	} >"$ws/.just/repo-toml.sh"
}

run_shellcheck_recipe() {
	local ws="$1"

	(
		cd "$ws" || exit 1
		PATH="$ws/shims:$PATH" just shellcheck 2>&1
	)
}

run_check_recipe() {
	local ws="$1"

	(
		cd "$ws" || exit 1
		just repo_toml_check 2>&1
	)
}

# #372 source assertion: the stub must be written under CHECKS_TMPDIR
# (never to the real .just/repo-toml.sh path) and the shellcheck
# invocation must carry -P so the sandboxed stub resolves the recipes'
# source lines for this run only.
test_stub_sandboxed_in_source() {
	local problems=""
	local label="shellcheck.just writes the stub to the temp dir and lints with -P (#372)"

	# SC2016: the $ literals are the point - grep must see the
	# unexpanded pattern to pin the write target and -P wiring
	# shellcheck disable=SC2016
	grep -q '} > "$CHECKS_TMPDIR/.just/repo-toml.sh"' "$SHELLCHECK_JUST" \
		|| problems+="stub write target is not CHECKS_TMPDIR/.just/repo-toml.sh; "
	# shellcheck disable=SC2016
	grep -q 'shellcheck -x -P "$CHECKS_TMPDIR" -s bash' "$SHELLCHECK_JUST" \
		|| problems+="shellcheck invocation lost -P; "
	if grep -q '> \.just/repo-toml\.sh' "$SHELLCHECK_JUST"; then
		problems+="a write to the real .just/repo-toml.sh path remains; "
	fi

	report_recipe_case "$label" "$problems" "grep on .just/shellcheck.just"
}

# #372 source assertion: repo_toml_check must refuse stub-marked files
# before the -nt staleness test can read a fresh stub as up-to-date.
test_sentinel_before_staleness() {
	local problems="" order
	local label="repo_toml_check refuses stubs before the -nt staleness test (#372)"

	grep -q '# Stub written by' "$REPO_TOML_JUST" \
		|| problems+="stub sentinel grep missing; "
	grep -q '\-nt .just/repo-toml\.sh' "$REPO_TOML_JUST" \
		|| problems+="staleness test missing; "

	# ordering: the sentinel check must precede the -nt test - a fresh
	# stub passes -nt, so the sentinel is the only line that can catch it
	order=$(awk '
		/# Stub written by/ { if (!stub) stub = NR }
		/-nt \.just\/repo-toml\.sh/ { if (!nt) nt = NR }
		END {
			if (stub && nt && stub > nt)
				print "sentinel at line " stub " after staleness test at line " nt
		}
	' "$REPO_TOML_JUST")
	[[ -z "$order" ]] || problems+="sentinel runs after staleness test: $order; "

	report_recipe_case "$label" "$problems" "grep/awk on .just/repo-toml.just"
}

# #372 core: with generation forced to fail, the lint must still pass
# AND leave no file at the real .just/repo-toml.sh path.
test_stub_never_touches_real_path() {
	local ws out rc=0 problems=""
	local label="failed generation: lint passes, real .just/repo-toml.sh untouched (#372)"

	ws=$(mktemp -d -t repo_toml_stub_lint.XXXXXX)
	build_shellcheck_workspace "$ws"

	out=$(run_shellcheck_recipe "$ws") || rc=$?

	[[ $rc -eq 0 ]] || problems+="exit code $rc (want 0); "
	[[ ! -e "$ws/.just/repo-toml.sh" ]] \
		|| problems+="real .just/repo-toml.sh was created by the stub path; "
	grep -q "could not generate .just/repo-toml.sh" <<<"$out" \
		|| problems+="generation-failure warning missing; "
	if grep -qE "SC1091|SC2154" <<<"$out"; then
		problems+="SC1091/SC2154 noise - sandboxed stub not followed; "
	fi

	report_recipe_case "$label" "$problems" "$out"
	rm -rf "$ws"
}

# A stub written by a pre-v10.2 shellcheck run sits fresh at the real
# path: -nt alone would call it up-to-date, so the sentinel must refuse
# it (the legacy-checkout heal).
test_check_rejects_stub() {
	local ws out rc=0 problems=""
	local label="repo_toml_check rejects a fresh stub at the real path (#372)"

	ws=$(mktemp -d -t repo_toml_stub_sent.XXXXXX)
	build_check_workspace "$ws"
	sleep 1 # ensure the stub is newer than .repo.toml, so -nt passes
	write_stub_file "$ws"

	out=$(run_check_recipe "$ws") || rc=$?

	[[ $rc -eq 1 ]] || problems+="exit code $rc (want 1); "
	grep -q "shellcheck stub" <<<"$out" \
		|| problems+="stub rejection message missing; "
	grep -q "repo_toml_generate" <<<"$out" \
		|| problems+="regenerate hint missing; "
	if grep -q "up-to-date" <<<"$out"; then
		problems+="stub passed as up-to-date; "
	fi

	report_recipe_case "$label" "$problems" "$out"
	rm -rf "$ws"
}

# Control: a fresh generated-looking file still passes.
test_check_passes_fresh_generated() {
	local ws out rc=0 problems=""
	local label="repo_toml_check still accepts a fresh generated file"

	ws=$(mktemp -d -t repo_toml_stub_ok.XXXXXX)
	build_check_workspace "$ws"
	sleep 1 # ensure the file is newer than .repo.toml
	write_generated_file "$ws"

	out=$(run_check_recipe "$ws") || rc=$?

	[[ $rc -eq 0 ]] || problems+="exit code $rc (want 0); "
	grep -q "up-to-date" <<<"$out" \
		|| problems+="up-to-date message missing; "

	report_recipe_case "$label" "$problems" "$out"
	rm -rf "$ws"
}

# Control: a missing file still fails (pins the pre-existing branch).
test_check_fails_missing_file() {
	local ws out rc=0 problems=""
	local label="repo_toml_check still fails when the file is missing"

	ws=$(mktemp -d -t repo_toml_stub_missing.XXXXXX)
	build_check_workspace "$ws"

	out=$(run_check_recipe "$ws") || rc=$?

	[[ $rc -eq 1 ]] || problems+="exit code $rc (want 1); "
	grep -q "not found" <<<"$out" \
		|| problems+="not-found message missing; "

	report_recipe_case "$label" "$problems" "$out"
	rm -rf "$ws"
}

# Control: staleness detection still fires when .repo.toml is newer
# than a non-stub file - the sentinel guard must not mask it.
test_check_flags_stale_generated() {
	local ws out rc=0 problems=""
	local label="repo_toml_check still flags a stale generated file"

	ws=$(mktemp -d -t repo_toml_stub_stale.XXXXXX)
	build_check_workspace "$ws"
	write_generated_file "$ws"
	sleep 1 # ensure .repo.toml becomes newer
	touch "$ws/.repo.toml"

	out=$(run_check_recipe "$ws") || rc=$?

	[[ $rc -eq 1 ]] || problems+="exit code $rc (want 1); "
	grep -q "stale" <<<"$out" \
		|| problems+="stale message missing; "

	report_recipe_case "$label" "$problems" "$out"
	rm -rf "$ws"
}

main() {
	echo -e "${BLUE}Running repo_toml stub tests...${NORMAL}}"
	echo

	test_stub_sandboxed_in_source
	test_sentinel_before_staleness

	if recipe_tools_available just shellcheck; then
		test_stub_never_touches_real_path
	else
		echo -e "${YELLOW}Skipping shellcheck recipe-mode test (need just and shellcheck on PATH)${NORMAL}"
		((skipped += 1))
	fi

	if recipe_tools_available just; then
		test_check_rejects_stub
		test_check_passes_fresh_generated
		test_check_fails_missing_file
		test_check_flags_stale_generated
	else
		echo -e "${YELLOW}Skipping repo_toml_check recipe-mode tests (need just on PATH)${NORMAL}"
		((skipped += 1))
	fi

	echo
	echo -e "Results: ${GREEN}$passed passed${NORMAL}, ${RED}$failed failed${NORMAL}, ${YELLOW}$skipped skipped${NORMAL}"

	if [[ $failed -gt 0 ]]; then
		exit 1
	fi
}

main "$@"
