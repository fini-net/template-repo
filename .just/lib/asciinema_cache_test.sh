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
# keeps it), the #375 call sites (both wrappers route through the guard
# before recording), and the guard-before-recording ordering.
#
# A second recipe-mode section drives the real cue-verify recipe with
# asciinema-record = true (gh shimmed, git real) to pin the warning
# behavior Claude review of #427 item 3 asked for: a directory-only
# '.cache/' ignore rule must not trigger the "not gitignored" warning
# (the probe path is a file under the directory), and the warning must
# fire when nothing covers .cache at all.
#
# This mirrors the recipe-mode coverage repo_urls_test.sh added for
# #420. Guard cases need just and git; cue-verify cases need just, cue,
# jq, and git. Without them a section is skipped rather than failed
# (source assertions always run).
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
readonly FIXTURES_DIR=".just/test/fixtures/asciinema_cache"

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

# Build a sandbox that drives the real cue-verify recipe with the
# fixture's asciinema-record = true flag: git stays real (the workspace
# is a repo with an origin remote, so check-ignore and the #420 origin
# cross-check see genuine answers) while gh is shimmed to serve the
# [about] metadata the fixture holds. ignore_rule, when non-empty,
# becomes the workspace's entire .gitignore (and .cache/ is NOT created,
# so directory-only patterns meet a nonexistent path - the exact shape
# that produced the spurious warning Claude review of #427 item 3
# flagged).
build_verify_workspace() {
	local ws="$1" ignore_rule="$2"

	mkdir -p "$ws/.just/lib" "$ws/docs" "$ws/shims"
	cp "$REPO_ROOT/.just/cue-verify.just" "$ws/.just/"
	cp "$REPO_ROOT/.just/lib/repo_urls.sh" "$ws/.just/lib/"
	cp "$REPO_ROOT/docs/repo-toml.cue" "$ws/docs/"
	cp "$REPO_ROOT/$FIXTURES_DIR/cue_verify_record.toml" "$ws/.repo.toml"
	if [[ -n "$ignore_rule" ]]; then
		printf '%s\n' "$ignore_rule" >"$ws/.gitignore"
	fi

	printf '%s\n' "import '.just/cue-verify.just'" >"$ws/justfile"

	git -C "$ws" init -q
	git -C "$ws" remote add origin git@github.com:other-org/derived-repo.git

	write_gh_shim "$ws"
}

# The gh shim serves the [about] metadata the fixture holds, so stage 3
# passes and the output under test is purely the asciinema-record block.
write_gh_shim() {
	local ws="$1"

	cat >"$ws/shims/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1 $2" == "api repos/other-org/derived-repo" ]]; then
	printf '{"description": "%s", "topics": %s}\n' "fixture description" '["fixture-topic"]'
	exit 0
fi
exit 1
EOF
	chmod +x "$ws/shims/gh"
}

run_verify() {
	local ws="$1"

	(
		cd "$ws" || exit 1
		GIT_CEILING_DIRECTORIES="$ws" \
		GIT_CONFIG_GLOBAL=/dev/null \
		GIT_CONFIG_SYSTEM=/dev/null \
			PATH="$ws/shims:$PATH" \
			just cue-verify 2>&1
	)
}

# A directory-only '.cache/' rule with no .cache/ directory must not
# trigger the "not gitignored" warning - the child-path probe
# (.cache/x.cast) matches it (Claude review of #427, item 3).
test_verify_no_spurious_warning() {
	local ws out rc=0 problems=""
	local label="cue-verify does not warn when a .cache/ rule covers the dir"

	ws=$(mktemp -d -t asciinema_cache_vok.XXXXXX)
	build_verify_workspace "$ws" '.cache/'

	out=$(run_verify "$ws") || rc=$?

	[[ $rc -eq 0 ]] || problems+="exit code $rc (want 0); "
	grep -q "cast files may capture sensitive output" <<<"$out" \
		|| problems+="sensitive-output caveat missing; "
	if grep -q "is not gitignored" <<<"$out"; then
		problems+="spurious not-gitignored warning fired; "
	fi
	[[ ! -d "$ws/.cache" ]] || problems+="cue-verify created .cache/; "

	report_recipe_case "$label" "$problems" "$out"
	rm -rf "$ws"
}

# With nothing ignoring .cache at all, the warning must fire (and
# cue-verify still passes - it is a soft warn).
test_verify_warns_when_unignored() {
	local ws out rc=0 problems=""
	local label="cue-verify warns when nothing ignores .cache"

	ws=$(mktemp -d -t asciinema_cache_vwarn.XXXXXX)
	build_verify_workspace "$ws" ''

	out=$(run_verify "$ws") || rc=$?

	[[ $rc -eq 0 ]] || problems+="exit code $rc (want 0); "
	grep -q "is not gitignored" <<<"$out" \
		|| problems+="not-gitignored warning missing; "

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
	# match the recipe line itself, not just a prefix, so a future
	# parameter or dependency surfaces here with the actual line
	line=$(grep -nE '^pr:[[:space:]]*$' "$GH_PROCESS") \
		|| problems+="pr recipe line is not a bare 'pr:' (got: ${line:-<none>}); "
	grep -q '^_pr_inner: _has_commits' "$GH_PROCESS" \
		|| problems+="_pr_inner lost its guard; "

	report_recipe_case "$label" "$problems" "grep on .just/gh-process.just"
}

# #375: both recording wrappers must route through the guard recipe
# before recording starts (the cast is written into .cache/, so the
# ignore guarantee has to be in place before asciinema runs), and the
# sensitive-output caveat must ship with both recordings.
test_guard_call_sites() {
	local problems="" calls unordered
	local label="pr and again wrappers call the guard before recording; caveat present (#375)"

	calls=$(grep -cE '^[[:space:]]+just _ensure_cache_ignored[[:space:]]*$' "$GH_PROCESS" || true)
	[[ "$calls" -ge 2 ]] \
		|| problems+="expected at least 2 guard call sites, found $calls; "
	grep -q '^_ensure_cache_ignored:' "$GH_PROCESS" \
		|| problems+="guard recipe missing; "
	grep -q 'capture sensitive output' "$GH_PROCESS" \
		|| problems+="sensitive-output caveat missing; "

	# ordering: within each wrapper, an asciinema rec line must not
	# appear before that wrapper's guard call. Whitespace-flexible on
	# the guard so a reformat does not break the count above; the
	# awk state machine pairs rec lines with the wrapper region they
	# sit in (recipe lines 'pr:' / 'again:' start a region).
	unordered=$(awk '
		/^pr:/ { wrapper = "pr" }
		/^again:/ { wrapper = "again" }
		/^[[:space:]]+just _ensure_cache_ignored[[:space:]]*$/ { guard[wrapper] = NR }
		/asciinema rec / {
			if (wrapper != "" && !(wrapper in guard)) {
				print wrapper " records at line " NR " before its guard call"
			}
		}
	' "$GH_PROCESS")
	if [[ -n "$unordered" ]]; then
		problems+="recording starts before the guard: $unordered; "
	fi

	report_recipe_case "$label" "$problems" "grep/awk on .just/gh-process.just"
}

main() {
	echo -e "${BLUE}Running asciinema cache guard tests...${NORMAL}"
	echo

	test_pr_guard_split
	test_guard_call_sites

	if recipe_tools_available just git; then
		test_creates_gitignore
		test_appends_to_existing
		test_repairs_missing_newline
		test_noop_when_ignored_slash_cache
		test_noop_when_ignored_cache_dir
		test_noop_when_ignored_by_exclude
		test_outside_git_repo
	else
		echo -e "${YELLOW}Skipping guard recipe-mode tests (need just and git on PATH)${NORMAL}"
		((skipped += 1))
	fi

	if recipe_tools_available just cue jq git; then
		test_verify_no_spurious_warning
		test_verify_warns_when_unignored
	else
		echo -e "${YELLOW}Skipping cue-verify recipe-mode tests (need just, cue, jq, and git on PATH)${NORMAL}"
		((skipped += 1))
	fi

	echo
	echo -e "Results: ${GREEN}$passed passed${NORMAL}, ${RED}$failed failed${NORMAL}, ${YELLOW}$skipped skipped${NORMAL}"

	if [[ $failed -gt 0 ]]; then
		exit 1
	fi
}

main "$@"
