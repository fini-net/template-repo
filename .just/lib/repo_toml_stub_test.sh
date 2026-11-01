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
# no write to the real path remains, the shellcheck invocation carries
# -P/--source-path, the sentinel grep runs before the -nt staleness
# test, and the stub's variable list covers exactly what
# repo_toml_generate emits - the two hand-maintained lists are the
# remaining duplication from #372, so drift fails here instead of
# waiting for a cue-less machine to notice. A unit-level precedence pin
# drives the real shellcheck binary: a clean real file at the
# invocation cwd must win over a deliberately broken stub sitting at
# the sandbox candidates, which is what makes passing -P unconditionally
# safe (Claude review round 2 on #428).
#
# The recipe modes need just and shellcheck; without them a section is
# skipped rather than failed (source assertions always run) - except in
# CI, where a missing tool fails the suite rather than letting it pass
# vacuously (this is the only regression coverage for #372).
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

# Fixed mtimes instead of sleep for the -nt orderings: deterministic
# even on coarse-mtime filesystems and no suite slowdown. Portable
# BSD+GNU touch -t form [[CC]YY]MMDDhhmm (Claude review of #428).
readonly STAMP_OLD="202601010000"
readonly STAMP_NEW="202601010001"
readonly STAMP_NEWEST="202601010002"

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

# A plausible generated file - the header repo_toml_generate writes,
# with the full variable set so recipes lint clean against it.
write_generated_file() {
	local ws="$1"

	{
		echo "# Auto-generated from .repo.toml by 'just repo_toml_generate'"
		echo "REPO_DESCRIPTION='test'"
		echo "REPO_LICENSE='GPL-2.0-only'"
		echo "REPO_TOPICS=test"
		echo "REPO_GIT_SSH='git@github.com:fini-net/template-repo.git'"
		echo "REPO_WEB_URL='https://github.com/fini-net/template-repo'"
		echo "REPO_ORG_NAME=fini-net"
		echo "REPO_REPO_NAME=template-repo"
		echo "FLAG_CLAUDE=true"
		echo "FLAG_CLAUDE_REVIEW=true"
		echo "FLAG_COPILOT_REVIEW=true"
		echo "FLAG_STANDARD_RELEASE=true"
		echo "FLAG_ASCIINEMA_RECORD=false"
		echo "REPO_TOPICS_ARRAY=("
		echo "    'test'"
		echo ")"
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

# #372 source assertion: no write to the bare real path may remain
# (backstop grep for the common redirect forms - the behavioral test
# is the guarantee, since a determined refactor could route around any
# grep), and the shellcheck invocation must carry -P/--source-path
# pointing at CHECKS_TMPDIR (loose on flag order and long form, and
# comment lines do not count - only the real invocation satisfies it;
# Claude review of #428).
test_stub_sandboxed_in_source() {
	local problems=""
	local label="shellcheck.just lints with -P/--source-path and never writes the real path (#372)"

	awk '
		$0 !~ /^[[:space:]]*#/ && /shellcheck/ && /(-P|--source-path)/ && /CHECKS_TMPDIR/ { found = 1 }
		END { exit !found }
	' "$SHELLCHECK_JUST" \
		|| problems+="shellcheck invocation lost -P/--source-path; "
	# comment lines do not count here either; a write routed through a
	# variable ("> $f") is beyond any static grep - the behavioral test
	# is the guarantee, this is the backstop
	if awk '
		$0 !~ /^[[:space:]]*#/ && />[[:space:]]*\.just\/repo-toml\.sh/ { found = 1 }
		END { exit !found }
	' "$SHELLCHECK_JUST"; then
		problems+="a write to the real .just/repo-toml.sh path remains; "
	fi

	report_recipe_case "$label" "$problems" "grep/awk on .just/shellcheck.just"
}

# The stub's variable list and repo_toml_generate's emit block are the
# two hand-maintained lists from #372 - this pins them together so
# adding a variable to the generator without the stub (or vice versa)
# fails the suite instead of surfacing as SC2154 noise on cue-less
# machines (Claude review of #428).
test_stub_covers_generated_variables() {
	local problems="" gen_vars stub_vars only_gen only_stub
	local label="stub variable list matches repo_toml_generate's output set"

	gen_vars=$(grep -oE 'echo "(REPO_[A-Z_]+|FLAG_[A-Z_]+)=' "$REPO_TOML_JUST" \
		| sed 's/^echo "//; s/=$//' | sort -u)
	stub_vars=$(grep -oE 'echo "(REPO_[A-Z_]+|FLAG_[A-Z_]+)=' "$SHELLCHECK_JUST" \
		| sed 's/^echo "//; s/=$//' | sort -u)

	[[ -n "$gen_vars" ]] \
		|| problems+="no variables extracted from repo_toml_generate; "
	[[ -n "$stub_vars" ]] \
		|| problems+="no variables extracted from the stub; "
	if [[ -n "$gen_vars" && -n "$stub_vars" && "$gen_vars" != "$stub_vars" ]]; then
		only_gen=$(comm -23 <(printf '%s\n' "$gen_vars") <(printf '%s\n' "$stub_vars") | tr '\n' ' ')
		only_stub=$(comm -13 <(printf '%s\n' "$gen_vars") <(printf '%s\n' "$stub_vars") | tr '\n' ' ')
		problems+="sets differ (generate-only: ${only_gen:-none} stub-only: ${only_stub:-none}); "
	fi

	report_recipe_case "$label" "$problems" "grep on .just/repo-toml.just + .just/shellcheck.just"
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

# Precedence pin (Claude review round 2 on #428): the unconditional -P
# is safe only because shellcheck resolves a relative source path
# against the invocation cwd first. Recreate the recipe's layout -
# script inside the -P dir, clean real file at cwd, deliberately
# broken stub at the sandbox candidate - and require the real file to
# win. If a future shellcheck changes the resolution order, the broken
# stub surfaces as a syntax error and this fails, long before the
# recipe's own comment about the resolution order goes stale.
test_real_file_wins_over_sandbox_candidates() {
	local cwddir pdir out rc=0 problems=""
	local label="real .just/repo-toml.sh wins over the sandboxed candidates"

	cwddir=$(mktemp -d -t repo_toml_prec_cwd.XXXXXX)
	pdir=$(mktemp -d -t repo_toml_prec_pdir.XXXXXX)
	mkdir -p "$cwddir/.just" "$pdir/.just"
	printf '%s\n' "# clean real file" "FLAG_CLAUDE=true" >"$cwddir/.just/repo-toml.sh"
	printf '%s\n' "# BROKEN stub" 'FLAG_CLAUDE="unterminated' >"$pdir/.just/repo-toml.sh"
	# SC2016: the $ literals are literal script content written to the
	# probe file - they must not expand
	# shellcheck disable=SC2016
	printf '%s\n' '#!/usr/bin/env bash' 'source .just/repo-toml.sh' 'echo "$FLAG_CLAUDE"' \
		>"$pdir/script_1.sh"

	out=$(cd "$cwddir" && shellcheck -x -P "$pdir" -s bash "$pdir/script_1.sh" 2>&1) || rc=$?

	[[ $rc -eq 0 ]] || problems+="exit code $rc (want 0 - the broken stub was followed); "

	report_recipe_case "$label" "$problems" "$out"
	rm -rf "$cwddir" "$pdir"
}

# Control (Claude review round 2 on #428): when the real file exists,
# the stub branch never runs and the lint follows the real file - no
# generation warning, no stub warning, no SC1091/SC2154 noise.
test_real_file_present_lints_against_it() {
	local ws out rc=0 problems=""
	local label="real .just/repo-toml.sh present: lint passes without the stub branch"

	ws=$(mktemp -d -t repo_toml_stub_real.XXXXXX)
	build_shellcheck_workspace "$ws"
	write_generated_file "$ws"

	out=$(run_shellcheck_recipe "$ws") || rc=$?

	[[ $rc -eq 0 ]] || problems+="exit code $rc (want 0); "
	if grep -q "not found - generating" <<<"$out"; then
		problems+="guard wrongly treated the real file as missing; "
	fi
	if grep -q "Writing a stub" <<<"$out"; then
		problems+="stub branch ran although the real file existed; "
	fi
	if grep -qE "SC1091|SC2154" <<<"$out"; then
		problems+="SC1091/SC2154 noise - real file not followed; "
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
	touch -t "$STAMP_OLD" "$ws/.repo.toml"
	write_stub_file "$ws"
	touch -t "$STAMP_NEW" "$ws/.just/repo-toml.sh" # newer than .repo.toml, so -nt passes

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
	touch -t "$STAMP_OLD" "$ws/.repo.toml"
	write_generated_file "$ws"
	touch -t "$STAMP_NEW" "$ws/.just/repo-toml.sh" # newer than .repo.toml

	out=$(run_check_recipe "$ws") || rc=$?

	[[ $rc -eq 0 ]] || problems+="exit code $rc (want 0); "
	grep -q "up-to-date" <<<"$out" \
		|| problems+="up-to-date message missing; "

	report_recipe_case "$label" "$problems" "$out"
	rm -rf "$ws"
}

# Control (Claude review round 3 on #428): the sentinel matches the
# stub marker only as the file's FIRST line - the shape every stub
# written by v10.1-and-earlier had. A marker buried mid-file is a hand
# edit and must not brick a legitimate file.
test_check_ignores_midfile_stub_marker() {
	local ws out rc=0 problems=""
	local label="repo_toml_check ignores a stub marker that is not the first line"

	ws=$(mktemp -d -t repo_toml_stub_mid.XXXXXX)
	build_check_workspace "$ws"
	touch -t "$STAMP_OLD" "$ws/.repo.toml"
	{
		echo "# Auto-generated from .repo.toml by 'just repo_toml_generate'"
		echo "# Stub written by 'just shellcheck' - hand edit, not a stub"
		echo "FLAG_CLAUDE=true"
	} >"$ws/.just/repo-toml.sh"
	touch -t "$STAMP_NEW" "$ws/.just/repo-toml.sh" # newer than .repo.toml

	out=$(run_check_recipe "$ws") || rc=$?

	[[ $rc -eq 0 ]] || problems+="exit code $rc (want 0); "
	if grep -q "shellcheck stub" <<<"$out"; then
		problems+="mid-file marker was treated as a stub; "
	fi

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
	touch -t "$STAMP_NEW" "$ws/.just/repo-toml.sh"
	touch -t "$STAMP_NEWEST" "$ws/.repo.toml" # newer than the file

	out=$(run_check_recipe "$ws") || rc=$?

	[[ $rc -eq 1 ]] || problems+="exit code $rc (want 1); "
	grep -q "stale" <<<"$out" \
		|| problems+="stale message missing; "

	report_recipe_case "$label" "$problems" "$out"
	rm -rf "$ws"
}

# Gate a recipe-mode section on its tools: skip with a note when a tool
# is missing, but fail in CI - a missing tool would otherwise let the
# suite pass vacuously, and this is the only regression coverage for
# #372 (Claude review of #428). Returns 0 (run the section) or 1
# (section not run).
skip_or_require_tools() {
	local section="$1"
	shift

	if recipe_tools_available "$@"; then
		return 0
	fi
	if [[ -n "${CI:-}" ]]; then
		fail "$section must run in CI: missing tool(s) among: $* - this suite does not pass vacuously"
		return 1
	fi
	echo -e "${YELLOW}Skipping $section (need: $*)${NORMAL}"
	((skipped += 1))
	return 1
}

main() {
	echo -e "${BLUE}Running repo_toml stub tests...${NORMAL}"
	echo

	test_stub_sandboxed_in_source
	test_sentinel_before_staleness
	test_stub_covers_generated_variables

	if skip_or_require_tools "shellcheck recipe-mode test" just shellcheck; then
		test_stub_never_touches_real_path
		test_real_file_present_lints_against_it
	fi

	if skip_or_require_tools "shellcheck precedence test" shellcheck; then
		test_real_file_wins_over_sandbox_candidates
	fi

	if skip_or_require_tools "repo_toml_check recipe-mode tests" just; then
		test_check_rejects_stub
		test_check_ignores_midfile_stub_marker
		test_check_passes_fresh_generated
		test_check_fails_missing_file
		test_check_flags_stale_generated
	fi

	echo
	echo -e "Results: ${GREEN}$passed passed${NORMAL}, ${RED}$failed failed${NORMAL}, ${YELLOW}$skipped skipped${NORMAL}"

	if [[ $failed -gt 0 ]]; then
		exit 1
	fi
}

main "$@"
