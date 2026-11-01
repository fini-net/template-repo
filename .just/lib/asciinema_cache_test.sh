#!/usr/bin/env bash
# Test suite for the asciinema recording safety guards (#374, #375).
#
# Recipe-mode cases drive the real _ensure_cache_ignored recipe from
# gh-process.just in temp workspaces (no gh shim needed - the guard
# touches only git and .gitignore):
#
#   - a repo with no .gitignore gets one created containing '/.cache',
#     and a second run is a no-op
#   - an existing .gitignore keeps its content and gains '/.cache';
#     a missing trailing newline is repaired so nothing glues together
#   - already-ignored shapes ('/.cache', '.cache/', .git/info/exclude)
#     leave .gitignore untouched
#   - outside a git repo the recipe warns and exits 0 without creating
#     .gitignore
#
# Source assertions pin the wiring in gh-process.just itself: the #374
# single-guard split (pr carries no _has_commits dependency, _pr_inner
# keeps it) and the #375 call sites (both wrappers route through the
# guard before recording).
#
# This mirrors the recipe-mode coverage repo_urls_test.sh added for
# #420. Recipe-mode cases need just and git; without them that section
# is skipped rather than failed (source assertions still run).
set -euo pipefail

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NORMAL='\033[0m'

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly REPO_ROOT
readonly GH_PROCESS="$REPO_ROOT/.just/gh-process.just"

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
	for tool in just git; do
		command -v "$tool" >/dev/null 2>&1 || return 1
	done
	return 0
}

# Build a sandbox workspace that imports the real gh-process.just.
# mode "git" (default) git-inits the workspace; mode "nogit" leaves it
# outside any git repo.
build_workspace() {
	local ws="$1" mode="${2:-git}"

	mkdir -p "$ws/.just"
	cp "$GH_PROCESS" "$ws/.just/"
	printf '%s\n' "import '.just/gh-process.just'" >"$ws/justfile"

	if [[ "$mode" == "git" ]]; then
		git -C "$ws" init -q
	fi
}

# Run the guard recipe inside a workspace. The ceiling directory keeps
# repo discovery inside the workspace, and global/system git config is
# disabled so the user's core.excludesFile cannot make .cache already
# ignored (or not) and results stay deterministic.
run_guard() {
	local ws="$1"

	(
		cd "$ws" || exit 1
		GIT_CEILING_DIRECTORIES="$ws" \
		GIT_CONFIG_GLOBAL=/dev/null \
		GIT_CONFIG_SYSTEM=/dev/null \
			just _ensure_cache_ignored 2>&1
	)
}

# No .gitignore: the recipe creates one, and a second run is a no-op.
test_creates_gitignore() {
	local ws out rc=0 problems="" second
	local label="guard creates .gitignore when absent; second run is a no-op"

	ws=$(mktemp -d -t asciinema_cache_none.XXXXXX)
	build_workspace "$ws"

	out=$(run_guard "$ws") || rc=$?

	[[ $rc -eq 0 ]] || problems+="exit code $rc (want 0); "
	[[ -d "$ws/.cache" ]] || problems+=".cache/ not created; "
	[[ -f "$ws/.gitignore" ]] || problems+=".gitignore not created; "
	grep -qx '/\.cache' "$ws/.gitignore" || problems+="'/.cache' entry missing; "
	grep -q "Added '/.cache'" <<<"$out" || problems+="append warning missing; "

	# idempotence: the second run finds .cache ignored and does nothing
	cp "$ws/.gitignore" "$ws/.gitignore.before"
	second=$(run_guard "$ws") || rc=$?
	cmp -s "$ws/.gitignore.before" "$ws/.gitignore" \
		|| problems+="second run modified .gitignore; "
	if grep -q "Added '/.cache'" <<<"$second"; then
		problems+="second run warned again; "
	fi

	report_recipe_case "$label" "$problems" "$out"
	rm -rf "$ws"
}

# Existing .gitignore: content survives, '/.cache' lands appended.
test_appends_to_existing() {
	local ws out rc=0 problems=""
	local label="guard appends to an existing .gitignore"

	ws=$(mktemp -d -t asciinema_cache_add.XXXXXX)
	build_workspace "$ws"
	printf '%s\n' '*.so' '*.dylib' >"$ws/.gitignore"

	out=$(run_guard "$ws") || rc=$?

	[[ $rc -eq 0 ]] || problems+="exit code $rc (want 0); "
	grep -qx '\*\.so' "$ws/.gitignore" || problems+="original first line lost; "
	grep -qx '\*\.dylib' "$ws/.gitignore" || problems+="original second line lost; "
	grep -qx '/\.cache' "$ws/.gitignore" || problems+="'/.cache' entry missing; "
	git -C "$ws" check-ignore -q .cache \
		|| problems+="git does not ignore .cache after the append; "

	report_recipe_case "$label" "$problems" "$out"
	rm -rf "$ws"
}

# .gitignore without a trailing newline: the append must not glue
# itself onto the last line.
test_repairs_missing_newline() {
	local ws out rc=0 problems=""
	local label="guard repairs a missing trailing newline before appending"

	ws=$(mktemp -d -t asciinema_cache_nl.XXXXXX)
	build_workspace "$ws"
	printf '%s' '*.so' >"$ws/.gitignore"

	out=$(run_guard "$ws") || rc=$?

	[[ $rc -eq 0 ]] || problems+="exit code $rc (want 0); "
	grep -qx '\*\.so' "$ws/.gitignore" \
		|| problems+="last line was lost or glued to the append; "
	grep -qx '/\.cache' "$ws/.gitignore" || problems+="'/.cache' entry missing; "

	report_recipe_case "$label" "$problems" "$out"
	rm -rf "$ws"
}

# Already ignored via '/.cache': .gitignore must come through untouched.
test_noop_when_ignored_slash_cache() {
	local ws out rc=0 problems=""
	local label="guard is a no-op when /.cache is already ignored"

	ws=$(mktemp -d -t asciinema_cache_noop.XXXXXX)
	build_workspace "$ws"
	printf '%s\n' '*.so' '/.cache' >"$ws/.gitignore"
	cp "$ws/.gitignore" "$ws/.gitignore.before"

	out=$(run_guard "$ws") || rc=$?

	[[ $rc -eq 0 ]] || problems+="exit code $rc (want 0); "
	cmp -s "$ws/.gitignore.before" "$ws/.gitignore" \
		|| problems+=".gitignore was modified; "
	[[ -d "$ws/.cache" ]] || problems+=".cache/ not created; "

	report_recipe_case "$label" "$problems" "$out"
	rm -rf "$ws"
}

# Same no-op for the '.cache/' pattern shape.
test_noop_when_ignored_cache_dir() {
	local ws out rc=0 problems=""
	local label="guard is a no-op when a .cache/ pattern is already ignored"

	ws=$(mktemp -d -t asciinema_cache_dir.XXXXXX)
	build_workspace "$ws"
	printf '%s\n' '.cache/' >"$ws/.gitignore"
	cp "$ws/.gitignore" "$ws/.gitignore.before"

	out=$(run_guard "$ws") || rc=$?

	[[ $rc -eq 0 ]] || problems+="exit code $rc (want 0); "
	cmp -s "$ws/.gitignore.before" "$ws/.gitignore" \
		|| problems+=".gitignore was modified; "

	report_recipe_case "$label" "$problems" "$out"
	rm -rf "$ws"
}

# Ignored via .git/info/exclude: no .gitignore may appear.
test_noop_when_ignored_by_exclude() {
	local ws out rc=0 problems=""
	local label="guard is a no-op when .cache/ is ignored via .git/info/exclude"

	ws=$(mktemp -d -t asciinema_cache_excl.XXXXXX)
	build_workspace "$ws"
	printf '%s\n' '.cache/' >>"$ws/.git/info/exclude"

	out=$(run_guard "$ws") || rc=$?

	[[ $rc -eq 0 ]] || problems+="exit code $rc (want 0); "
	[[ ! -f "$ws/.gitignore" ]] \
		|| problems+=".gitignore created despite the exclude rule; "

	report_recipe_case "$label" "$problems" "$out"
	rm -rf "$ws"
}

# Outside a git repo: warn, exit 0, and do not create .gitignore.
test_outside_git_repo() {
	local ws out rc=0 problems=""
	local label="guard warns and exits 0 outside a git repo"

	ws=$(mktemp -d -t asciinema_cache_norepo.XXXXXX)
	build_workspace "$ws" nogit

	out=$(run_guard "$ws") || rc=$?

	[[ $rc -eq 0 ]] || problems+="exit code $rc (want 0); "
	[[ ! -f "$ws/.gitignore" ]] || problems+=".gitignore created outside a repo; "
	grep -q "could not probe" <<<"$out" || problems+="probe warning missing; "

	report_recipe_case "$label" "$problems" "$out"
	rm -rf "$ws"
}

# #374: the guard lives on _pr_inner only - declaring it on both recipes
# ran it (and its _on_a_branch chain) twice per invocation.
test_pr_guard_split() {
	local problems="" line
	local label="pr wrapper has no _has_commits dependency; _pr_inner keeps it (#374)"

	if grep -q '^pr: _has_commits' "$GH_PROCESS"; then
		problems+="pr still declares _has_commits; "
	fi
	line=$(grep -n '^pr:' "$GH_PROCESS") || problems+="pr recipe not found; "
	[[ "$line" == *"pr:" ]] || problems+="pr carries dependencies: ${line#*:}; "
	grep -q '^_pr_inner: _has_commits' "$GH_PROCESS" \
		|| problems+="_pr_inner lost its guard; "

	report_recipe_case "$label" "$problems" "grep on .just/gh-process.just"
}

# #375: both recording wrappers must route through the guard recipe
# before recording, and the sensitive-output caveat must ship with
# both recordings.
test_guard_call_sites() {
	local problems="" calls
	local label="pr and again wrappers call the guard; caveat present (#375)"

	calls=$(grep -c '^    just _ensure_cache_ignored$' "$GH_PROCESS" || true)
	[[ "$calls" -eq 2 ]] || problems+="expected 2 guard call sites, found $calls; "
	grep -q '^_ensure_cache_ignored:' "$GH_PROCESS" \
		|| problems+="guard recipe missing; "
	grep -q 'capture sensitive output' "$GH_PROCESS" \
		|| problems+="sensitive-output caveat missing; "

	report_recipe_case "$label" "$problems" "grep on .just/gh-process.just"
}

main() {
	echo -e "${BLUE}Running asciinema cache guard tests...${NORMAL}"
	echo

	test_pr_guard_split
	test_guard_call_sites

	if recipe_tools_available; then
		test_creates_gitignore
		test_appends_to_existing
		test_repairs_missing_newline
		test_noop_when_ignored_slash_cache
		test_noop_when_ignored_cache_dir
		test_noop_when_ignored_by_exclude
		test_outside_git_repo
	else
		echo -e "${YELLOW}Skipping recipe-mode tests (need just and git on PATH)${NORMAL}"
		((skipped += 1))
	fi

	echo
	echo -e "Results: ${GREEN}$passed passed${NORMAL}, ${RED}$failed failed${NORMAL}, ${YELLOW}$skipped skipped${NORMAL}"

	if [[ $failed -gt 0 ]]; then
		exit 1
	fi
}

main "$@"
