#!/usr/bin/env bash
# Test suite for repo_urls.sh - org/repo extraction, URL agreement
# classification, and the clean_template [urls] repoint transform.
#
# Also drives the real `just cue-sync-from-github` recipe in a temp
# workspace (with git/gh shims first on PATH) to exercise the #420 guard
# end to end: a .repo.toml whose urls.web_url disagrees with the git
# origin remote must make the recipe refuse to sync, and a matching
# .repo.toml must sync the shimmed gh metadata through. This mirrors the
# recipe-mode coverage template_sync_test.sh added for the checksums
# gates (#354). The recipe mode needs just, cue, and jq; without them
# that section is skipped rather than failed (unit tests still run).
set -euo pipefail

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NORMAL='\033[0m'

readonly FIXTURES_DIR=".just/test/fixtures/repo_urls"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly REPO_ROOT
readonly LIB_FILE="$REPO_ROOT/.just/lib/repo_urls.sh"

passed=0
failed=0
skipped=0

# shellcheck source=.just/lib/repo_urls.sh
source "$LIB_FILE"

pass() {
	echo -e "${GREEN}✓${NORMAL} $1"
	((passed += 1))
}

fail() {
	echo -e "${RED}✗${NORMAL} $1"
	((failed += 1))
}

# Assert a pure function echoes the expected "org repo" pair for the
# given argument - or fails, when expected is the literal FAIL.
expect_pair() {
	local label="$1" func="$2" arg="$3" expected="$4"
	local actual rc=0
	actual=$("$func" "$arg" 2>/dev/null) || rc=$?

	if [[ "$expected" == "FAIL" ]]; then
		if [[ $rc -ne 0 ]]; then
			pass "$label (rejected)"
		else
			fail "$label - expected rejection, got: $actual"
		fi
	elif [[ $rc -eq 0 && "$actual" == "$expected" ]]; then
		pass "$label"
	else
		fail "$label - expected: $expected (rc 0), got: ${actual:-<none>} (rc $rc)"
	fi
}

# Assert classify_url_mismatch's verdict for two "org repo" pairs - or a
# rejection, when expected is the literal FAIL.
expect_verdict() {
	local label="$1" toml="$2" origin="$3" expected="$4"
	local actual rc=0
	actual=$(classify_url_mismatch "$toml" "$origin" 2>/dev/null) || rc=$?

	if [[ "$expected" == "FAIL" ]]; then
		if [[ $rc -ne 0 ]]; then
			pass "$label (rejected)"
		else
			fail "$label - expected rejection, got: $actual"
		fi
	elif [[ $rc -eq 0 && "$actual" == "$expected" ]]; then
		pass "$label"
	else
		fail "$label - expected: $expected (rc 0), got: ${actual:-<none>} (rc $rc)"
	fi
}

# Assert repointed_repo_toml's output for a fixture equals the matching
# .expected.toml byte for byte.
expect_repoint() {
	local fixture="$1"
	local label="$2"
	local fixture_path="$REPO_ROOT/$FIXTURES_DIR/$fixture"
	local expected_path="${fixture_path%.toml}.expected.toml"

	if [[ ! -f "$fixture_path" || ! -f "$expected_path" ]]; then
		fail "$label - missing fixture pair: $fixture"
		return
	fi

	local workspace
	workspace=$(mktemp -d -t repo_urls_repoint.XXXXXX)
	if repointed_repo_toml "$fixture_path" "other-org" "derived-repo" \
		>"$workspace/out.toml" 2>/dev/null \
		&& cmp -s "$expected_path" "$workspace/out.toml"; then
		pass "$label"
	else
		fail "$label - transformed fixture differs from expected output"
		echo "    --- diff (expected vs actual) ---"
		diff "$expected_path" "$workspace/out.toml" | sed 's/^/    /' || true
		echo "    --- end diff ---"
	fi
	rm -rf "$workspace"
}

test_normalize_remote_url() {
	local f=normalize_remote_url

	expect_pair "$f: SSH with .git" "$f" \
		'git@github.com:fini-net/template-repo.git' 'fini-net template-repo'
	expect_pair "$f: SSH without .git" "$f" \
		'git@github.com:fini-net/template-repo' 'fini-net template-repo'
	expect_pair "$f: HTTPS with .git" "$f" \
		'https://github.com/fini-net/template-repo.git' 'fini-net template-repo'
	expect_pair "$f: HTTPS without .git" "$f" \
		'https://github.com/fini-net/template-repo' 'fini-net template-repo'
	expect_pair "$f: HTTPS with trailing slash" "$f" \
		'https://github.com/fini-net/template-repo/' 'fini-net template-repo'
	expect_pair "$f: ssh:// URL form" "$f" \
		'ssh://git@github.com/fini-net/template-repo.git' 'fini-net template-repo'
	expect_pair "$f: ssh:// URL with colon" "$f" \
		'ssh://git@github.com:fini-net/template-repo.git' 'fini-net template-repo'
	expect_pair "$f: non-GitHub host tolerated" "$f" \
		'git@gitlab.example:group/project.git' 'group project'
	expect_pair "$f: no org/repo pair" "$f" 'not-a-remote' 'FAIL'
	expect_pair "$f: empty repo part" "$f" 'git@github.com:fini-net/' 'FAIL'
	expect_pair "$f: bare org, no repo" "$f" 'https://github.com/fini-net' 'FAIL'
}

test_parse_web_url() {
	local f=parse_web_url

	expect_pair "$f: plain web URL" "$f" \
		'https://github.com/fini-net/template-repo' 'fini-net template-repo'
	expect_pair "$f: trailing slash" "$f" \
		'https://github.com/fini-net/template-repo/' 'fini-net template-repo'
	expect_pair "$f: double trailing slash rejected" "$f" \
		'https://github.com/fini-net/template-repo//' 'FAIL'
	expect_pair "$f: non-GitHub host rejected" "$f" \
		'https://gitlab.com/group/project' 'FAIL'
	expect_pair "$f: missing repo rejected" "$f" \
		'https://github.com/fini-net' 'FAIL'
	expect_pair "$f: SSH remote form rejected (not a web URL)" "$f" \
		'git@github.com:fini-net/template-repo.git' 'FAIL'
	expect_pair "$f: extra path rejected" "$f" \
		'https://github.com/fini-net/template-repo/blob/main' 'FAIL'
}

test_classify_url_mismatch() {
	expect_verdict "identical pairs match" \
		'fini-net template-repo' 'fini-net template-repo' 'match'
	expect_verdict "same repo, different org is org-mismatch (fork)" \
		'someone template-repo' 'fini-net template-repo' 'org-mismatch'
	expect_verdict "different repo is name-mismatch (stale template URLs)" \
		'fini-net fini-books' 'fini-net template-repo' 'name-mismatch'
	expect_verdict "both differ is still name-mismatch" \
		'other-org fini-books' 'fini-net template-repo' 'name-mismatch'
	expect_verdict "incomplete pair rejected" \
		'' 'fini-net template-repo' 'FAIL'
}

test_repointed_repo_toml() {
	expect_repoint "active_urls.toml" \
		"active git_ssh/web_url lines repointed in place"
	expect_repoint "commented_urls.toml" \
		"commented git_ssh/web_url lines repointed and uncommented"
	expect_repoint "missing_urls.toml" \
		"absent [urls] keys get a section appended"
}

# Scaffold a workspace holding a copy of the real cue-verify.just (plus
# the modules it needs) and a fixture .repo.toml, with git/gh shims first
# on PATH. The git shim claims the origin remote is
# other-org/derived-repo; the gh shim serves fixture metadata for that
# repo and logs every call to $GH_CALL_LOG.
build_workspace() {
	local fixture="$1"
	local ws="$2"

	mkdir -p "$ws/.just/lib" "$ws/docs" "$ws/shims"
	cp "$REPO_ROOT/.just/cue-verify.just" "$ws/.just/"
	cp "$REPO_ROOT/.just/lib/repo_urls.sh" "$ws/.just/lib/"
	cp "$REPO_ROOT/.just/lib/cue_sync.awk" "$ws/.just/lib/"
	cp "$REPO_ROOT/docs/repo-toml.cue" "$ws/docs/"
	cp "$REPO_ROOT/$FIXTURES_DIR/$fixture" "$ws/.repo.toml"

	printf '%s\n' "import '.just/cue-verify.just'" >"$ws/justfile"

	cat >"$ws/shims/git" <<'EOF'
#!/usr/bin/env bash
if [[ "$1 $2" == "remote get-url" && "$3" == "origin" ]]; then
	echo "git@github.com:other-org/derived-repo.git"
	exit 0
fi
echo "git shim: unexpected call: $*" >&2
exit 1
EOF
	chmod +x "$ws/shims/git"

	cat >"$ws/shims/gh" <<EOF
#!/usr/bin/env bash
if [[ -n "\${GH_CALL_LOG:-}" ]]; then
	echo "gh \$*" >> "\$GH_CALL_LOG"
fi
if [[ "\$1 \$2" == "api repos/other-org/derived-repo" ]]; then
	printf '%s\n' '{"description": "fixture description", "topics": ["fixture-topic"]}'
	exit 0
fi
exit 1
EOF
	chmod +x "$ws/shims/gh"
}

run_recipe() {
	local ws="$1"
	(
		cd "$ws" &&
			PATH="$ws/shims:$PATH" \
				GH_CALL_LOG="$ws/gh_calls.log" \
				just cue-sync-from-github 2>&1
	)
}

recipe_tools_available() {
	local tool
	for tool in just cue jq; do
		command -v "$tool" >/dev/null 2>&1 || return 1
	done
	return 0
}

# The headline #420 case: .repo.toml still points at template-repo while
# the origin remote is a different repo, so the recipe must refuse to
# sync, leave .repo.toml untouched, and never call gh.
test_sync_refuses_stale_urls() {
	local ws out rc=0 problems=""
	local label="sync refuses stale template URLs (#420)"

	ws=$(mktemp -d -t repo_urls_stale.XXXXXX)
	build_workspace "recipe_stale_urls.toml" "$ws"

	out=$(run_recipe "$ws") || rc=$?

	[[ $rc -eq 1 ]] || problems+="exit code $rc (want 1); "
	grep -q "refusing to sync" <<<"$out" || problems+="guard message missing; "
	cmp -s "$REPO_ROOT/$FIXTURES_DIR/recipe_stale_urls.toml" "$ws/.repo.toml" \
		|| problems+=".repo.toml was modified; "
	[[ ! -e "$ws/.repo.toml.backup" ]] || problems+="backup left behind; "
	if [[ -e "$ws/gh_calls.log" ]] \
		&& grep -q "repos/fini-net/template-repo" "$ws/gh_calls.log"; then
		problems+="gh was called despite the guard; "
	fi

	if [[ -z "$problems" ]]; then
		pass "$label"
	else
		fail "$label - $problems"
		echo "    --- recipe output ---"
		echo "    ${out//$'\n'/$'\n'    }"
		echo "    --- end output ---"
	fi
	rm -rf "$ws"
}

# The healthy counterpart: URLs that agree with the origin remote sync
# the shimmed metadata through and pass the recipe's own cue-verify.
test_sync_allows_matching_urls() {
	local ws out rc=0 problems=""
	local label="sync proceeds when URLs match the origin remote"

	ws=$(mktemp -d -t repo_urls_match.XXXXXX)
	build_workspace "recipe_match_urls.toml" "$ws"

	out=$(run_recipe "$ws") || rc=$?

	[[ $rc -eq 0 ]] || problems+="exit code $rc (want 0); "
	grep -q "Successfully synced" <<<"$out" || problems+="success message missing; "
	grep -qF 'description = "fixture description"' "$ws/.repo.toml" \
		|| problems+="description not synced; "
	grep -qF 'topics = ["fixture-topic"]' "$ws/.repo.toml" \
		|| problems+="topics not synced; "
	[[ ! -e "$ws/.repo.toml.backup" ]] || problems+="backup left behind; "

	if [[ -z "$problems" ]]; then
		pass "$label"
	else
		fail "$label - $problems"
		echo "    --- recipe output ---"
		echo "    ${out//$'\n'/$'\n'    }"
		echo "    --- end output ---"
	fi
	rm -rf "$ws"
}

main() {
	echo -e "${BLUE}Running repo_urls tests...${NORMAL}"
	echo

	test_normalize_remote_url
	test_parse_web_url
	test_classify_url_mismatch
	test_repointed_repo_toml

	if recipe_tools_available; then
		test_sync_refuses_stale_urls
		test_sync_allows_matching_urls
	else
		echo -e "${YELLOW}Skipping recipe-mode tests (need just, cue, and jq on PATH)${NORMAL}"
		((skipped += 1))
	fi

	echo
	echo -e "Results: ${GREEN}$passed passed${NORMAL}, ${RED}$failed failed${NORMAL}, ${YELLOW}$skipped skipped${NORMAL}"

	if [[ $failed -gt 0 ]]; then
		exit 1
	fi
}

main "$@"
