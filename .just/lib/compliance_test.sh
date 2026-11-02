#!/usr/bin/env bash
# Test suite for the compliance_check OpenSSF heuristics (#373/#380).
#
# The portable word-boundary regexes and the media/executable
# classification are the two things that can regress invisibly: someone
# "simplifies" a boundary back to GNU \b (silently literal under the
# BSD grep macOS ships) or edits a classification pattern, and the only
# visible symptom is subtly wrong informational output. So this suite
# does not hardcode copies of the patterns - it extracts the live
# pattern strings from .just/compliance.just and exercises them:
#
#   - the CI-Tests test_cmds boundary: 'run: tox', 'jest', 'vitest',
#     'just pr_body_test' match; 'majestic' and 'adjust testing' do not
#   - the pull_request_target secrets boundary: '- ${{ secrets.A }}'
#     and 'secrets.BAR' match; 'mysecrets.foo' and 'FOOsecrets.BAR'
#     do not
#   - the sudo boundary: 'sudo', '- sudo', 'run: sudo make install'
#     match; 'sudoers' and 'pseudorandom' do not
#   - the classification pipeline (replicated here with the recipe's
#     extracted patterns) against a planted scratch git repo: a fake
#     ELF lands in executables, media files in the media count, a 1.7MB
#     blob in the large-blob count, and text files *named*
#     ELF-notes.md and PDF-spec.txt classify as neither, because
#     matching anchors to the `file` description after
#     the first ':' rather than the whole line, with a word boundary
#     required before each keyword
#
# Needs bash, grep, file, git. Without `file` or `git` the
# classification section is skipped rather than failed (the boundary
# section always runs) - except in CI, where a missing tool fails the
# suite rather than letting it pass vacuously (mirrors
# repo_toml_stub_test.sh).
set -euo pipefail

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NORMAL='\033[0m'

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly REPO_ROOT
readonly COMPLIANCE_JUST="$REPO_ROOT/.just/compliance.just"

failures=0

pass() { printf '  %bPASS%b  %s\n' "$GREEN" "$NORMAL" "$1"; }
fail() { printf '  %bFAIL%b  %s\n' "$RED" "$NORMAL" "$1"; failures=$((failures + 1)); }

# Extract the single-quoted pattern that follows a marker on a recipe
# line: grep -oE finds "<marker>'<pattern>'", cut pulls the pattern from
# between the quotes, and an optional literal filter disambiguates
# repeated markers - or pins a nominally unique one, so a new grep
# added earlier in the recipe cannot silently re-target the
# first-match extraction. A missing line or empty pattern fails the
# suite - that is the drift tripwire: this suite cannot go green while
# the recipe quietly drifts away from it. An optional fourth argument
# pins the pattern's terminal token: the marker regex stops at the
# first quote, so a single quote inside a recipe pattern would
# truncate the extraction there and silently exercise a partial
# pattern - the suffix assertion makes that fail loudly instead. An
# optional fifth argument overrides the file to scan, used by the
# quote-injection self-test. Diagnostics go to stderr so they survive
# command substitution; extraction failures never touch the failures
# counter - every caller aborts the suite on rc 1.
extract_pattern() {
	local label=$1 marker=$2 filter=${3:-} terminal=${4:-} just_file=${5:-$COMPLIANCE_JUST}
	local match pattern
	match=$(grep -oE "${marker}[^']*'" "$just_file" | grep -F "$filter" | head -1 || true)
	if [[ -z "$match" ]]; then
		printf 'extract %s: pattern not found in %s\n' "$label" "$just_file" >&2
		return 1
	fi
	pattern=$(printf '%s' "$match" | cut -d"'" -f2)
	# Suffix match, not substring: a token appearing earlier in the
	# pattern satisfies a contains-check even after truncation past it,
	# while a suffix match pins the pattern's actual end.
	if [[ -n "$terminal" && "$pattern" != *"$terminal" ]]; then
		printf 'extract %s: pattern truncated - missing terminal token %s (single quote inside the pattern?)\n' "$label" "$terminal" >&2
		return 1
	fi
	printf '%s' "$pattern"
}

# assert_matches <label> <pattern> <input> <expected>
# expected = the matching lines joined with '|' and a trailing '|',
# mirroring the tr '\n' '|' pipeline output
assert_matches() {
	local label=$1 pattern=$2 input=$3 expected=$4
	local got
	got=$(printf '%s\n' "$input" | grep -E "$pattern" | tr '\n' '|' || true)
	if [[ "$got" == "$expected" ]]; then
		pass "$label ($got)"
	else
		fail "$label: expected [$expected] got [$got]"
	fi
}

echo -e "${BLUE}Testing compliance_check heuristics...${NORMAL}"

# ---- Boundary patterns, extracted live from the recipe ----
echo "Boundary patterns (extracted from compliance.just):"

test_cmds=$(extract_pattern 'test_cmds' "test_cmds='" 'vitest' 'just [a-z0-9_-]*test') ||
	{ printf '  suite aborted: cannot proceed without the test_cmds pattern\n' >&2; exit 1; }
assert_matches 'test_cmds word boundaries' "$test_cmds" \
	'run: tox
majestic
adjust testing
just pr_body_test
jest
vitest' \
	'run: tox|just pr_body_test|jest|vitest|'

secrets_pat=$(extract_pattern 'secrets boundary' "grep -lE '" 'secrets\.' 'secrets\.') ||
	{ printf '  suite aborted: cannot proceed without the secrets pattern\n' >&2; exit 1; }
# the '${{ secrets.* }}' fixtures are literal GitHub Actions expressions,
# deliberately single-quoted so nothing expands
# shellcheck disable=SC2016
assert_matches 'secrets left boundary' "$secrets_pat" \
	'- ${{ secrets.A }}
mysecrets.foo
secrets.BAR
FOOsecrets.BAR' \
	'- ${{ secrets.A }}|secrets.BAR|'

sudo_pat=$(extract_pattern 'sudo boundary' "grep -rlE '" 'sudo' 'sudo([^a-zA-Z0-9_]|$)') ||
	{ printf '  suite aborted: cannot proceed without the sudo pattern\n' >&2; exit 1; }
assert_matches 'sudo word boundaries' "$sudo_pat" \
	'run: sudo make install
sudoers
pseudorandom
sudo
- sudo' \
	'run: sudo make install|sudo|- sudo|'

# Negative self-test for the terminal-token guard: a single quote
# inside a recipe pattern truncates the extraction at that point; the
# guard must turn that into a hard failure instead of silently
# exercising a partial pattern. Injected into a throwaway copy of
# compliance.just so the real recipe is never touched. The test
# asserts the specific truncation diagnostic rather than any failure -
# a missing marker must not masquerade as the guard firing - and fails
# loudly if the sed fixture no longer matches the recipe text. The trap
# covers the abort window between mktemp and the eager rm below.
neg_just=$(mktemp "${TMPDIR:-/tmp}/compliance-neg.XXXXXX")
trap 'rm -f "$neg_just"' EXIT
sed "s/PDF|icon resource)'/PDF|icon resource'x)/" "$COMPLIANCE_JUST" > "$neg_just"
if cmp -s "$neg_just" "$COMPLIANCE_JUST"; then
	fail "quote-injection: sed produced no change - update the injection fixture"
else
	neg_err=$(extract_pattern 'media_count' "grep -cE '" 'JPEG' 'icon resource)' "$neg_just" 2>&1 >/dev/null || true)
	if [[ "$neg_err" == *truncated* ]]; then
		pass "quote-injection: truncated media pattern fails the guard"
	else
		fail "quote-injection: expected a truncation diagnostic, got [$neg_err]"
	fi
fi
rm -f "$neg_just"

# ---- Classification pipeline vs a planted scratch repo ----
missing=""
command -v file >/dev/null 2>&1 || missing="${missing:+$missing }file"
command -v git >/dev/null 2>&1 || missing="${missing:+$missing }git"
if [[ -n "$missing" ]]; then
	if [[ -n "${CI:-}" ]]; then
		fail "classification section: missing tool(s): $missing (CI must not pass vacuously)"
	else
		echo -e "  ${YELLOW}SKIP${NORMAL}  classification section: missing tool(s): $missing, skipping (not CI)"
	fi
else
	echo "Classification pipeline (planted scratch repo):"

	exe_pat=$(extract_pattern 'executables' "grep -E '" 'Mach-O' 'MS Windows)') ||
		{ printf '  suite aborted: cannot proceed without the executables pattern\n' >&2; exit 1; }
	ico_pat=$(extract_pattern 'icon-resource exclusion' "grep -vE '" 'icon resource' 'icon resource') ||
		{ printf '  suite aborted: cannot proceed without the icon exclusion pattern\n' >&2; exit 1; }
	media_pat=$(extract_pattern 'media_count' "grep -cE '" 'JPEG' 'icon resource)') ||
		{ printf '  suite aborted: cannot proceed without the media pattern\n' >&2; exit 1; }

	scratch=$(mktemp -d "${TMPDIR:-/tmp}/compliance-test.XXXXXX")
	trap 'rm -rf "$scratch"' EXIT

	(
		cd "$scratch"
		git init -q .
		# 64-byte ELF header: enough for `file` on both BSD and GNU to
		# read e_ident/e_type/e_machine and report an ELF
		{ printf '\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00'; head -c 46 /dev/zero; } > evil.elf
		printf '\xff\xd8\xff\xe0\x00\x10JFIF' > photo.jpg
		printf 'GIF89a' > anim.gif
		printf '\x00\x00\x01\x00\x01\x00\x10\x10\x00\x00\x01\x00\x20\x00\x68\x04\x00\x00\x16\x00\x00\x00(\x00\x00\x00\x10\x00\x00\x00\x20\x00\x00\x00\x01\x00\x20\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' > favicon.ico
		# the PR #430 review regression files: `file` describes them by
		# content ("ASCII text"), the patterns must not read the path
		printf 'text about ELF binaries, named to tempt the whole-line match\n' > ELF-notes.md
		printf 'text about PDFs, named to tempt the whole-line match\n' > PDF-spec.txt
		# >1MB of zeros: `file` reports "data" on both BSD and GNU, so the
		# large-blob count gets exercised without touching media
		head -c 1765185 /dev/zero > big.bin
		git add -A
	)

	file_types=$(cd "$scratch" && git ls-files -z | xargs -0 file -- 2>/dev/null || true)
	executables=$(printf '%s\n' "$file_types" | grep -E "$exe_pat" | grep -vE "$ico_pat" | cut -d: -f1 || true)
	media_count=$(printf '%s\n' "$file_types" | grep -cE "$media_pat" || true)
	large_blobs=$(cd "$scratch" && git ls-files -z | xargs -0 wc -c 2>/dev/null | awk '$1 > 1000000 && $2 != "total" {found++} END {print found+0}')

	printf '  scratch file(1) output:\n'
	while IFS= read -r line; do
		printf '    %s\n' "$line"
	done <<<"$file_types"

	if [[ "$executables" == "evil.elf" ]]; then
		pass "executables exactly [evil.elf]; favicon.ico and ELF-notes.md stay out"
	else
		fail "executables expected exactly [evil.elf], got [$executables]"
	fi
	if [[ "$media_count" == 3 ]]; then
		pass "jpg/gif/ico -> media_count 3 (PDF-spec.txt stays out)"
	else
		fail "media_count expected 3, got [$media_count]"
	fi
	if [[ "$large_blobs" == 1 ]]; then
		pass "1.7MB blob -> large_blobs 1"
	else
		fail "large_blobs expected 1, got [$large_blobs]"
	fi
fi

echo ""
if [[ "$failures" -eq 0 ]]; then
	printf '%bAll compliance heuristic tests passed!%b\n' "$GREEN" "$NORMAL"
	exit 0
fi
printf '%bSome compliance heuristic tests failed%b\n' "$RED" "$NORMAL"
exit 1
