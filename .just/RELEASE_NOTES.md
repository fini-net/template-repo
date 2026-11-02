# Release Notes: gh-process.just

This file tracks the evolution of the Git/GitHub workflow automation module.

## November 2026

### v10.8 - release accepts semver pre-release/build tags (2026-11-02)

- Fixes issue [#379](https://github.com/fini-net/template-repo/issues/379)
- **Related PR:** [#437](https://github.com/fini-net/template-repo/pull/437)

**`just release` accepts `v1.0.0-rc1` and `v1.0.0+build.5` again.** The
v9.7 quote-injection hardening (#359) tightened the release version
regex to `^v[0-9]+(\.[0-9]+){0,2}$`, silently rejecting semver
pre-release and build-metadata tags the old loose `^v[0-9]` check had
allowed. The rejection was deliberate - the v9.7 entry below says so -
but it was documented only in these notes, not in the recipe comment
or the error message, so two v9.9 sync reviews
([fini-domains#62](https://github.com/fini-net/fini-domains/pull/62#issuecomment-5717899954),
[fini-projects#34](https://github.com/fini-net/fini-projects/pull/34#issuecomment-5670582615))
could not tell rejection-by-design from breakage. The regex now takes
optional `-prerelease` and `+build` suffixes -
`^v[0-9]+(\.[0-9]+){0,2}(-[0-9A-Za-z.-]+)?([+][0-9A-Za-z.-]+)?$` -
each independently optional, so `v1`, `v1.0`, `v1.0.0`, `v1.0.0-rc1`,
`v1.0.0+build.5` and both suffixes together all pass.

**The #359 guard is unchanged in strength.** The suffix character
classes admit no shell metacharacters - alphanumerics, hyphen, dot,
and a bracketed `[+]` (the escaped `\+` spelling happens to work on
glibc and macOS libc alike, but the class form is unambiguous
everywhere) - and both anchors stay, so the original
`v1"; touch /tmp/pwned #` payload still fails validation.
`rel_version` continues to flow only into the quoted
`gh release create "$rel_version"` call. This is a grammar guard, not
a semver validator: degenerate but metacharacter-free suffixes like
`v1.0.0--` pass, and the recipe comment says so.

**Accepting at the template level beats documenting the rejection.**
The v9.7 entry called loosening a one-line change for any repo that
ever needs pre-releases, but for derived repos it is not:
`gh-process.just` is CHECKSUMS-tracked, so a locally loosened line
would show up as modified-file drift in `checksums_verify` and
template sync - the template would be advising an edit its own drift
detector flags. Template-repo itself keeps its plain `vX`/`vX.Y` tag
history and simply never uses the suffixes. The error message now
states the full accepted grammar with examples, so any future
rejection is self-explanatory either way.

**Fixtures pin both acceptances and a rejection.** Two new recipe
fixtures reuse the fixture-12 gh/git shim pattern to drive the real
recipe: `17_recipe_release_prerelease_accept` asserts `release
v1.0.0-rc1` reaches `gh release create` intact, and
`18_recipe_release_buildmeta_accept` does the same for
`v1.0.0+build.5` - a tag the old regex could never admit.
`19_recipe_release_reject` feeds the single-token injection probe
`v1.0.0";touch${IFS}pwn#` - the shape of the original #359 payload,
squeezed into one token because the harness parses the fixture recipe
line by whitespace - and asserts the grammar error and exit 1. All
three feed versions through the real regex in the real recipe, so
loosening can never silently lose a rejection class.

**Monotonic ordering deliberately deferred.** The #379 thread also
surfaced that `release` never checks that the new version sorts after
the previous one - `v1.0.0` after `v1.2.0` succeeds today, and GitHub
marks the newest created release as latest regardless of version
order. That stays out of scope here because its design choices are a
separate conversation - warn vs prompt vs fail (backport tagging like
`v1.1.1` after `v2.0.0` is legitimate), and the comparison must be
semver-aware since `sort -V` orders `1.0.0-rc1` after `1.0.0`, which
is backwards for precedence. Tracked in
[#436](https://github.com/fini-net/template-repo/issues/436).

**Review round (PR #437).** Claude's review approved the grammar and
its security story and flagged one real gap, folded in here: accepting
`-rc1` tags while publishing them as *normal* releases would let a
pre-release wear the GitHub Latest crown - the same half-acceptance
complained about in #379, one layer up. Pre-release detection strips
the `+build` suffix first, then tests the remainder for a hyphen, so
`v1.0.0-rc1` publishes with `--prerelease`; build metadata alone
(`v1.0.0+build.5`) is not a pre-release per semver and publishes
normally. The if/else
avoids the bash 3.2 `set -u` empty-array expansion trap the test
harness documents. Fixture 17 now asserts the flag round-trips to
`gh release create`, while fixtures 12 and 18 pin that plain and
build-only versions do not get it. The reviewer also suggested a
tighter dot-separated-identifier suffix class; the looser class stays
a documented tradeoff - `v1.0.0--` is a semver-legal identifier, and
the recipe comment owns the choice. And the reviewer's
`release_age` question, checked: it reads `gh release list --limit 1`,
which lists pre-releases too, so it keeps reporting time since the
newest release activity, rc or not - defensible activity-based
semantics, left as is.

**Review round two (PR #437).** The second review caught a real bug in
the first cut of the pre-release flag: it tested the whole version for
a hyphen, and semver build identifiers may hyphenate, so
`v1.0.0+build-5` would have published with `--prerelease`. The test now
runs on the version with build metadata stripped
(`rel_core="${rel_version%%+*}"`), and two fixtures grew from the same
note: `20_recipe_release_combined_suffix_accept` pins that a combined
`-rc.1+build.5` tag keeps the flag, and
`21_recipe_release_buildmeta_hyphen_accept` pins that `+build-5` does
not get it. The reviewer also asked whether the fixture-19 injection
probe really arrives intact: a scratch `just` run confirmed `$1`
carries `v1.0.0";touch${IFS}pwn#` byte for byte (no execution, no
mangling), so the rejection is the regex, not argument loss on the way
in. And the two v10.8 entries the review spotted for `gh-process.just`
in CHECKSUMS.json are the manifest's normal shape - version labels
come from commit subjects, one entry per distinct checksum, and
twelve tracked files already carry same-version entries; the
hash/date refresh on unchanged files is the same
regenerating-from-git-history behavior.

### v10.7 - copilot_rollback dotglob reset + security-boundary test coverage (2026-11-02)

- Fixes issues [#378](https://github.com/fini-net/template-repo/issues/378)
  and [#382](https://github.com/fini-net/template-repo/issues/382)
- **Related PR:** [#434](https://github.com/fini-net/template-repo/pull/434)

**`copilot_rollback` now restores default globbing.** The recipe enables
`shopt -s dotglob` so the `*.bak` listing matches dot-prefixed backup
names (#332), but never reset it - harmless while each recipe runs in
its own bash process, but inconsistent with the set/reset cleanup idiom
the test harness uses, and a trap for any glob added later in the same
recipe body, which would silently start matching dotfiles too (#378).
A matching `shopt -u dotglob` now runs right after the listing loop.
The subshell-scoping alternative from the issue would have meant
restructuring the `backups`/`backup_targets` arrays the selection
prompt uses after the loop, so the one-line reset wins.

**The sync system's security boundary has direct assertions.** Two v9.9
sync reviews flagged that the boundary itself - `validate_filepath` /
`sanitize_for_display` in `common.sh`, and the `copilot_rollback`
backup-name parse - shipped with no unit-level tests for its rejection
classes (#382). `template_sync_test.sh` grew a
`security_boundary_selftest` pseudo-fixture (the v10.6
`harness_selftest` precedent applied to product code) which asserts
every documented `validate_filepath` rejection class against the real
sourced `common.sh`: non-`.just/` prefixes, absolute paths, whole
`..` segments, double quotes and backslashes, and control characters
including the embedded-newline NUL-delimited-key case - plus the
odd-but-legal `...` accept case, the deliberate single-quote accept
(call sites pass keys with jq `--arg`, which is quote-safe), and
`sanitize_for_display` control-byte stripping. `common.sh` also gained
the worked example the gh-amp review asked for, since the escaping
there is dense and easy to break on a future "simplifying" edit.

**`copilot_rollback` is now fixture-covered end to end.** A new `stdin`
fixture key pipes a fixture file to the recipe (default `/dev/null`),
so the recipe's interactive selection read gets deterministic input and
no recipe run can hang on a TTY. Three new recipe fixtures drive the
real recipe in a shimmed workspace (a `gum` shim confirms the restore
and declines the push): a happy-path restore of a dot-prefixed
URL-encoded backup - which doubles as the regression test for the
dotglob listing, since it fails if `*.bak` ever stops matching
dot-prefixed names - a parse-edge fixture pinning the greedy
timestamp-suffix split (a digit-heavy safe path, a safe path that
itself ends in a timestamp-like suffix, an unparseable loud-skip, and
a `../`-decoding skip), and a legacy `_`-for-`/` fixture pinning the
fallback decode branch. The fixtures feed names through the real regex
in the real recipe, so neither can lose a rejection class without a red
fixture. Fixture backup names share a `.just%2F` prefix and differ
first at an alphanumeric character, keeping the in-order matcher for
expected output stable across C and en_US.UTF-8 collation.

**`template-sync.yml` triggers.** The workflow now also fires on
`.just/copilot.just` and `.just/lib/common.sh` - neither path
triggered the sync workflow before, so a `common.sh` edit ran no sync
CI at all.

**Review round (PR #434).** Claude's two reviews were LGTM with
non-blocking suggestions; the actionable ones are folded in here.
Fixture files now end with a final newline per `.editorconfig`
(`insert_final_newline`) - the harness matcher tolerates its absence,
but the existing fixture key files all have it. The
`sanitize_for_display` self-test grew the explicit literal-tail
assertion: an escape's remaining `[31m` text survives, pinning that the
function strips raw control bytes only (the call sites' `printf '%s'`
is what keeps the tail inert). And fixture 15 carries a README
recording why its backup names all share a `.just%2F` prefix and
diverge first at an alphanumeric character: the in-order expected-
output matcher is locale-collation-sensitive, and C (CI) and
en_US.UTF-8 (macOS) disagree when punctuation would decide glob order.
The suggested shared default `gum` shim was declined: three identical
shims are cheaper than new harness machinery, and the duplication
should be extracted only when a fourth rollback fixture appears.

### v10.6 - template_sync_test: mismatch dump + DRY matcher/state helpers (2026-11-02)

- Fixes issues [#376](https://github.com/fini-net/template-repo/issues/376)
  and [#377](https://github.com/fini-net/template-repo/issues/377)
- **Related PR:** [#433](https://github.com/fini-net/template-repo/pull/433)

**A red fixture now answers "what did it actually print."** Both
runner modes in `template_sync_test.sh` reported an output mismatch
with a bare `Output mismatch` line and nothing else, leaving the
expected-vs-actual comparison entirely to the developer re-running
the fixture manually with added echoes. On a mismatch the suite now
dumps both sides - expected lines and the normalized actual output -
through the exact normalization the matcher uses (colors stripped,
blank lines dropped, `/tmp` paths scrubbed, so mktemp/pid noise never
appears), plus a first-difference hint: the first expected line with
no match at/after the search position, and the normalized line the
search had reached. The state report got the same treatment: `State
mismatch` now names the offending file and reason (`missing:` /
`differs:`), the state counterpart of the output dump. The suite is
the standing guard for the "tracked modules must be self-contained"
invariant (#368) - its failure report now carries the evidence the
fix loop starts with.

**The matcher and state-check blocks can no longer drift.** The v9.9
`write_mock_curl` extraction left the expected-output matcher and the
expected-state checksum loop duplicated verbatim between
`run_recipe_test` and `run_update_test`, and drift had already begun:
the state-check loop quoted the fixture-dir expansion in one copy and
left it unquoted in the other (shellcheck SC2295; harmless today only
because fixture dir names contain no glob metacharacters - exactly
the divergence class that motivated the extraction). Both blocks now
live in shared helpers - `match_expected_output <output> <test_dir>
<test_name>` and `verify_expected_state <workspace> <test_dir>` -
keeping the quoted form, and the output-mismatch dump is written
once for both modes (as #376 suggested, it rode along with the DRY
cleanup). The `write_mock_curl` contract comment now states the
narrowed manifest contract: the CHECKSUMS.json branch sits inside the
`-o` branch, so a manifest fetch without `-o` falls through to
failure (both real call sites use `-o`).

**Review round (PR #433).** The state walk now sorts before
checksumming (`find | LC_ALL=C sort`): `find`'s order is
filesystem-dependent, and the mismatch report names the first
offender, so which file gets reported must not vary between runs or
machines. The search-position hint was reworded to "searched for it
from line N onward" - the first wording could be misread as naming
the line that failed. And the matchers gained a `harness_selftest`
pseudo-fixture that runs before every fixture pass: the diagnostics
only print on failure and no fixture is supposed to fail, so the
dump and state-reason paths had no coverage - the self-test drives
the helpers against a deliberately wrong scratch fixture and asserts
the dump fires (and stays silent on a clean run), the v10.5
compliance suite's run-on-every-run self-test precedent applied here.

### v10.5 - compliance suite: enforced terminal-token extraction guard (2026-11-02)

- **Related PR:** [#432](https://github.com/fini-net/template-repo/pull/432)
  (follow-up to [#431](https://github.com/fini-net/template-repo/pull/431))

**The single-quote constraint is now enforced, not just documented.**
`compliance_test.sh`'s `extract_pattern` takes a fourth argument - the
extracted pattern's terminal token - and fails the suite when an
extraction does not end with it (a suffix match, so a token that also
appears earlier in the pattern cannot mask a truncation). Because the
marker regex stops at the first quote, a single quote landing inside a
recipe pattern would truncate the extraction there and silently
exercise a partial pattern; the terminal-token assertion makes the
next suite run fail loudly instead, and the suite self-tests that
guard on every run by extracting from a quote-injected throwaway copy
of the recipe and asserting the specific truncation diagnostic (a
stale injection fixture fails loudly rather than passing vacuously).
Extraction diagnostics moved
to stderr so they stay visible through command substitution. The
constraint comment in `compliance.just` no longer writes its examples
with literal single quotes, so the comment block cannot confuse a
future grep-based extraction of the patterns, and a v10.3
release-notes paragraph that had drifted past the file's wrap style
was re-wrapped.

### v10.4 - compliance review follow-ups: single-quote constraint, missing-tool reporting (2026-11-02)

- **Related PR:** [#431](https://github.com/fini-net/template-repo/pull/431)
  (follow-up to [#430](https://github.com/fini-net/template-repo/pull/430))

**Post-merge follow-ups from the Claude review of #430's final head.**
The classification comment block in `compliance_check` now warns that
`compliance_test.sh` extracts the live patterns by their single-quoted
text, so single quotes added to those patterns would silently truncate
the extraction - and documents the large-blob awk's blind spot for a
file literally named `total` (low-impact for an informational check).
The suite's missing-tool gate now reports every missing tool instead of
only the last one checked, so an environment missing both `file` and
`git` names both in one message. The release-notes description of
`MS Windows icon resource` was corrected to match the shipped #373
behavior: favicon-style files are excluded from the red executables
branch and counted as media.

### v10.3 - compliance: binary-artifact split, portable grep, SUPPORT.md (2026-11-02)

- Fixes issues
  [#373](https://github.com/fini-net/template-repo/issues/373),
  [#380](https://github.com/fini-net/template-repo/issues/380), and
  [#386](https://github.com/fini-net/template-repo/issues/386)
- **Related PR:** [#430](https://github.com/fini-net/template-repo/pull/430)

**`compliance_check` no longer treats images and PDFs as contraband
([#373](https://github.com/fini-net/template-repo/issues/373)).** The
OpenSSF-aligned Binary-Artifacts heuristic ran one `file` pass whose `grep`
lumped `JPEG|PNG|GIF|Web/P|PDF` in with `ELF|Mach-O|PE32|MS Windows`, so any
derived repo that legitimately ships media - Hugo sites with static images,
games with sprite/audio assets, docs trees with PDFs - printed red on every
run, and a permanently red check is noise that gets ignored. The scan now
classifies each file exactly once: executables stay red (that is what
Scorecard's Binary-Artifacts check is actually about), while media formats
become a yellow advisory with a count. `MS Windows icon resource`
(favicon.ico and friends) is excluded from the red executables branch
and counted as media, so static sites stay clean. Blobs over 1MB moved
out of the red branch into their own yellow advisory - size hygiene
is worth mentioning, but not worth drowning the executable
signal, and template-repo itself was permanently red on its
own 1.7MB banner. The green verdict keys on executables alone and stays
quiet about surgical cleanliness while a size advisory is on the screen.
The classification greps anchor to the `file` description after
`path:` rather than the whole line and require a word boundary
(`(^|[^a-zA-Z0-9_])`, the portable #380 form) before each keyword, so a
text file *named* `ELF-notes.md` or `PDF-spec.txt` is classified by its
content instead of its name, and a keyword embedded mid-word in a
description cannot match. Output plumbing uses `printf '%s\n'` rather
than `echo` so a filename starting with `-n` cannot be eaten as a flag.
Paths containing `:` (or newlines) still confuse the `cut -d: -f1`
extraction - a pre-existing, now-documented limitation acceptable for an
informational check.

**The OpenSSF heuristics no longer depend on GNU grep extensions
([#380](https://github.com/fini-net/template-repo/issues/380)).** `\b` word
boundaries and `-w` silently degrade under the BSD grep macOS ships -
boundaries treated literally, matches missed, with no hint to the user that
the output means less than it does on Linux. All three sites (the CI-Tests
`test_cmds` pattern, the `pull_request_target` secrets scan, and the `sudo`
scan) now use POSIX character-class boundaries (`(^|[^a-zA-Z0-9_])` on the
left, `([^a-zA-Z0-9_]|$)` on the right), verified on both BSD and GNU grep;
the comments that documented the deliberate GNU dependency now document the
portable form instead. No runtime GNU-grep detection notice was needed
because nothing GNU-specific remains.

**`compliance_check` now verifies `.github/SUPPORT.md`
([#386](https://github.com/fini-net/template-repo/issues/386)).** The README
links to it, and the link dangled until the file was added - exactly the
kind of rot a compliance check exists to catch. The check sits with the
other `.github/*` file checks and carries the `[gh]` label, but SUPPORT.md
is not part of GitHub's community-standards checklist: it is an
extra-health check like the custom social preview one.

**New tests pin the two behaviors that regress invisibly.**
`.just/lib/compliance_test.sh` (run via `just compliance_test`) does not
hardcode copies of the patterns - it extracts the live boundary and
classification pattern strings from `compliance.just` and exercises
those (the extraction matches the patterns' single-quoted text, so they
must stay single-quote-free - noted in the recipe comments), so someone
"simplifying" a boundary back to GNU `\b` (silently
literal under the BSD grep macOS ships) or editing a classification
pattern fails the suite instead of shipping subtly wrong informational
output. The boundary section asserts exact match sets (`jest`, `tox`,
`vitest`, and `just pr_body_test` in, `majestic` and `adjust testing`
out; `secrets.BAR` in, `mysecrets.foo` out; `sudo` and `- sudo` in,
`sudoers` and `pseudorandom` out). The classification section plants a
scratch git repo with a fake ELF, a JPEG, a GIF, a favicon.ico, a 1.7MB
blob, and text files *named* `ELF-notes.md`/`PDF-spec.txt` that must
classify as neither executable nor media. The pattern extraction is
content-anchored, not positional: every marker carries a literal filter
(`'secrets\.'` and `'sudo'` for the CI-Tests and sudo boundaries,
`'Mach-O'` for executables, `'icon resource'` for the exclusion,
`'JPEG'` for media) so an unrelated grep added earlier in
`compliance.just` cannot silently re-target the suite, and the
executables assertion is an exact match (`evil.elf` and nothing else)
so a leaked favicon cannot hide inside a substring check. The suite runs in
`cue-sync-tests.yml`, whose path triggers now include
`compliance.just` and the new lib script, and ships with matching
`CLEANED_FILES` and `clean_template` removal entries so derived repos do
not keep it. In CI a missing `file`/`git` fails the suite rather than
letting it pass vacuously; locally that section skips with a note.

### v10.2 - repo-toml stub sandboxing, repo_toml_check stub sentinel (2026-11-01)

- Fixes issue [#372](https://github.com/fini-net/template-repo/issues/372)
- **Related PR:** [#428](https://github.com/fini-net/template-repo/pull/428)

**`just shellcheck` no longer writes its fallback stub to the real
`.just/repo-toml.sh` path.** When the generated file was missing and
`repo_toml_generate` failed (no `cue`/`jq` on PATH - the
[#192](https://github.com/fini-net/template-repo/issues/192) auto-generate
fallback), the recipe wrote a hardcoded default-flag stub to the real path so
shellcheck would have something to follow. That had two consequences: the stub
was freshly written, so `repo_toml_check`'s `-nt` staleness test read it as
up-to-date even though its `FLAG_*` values might not match `.repo.toml`, and
every recipe that sources the file (`pr`, `again`, `pr_checks`, `claude_review`,
`release`, `release_age`) silently inherited those defaults until someone
noticed and regenerated. The stub now lives in the lint run's temp directory
(`$CHECKS_TMPDIR/.just/repo-toml.sh`) and shellcheck resolves it through
`-P`/`--source-path` for that run only, so the real path is never touched and a
failed lint run can no longer leave poison behind. When the real file exists the
stub branch never runs at all; the suite pins that shellcheck's cwd-first source
resolution makes the real file win over the sandboxed candidates, so the normal
path lints exactly as before.

**`repo_toml_check` now refuses stub-marked files.** Checkouts that
already carry a v10.1-era stub at the real path are healed by a new
sentinel check: the file's first line is compared against the stub
marker (`# Stub written by ...`) before the `-nt` test, so a fresh stub
is rejected with a "regenerate" hint instead of passing as up-to-date.
The comparison is first-line only: every stub the old recipe wrote led
with the marker, so a marker buried mid-file is treated as a hand edit,
not a stub. If `cue`/`jq` are unavailable, deleting the stub is enough:
the sourcing recipes' existing fallback branches supply their built-in
defaults. No `gh-process.just` recipes changed: a legacy stub
only exists on machines without `jq`, which cannot complete the `pr`
flow anyway.

**New tests cover both ends of
[#372](https://github.com/fini-net/template-repo/issues/372).**
`.just/lib/repo_toml_stub_test.sh` (run via `just repo_toml_stub_test`) drives
the real `shellcheck` and `repo_toml_check` recipes in temp workspaces: the lint
passes with no SC1091/SC2154 noise while the real `.just/repo-toml.sh` path
stays untouched, a fresh stub is rejected, a generated-looking file passes, and
staleness detection still fires. A drift assertion fails the suite if the stub's
variable list diverges from `repo_toml_generate`'s emit block, and a precedence
pin drives the real shellcheck binary in the recipe's layout to prove the real
file wins over the sandboxed stub. The suite runs in `cue-sync-tests.yml` -
whose path triggers now include the modules under test, so a PR that regresses
only them cannot skip the suite that guards them - and ships with matching
`CLEANED_FILES` and `clean_template` removal entries so derived repos do not
keep it. In CI (`$CI` set) a missing `just`/`shellcheck` fails the suite instead
of skipping it: this is the only regression coverage for
[#372](https://github.com/fini-net/template-repo/issues/372), and a vacuous
green run would be worse than a red one; locally the skip-with-note behavior is
unchanged.

### v10.1 - asciinema .cache gitignore guard, sensitive-recording caveat, single-guard pr (2026-11-01)

- Fixes issues [#374](https://github.com/fini-net/template-repo/issues/374)
  and [#375](https://github.com/fini-net/template-repo/issues/375)
- **Related PR:** [#427](https://github.com/fini-net/template-repo/pull/427)

**The asciinema recording feature now guarantees `.cache/` is gitignored
before any recording starts.** The root `.gitignore` is not
CHECKSUMS-tracked and does not ship via `just update_from_template`, so
a derived repo that flipped the opt-in `flags.asciinema-record` feature
(v9.9) on had nothing stopping a `git add -A` from sweeping a `.cast`
file into a commit. A new hidden guard recipe, `_ensure_cache_ignored`,
now runs before both `pr` and `again` start recording: it creates
`.cache/` when missing, probes with `git check-ignore` - using a path
*under* `.cache/` (`.cache/x.cast`), because directory-only patterns
like `.cache/` do not match a path that does not exist yet - and
appends a root-anchored `/.cache` entry to `.gitignore` when nothing
covers it yet, creating the file when absent, repairing a missing
trailing newline so the entry cannot glue itself onto the last line,
and leaving already-ignored repos untouched. Outside a git repo it
warns and continues rather than failing.

**Recordings are now labeled as what they are: sensitive local
artifacts.** A cast can capture `gh` output, tokens echoed by a
misbehaving tool, or accidentally displayed files, so both recording
paths and `cue-verify`'s `asciinema-record` block print a
review-before-sharing caveat, and `cue-verify` also warns when
`/.cache` is not gitignored yet. The caveat lives in CHECKSUMS-tracked
recipes, so derived repos pick it up through the normal
`just update_from_template` flow.

**`pr` no longer runs the `_has_commits` guard twice.** Since v9.9 the
`pr` wrapper declared `_has_commits` as a dependency while
unconditionally delegating to `_pr_inner`, which declares the same
dependency - so the `git cherry` check ran twice per invocation. The
dependency is gone from `pr`: the guard still fires exactly once, inside
`_pr_inner`, the recipe body it protects. The `again`/`_again_inner`
pair was checked for the same duplication and is clean.

**New tests cover the guard end to end.** `.just/lib/asciinema_cache_test.sh`
(run via `just asciinema_cache_test`) drives the real
`_ensure_cache_ignored` recipe and `cue-verify`'s warning behavior in
temp workspaces, runs in the `cue-sync-tests.yml` workflow alongside
the cue-sync and repo_urls tests, and ships with matching
`CLEANED_FILES` and `clean_template` removal entries. The removal list
also caught a v10.0 straggler: `repo_urls_test.sh` landed in
`CLEANED_FILES` without a matching removal block in
`_remove_template_files`, orphaning it in derived repos; it is removed
alongside the new test script.

## October 2026

### v10.0 - clean_template repoints .repo.toml URLs; cue sync refuses stale URLs (2026-10-31)

- Fixes issue [#420](https://github.com/fini-net/template-repo/issues/420)
- **Related PR:** [#426](https://github.com/fini-net/template-repo/pull/426)

**Derived repos used to ship with `.repo.toml` still describing template-repo.**
`clean_template` regenerated README.md from the derived repo's real org/repo
(pulled from `git remote` in `_clean_readme`) but never touched `.repo.toml`,
and nothing else in the fork flow fixed the `[urls]` section either.
`cue-sync-from-github` decides which GitHub repo to query from
`urls.web_url`, so in a derived repo it fetched the *template's* description
and topics, wrote them into the derived repo's `.repo.toml`, and the trailing
`just cue-verify` passed - both sides of the comparison pointed at
template-repo. The git-remote fallback only fired when the extracted names
were empty, not valid-but-stale, so the failure was completely silent: one
derived repo went three PRs believing its `.repo.toml` described itself while
every sync re-imported the template's metadata, triple-space typo and all.

**clean_template now repoints `[urls]` and syncs real metadata in the same
pass.** A new `_clean_repo_toml` recipe (running between `_clean_readme` and
`_remove_template_files`) extracts org/repo from the origin remote, rewrites
`git_ssh`/`web_url` in `.repo.toml`, validates with `cue vet`, then runs
`just cue-sync-from-github` so description and topics come from the derived
repo's own GitHub metadata. The rewrite is scoped to the `[urls]` section,
replaces commented lines there, inserts whichever key is missing (so
`git_ssh` and `web_url` can never drift apart), leaves doc-comment `web_url`
lines in other sections untouched, and the recipe verifies that *both* keys
landed. Two fresh-fork realities are handled: a repo with zero GitHub topics
gets a `placeholder` topic added via the GitHub topics API (the CUE schema
requires at least one topic, so the first sync would otherwise fail
validation and roll back - replace it with real topics and re-sync), and a
sync failure - typically a brand-new repo with no GitHub description yet -
warns with instructions instead of failing the cleanup. All of
`clean_template`'s recipes now run at the repo root (no `[no-cd]`), so the
relative paths they touch are correct no matter where the recipe is invoked
from.

**The sync recipe and cue-verify now cross-check `urls.web_url` against the
git origin remote.** A new shared library, `.just/lib/repo_urls.sh`,
centralizes the URL parsing both recipes use: `normalize_remote_url`
(SSH, HTTPS, and `ssh://` remotes, with or without a `.git` suffix; scp-style
remotes on other hosts are tolerated, other schemed URLs are rejected rather
than guessed at), `parse_web_url` (strict `github.com` org/repo - replacing
a sed extraction that returned misleading partial values for non-matching
URLs), `classify_url_mismatch` (`match` / `org-mismatch` / `name-mismatch`),
and a `repointed_repo_toml` transform. `cue-sync-from-github` refuses to
sync on *any* mismatch before writing anything; `cue-verify` stage 3 reports
a repo-name mismatch as a fatal error (the stale template-URL shape), warns
on an org-only mismatch (the normal contributor-fork clone, where
verification legitimately runs against the repo named in web_url), and
notes when the origin remote is unavailable so the cross-check cannot run.
Existing derived repos pick the guards up via `just update_from_template`,
so a stale `.repo.toml` gets caught on day one instead of after manual
archaeology.

**`_clean_readme` also learned HTTPS.** Its inline sed extraction produced an
empty org for `https://github.com/org/repo` origin remotes, silently breaking
the README badges. It now uses the shared helper, which handles SSH and
HTTPS alike.

**New tests cover the machinery end to end.** `.just/lib/repo_urls_test.sh`
(run via `just repo_urls_test`) unit-tests the URL parsing, the mismatch
classifier, and the `[urls]` repoint transform over fixtures - including
doc comments that must survive untouched and half-missing key pairs. Its
recipe-mode cases drive the real recipes in temp workspaces with git/gh
shims on PATH: the stale-URL refusal (proving the recipe actually refuses,
leaves the file untouched, and never calls gh), the matching-URL sync, the
cue-verify error/warn split, and both `_clean_repo_toml` outcomes - the
placeholder-topic bootstrap and the tolerated sync failure. The
`cue-sync-tests.yml` workflow runs all of it in CI (and now triggers on the
clean-template, gh-process, and testing modules those tests exercise).

**The template's own description lost its triple space.** The
`Copilot/Claude),   and` typo - the smoking gun that let a derived repo
notice its metadata was coming from template-repo - is fixed on both the
`.repo.toml` side and the GitHub side.

**The CONTRIBUTING recipe listing caught up with reality**, which had
drifted as far back as `PR create v5.4`.

## September 2026

### v9.9 - self-contained positional-argument recipes + bare-justfile test pass (2026-09-14)

- Fixes issues [#367](https://github.com/fini-net/template-repo/issues/367)
  and [#368](https://github.com/fini-net/template-repo/issues/368)
- **Related PR:** [#369](https://github.com/fini-net/template-repo/pull/369)

**The four argument-taking recipes no longer depend on root-justfile
configuration.** v9.7 moved `claude`, `branch`, `release`, and
`checksums_diff` to positional shell parameters (`"$@"` / `"$1"`), but
positional parameters only populate when `set positional-arguments :=
true` is present somewhere in the justfile/import tree - and the root
justfile, which holds the setting, is not CHECKSUMS-tracked, so
`just update_from_template` shipped the v9.7 modules to derived repos
without the setting they require. Every derived repo that pulled v9.7
broke: `just claude <anything>` silently launched claude with no
arguments, `just branch my-feature` created `user/2026-09-14-` with the
name silently dropped, and `just release v1.0` / `just checksums_diff
<path>` failed immediately with `$1: unbound variable`. A second `set`
inside a shipped module is a hard redefinition error, so the fix is the
per-recipe `[positional-arguments]` attribute (just >= 1.29.0), which
now sits on all four recipes. The attribute lives inside
CHECKSUMS-tracked modules, so it ships to derived repos, and it is
inert next to template-repo's own root `set`. Verified against the
injection payload end to end: under a bare justfile,
`just claude 'x"$(echo PWNED)"y'` still passes the argument through as
a literal string.

**The recipe-mode harness no longer tests against a configuration real consumers
never have.** `run_recipe_test()` baked `set positional-arguments := true` into
every sandbox justfile, which is exactly why the v9.7 breakage sailed through CI
green ([#368](https://github.com/fini-net/template-repo/issues/368)). The
harness now supports `modules`, `bare_justfile` (omit the `set` line, mirroring
a derived-repo justfile), and `shims/` fixture options, and four new bare
fixtures pin the invariant that tracked modules must be self-contained:
`checksums_diff`, `claude`, `release`, and `branch` each driven through shims in
a bare workspace, all four confirmed red against the pre-fix recipes. The
fixtures assert environment-independent verdicts (e.g. a boolean OK/MISSING line
from the git shim) rather than `$USER`/date-dependent output, so they stay
deterministic on any runner. Along the way the bare fixtures surfaced a latent
harness bug: the expected-output matcher aborted the whole suite under `set -euo
pipefail` the first time an expected line was missing, so no failing fixture
could ever be reported; both matcher copies now guard the substitution with `||
true`.

### v9.8 - claude_review is the single print site for the Copilot summary line (2026-09-13)

- **Related PR:** [#363](https://github.com/fini-net/template-repo/pull/363)

`pr_checks` (`.just/gh-process.just`) always chains into `claude_review`
(`pr_checks: _on_a_pull_request && claude_review`). Both recipes read the
same `COPILOT_COUNT_FILE` written by `pr_checks`'s GraphQL query, and both
echoed the `🐈‍⬛ No unresolved Copilot suggestions - looks good!` /
`🐈‍⬛ Unresolved Copilot suggestions: N` summary line from that count -
`pr_checks` as immediate feedback right after the query, `claude_review`
again as its end-of-run summary (a deliberate v8.4 change that moved the
summary above `claude_review`'s early-exit gates so it always prints).
Together they printed the identical line twice on every `just pr` /
`just again` run with `copilot-review` enabled, on both the `gh observer`
and `gh pr checks --watch` watcher paths.

`pr_checks` no longer echoes the summary line. It still writes the count
to `COPILOT_COUNT_FILE` for `claude_review` to read, and still prints the
detailed `COPILOT_JSON` dump immediately when there are unresolved
suggestions, but the "looks good!" / count summary now prints exactly
once, from `claude_review`.

### v9.7 - injection hardening: positional args for branch/release/claude (2026-09-12)

- Fixes issues [#353](https://github.com/fini-net/template-repo/issues/353)
  and [#359](https://github.com/fini-net/template-repo/issues/359)
- **Related PR:** [#362](https://github.com/fini-net/template-repo/pull/362)

**The last `{{...}}` argument templating is gone from user-facing recipes.** PR
[#352](https://github.com/fini-net/template-repo/pull/352) (v9.1) proved
empirically that interpolating a recipe argument into the body via `{{arg}}` is
command-injectable at the templating layer - a branch name like `x"$(echo
PWNED)"y` executes the substitution before bash parses the script.
[#353](https://github.com/fini-net/template-repo/issues/353) was the audit
follow-up listing the three remaining sites with that same code shape, and all
three now take the positional form: `branch` runs `git checkout -b
"$USER/$NOW-$1"`, `release` reads `rel_version="$1"` up front and interpolates
`"$rel_version"` throughout, and the variadic `claude *args` in `claude.just`
becomes a shebang recipe running `claude "$@"`. Testing confirmed variadics
arrive as real positional shell parameters (the payload stayed a literal string
end to end), so `"$@"` is safe.

**The release regex is now actually load-bearing
([#359](https://github.com/fini-net/template-repo/issues/359)).** The old
`^v[0-9]` start-anchored-only check let `v1"; touch /tmp/pwned #` pass
validation and then break out of the quoting in `gh release create`. The guard
is now tightened to `^v[0-9]+(\.[0-9]+){0,2}$`: strict input validation with a
clean error message (`v1`, `v1.0`, `v1.0.0` pass; anything with stray characters
fails). The strict form deliberately rejects prerelease suffixes (`v0.1-beta`);
the repo's own tags have only ever been plain `vX.Y` forms, and the looser
variant remains a one-line change if a prerelease workflow ever needs it.

### v9.6 - release-process hygiene: editorconfig pre-push guard (2026-09-12)

- Fixes issue [#329](https://github.com/fini-net/template-repo/issues/329)
- **Related PR:** [#361](https://github.com/fini-net/template-repo/pull/361)

**The 3-space indent regression finally has a local gate.** Numbered-list
continuation lines in this very file kept landing with a 3-space indent (the
visual alignment under the `1.` list marker) instead of a multiple of 2, which
is what `.editorconfig` demands for `*.md` - and editorconfig CI failed for it
three times across two consecutive versions:
[#289](https://github.com/fini-net/template-repo/pull/289) (v8.3) flagged it,
the fix landed, then a follow-up push to the same PR re-broke items 4-5, and
[#317](https://github.com/fini-net/template-repo/pull/317) (v8.5) hit it again.
Every failure was caught in CI *after* the push, which is exactly where you want
it not to be. The new `editorconfig_check` recipe in `compliance.just` runs
`editorconfig-checker` over all git-tracked files and now sits in `_pr-hook`, so
`just pr` fails locally before the push instead of letting CI deliver the news.
Since the binary is not yet in the required-tools list, the gate is deliberately
best-effort: a missing `.editorconfig` or a missing `editorconfig-checker`
binary warns and exits 0 (the asciinema/shellcheck-stub precedent), and CI
(`.github/workflows/editorconfig.yml`) remains the hard enforcement
([#329](https://github.com/fini-net/template-repo/issues/329)).

**The `again` path is guarded too.** The second
[#289](https://github.com/fini-net/template-repo/pull/289) regression arrived
through `just again` - a follow-up push to an open PR - which never ran the
pre-PR hook. `_again_inner` now invokes `_pr-hook` (when present) before its
`git push`, same as `_pr_inner` does, so both push paths through the PR
lifecycle get the same pre-flight checks
([#329](https://github.com/fini-net/template-repo/issues/329)).

**Tooling support and docs.** `install-prerequisites.sh` now knows about
`editorconfig-checker`: it detects it, installs it via Homebrew on macOS, points
pacman users at the official Arch package, and points everyone else at the
installation docs (there is no apt/dnf package - the release binary, npm, and
pip are the supported routes). CLAUDE.md's "Versioning `.just/*` changes"
section gains an explicit RELEASE_NOTES.md indentation rule aimed at the actual
culprit - AI agents appending list items mid-PR - and `.just/README.md` no
longer calls `_pr-hook` a placeholder that "just prints a message", because it
now runs three real checks
([#329](https://github.com/fini-net/template-repo/issues/329)).

### v9.5 - test infrastructure: wait_for_copilot suite + recipe-gate coverage (2026-09-11)

- Fixes issues [#330](https://github.com/fini-net/template-repo/issues/330)
  and [#354](https://github.com/fini-net/template-repo/issues/354)
- **Related PR:** [#360](https://github.com/fini-net/template-repo/pull/360)

**The Copilot-wait state machine finally has tests.** The shared
`.just/lib/wait_for_copilot.sh` poll loop sits on the critical path of every
`just pr` / `just again` / `just copilot_refresh` run and needed two rounds of
GraphQL/state-machine bug fixes in v8.4 alone - yet unlike its siblings it had
no automated test. The new `.just/lib/wait_for_copilot_test.sh` runs the
production script byte-for-byte unmodified, intercepting `gh` and `sleep` with a
PATH shim directory (the same mocking precedent `template_sync_test.sh` set for
curl). The mock `gh` plays fixture responses in order and applies the real
`--jq` filter with real jq, so the exact response shaping the script relies on
is exercised; the no-op `sleep` keeps tests instant. Ten fixtures cover the full
branch matrix - completion, in-progress, the null-response/not-found fast-fail,
the stale-review fast-fail, timeout with and without a stale review, and the
`USING_GUM` dot suppression - and sentinel files are asserted written on stale
exits and cleared on clean ones (the
[#300](https://github.com/fini-net/template-repo/pull/300) review regression).
An `exact_output.txt` fixture mode takes precedence over the in-order line check
and requires byte-for-byte output, so extra progress dots fail the suite instead
of passing a substring check. Wired into `.just/testing.just` as `just
wait_for_copilot_test` and CI via `.github/workflows/wait-for-copilot-tests.yml`
([#330](https://github.com/fini-net/template-repo/issues/330)).

**Recipe gates are now tested, not just the update script.** The
validate_filepath path-traversal gate added in
[#352](https://github.com/fini-net/template-repo/pull/352) lives in three
places - `template_update.sh`'s `process_file()` and the `checksums_verify` /
`checksums_diff` recipe bodies - but the fixture harness only drove a patched
copy of the update script. `template_sync_test.sh` grew a recipe mode: fixtures
with a `recipe` file get a sandboxed workspace holding a copy of the real
`.just/template-sync.just` plus a minimal justfile, and the harness runs the
actual `just checksums_verify` / `checksums_diff` commands with mocked curl,
asserting exit codes, ordered output lines, and expected state. Five new
fixtures cover the invalid-manifest-key rejection, the
cleaned/not-present/modified file states, the all-latest success path, the
traversal-argument rejection in `checksums_diff`, and a happy-path diff against
a mocked template version. The shared mock curl now writes `-o` output files
properly and no-ops when source and destination are the same file, so the legacy
fixtures keep passing unchanged
([#354](https://github.com/fini-net/template-repo/issues/354)).

**Both runners ship clean.** Following the v7.2 lesson
(`cue_sync_test.sh` initially shipped into derived repos as a dead
runner), the new test runner and workflow are added to the
`clean_template` removal lists and `CLEANED_FILES` in the same commit
they appear in, so `just update_from_template` never resurrects them
in a derived repo.

### v9.4 - misleading comment fixes (2026-09-11)

- Fixes issues [#339](https://github.com/fini-net/template-repo/issues/339)
  and [#337](https://github.com/fini-net/template-repo/issues/337)
- **Related PR:** [#357](https://github.com/fini-net/template-repo/pull/357)

**No more "calling shell" confusion.** The comment above `unset
'footer_content[...]'` in `update_pr_body.sh` was added by
[#203](https://github.com/fini-net/template-repo/issues/203) to stop recurring
false-positive reviews of the single-quoted `unset` idiom. It failed: Copilot's
review of [gh-amp#18](https://github.com/fini-net/gh-amp/pull/18) flagged the
*comment* itself, noting "there is no separate 'calling shell'" — the framing
invited exactly the wrong mental model. The comment now says what the code does
in one accurate sentence: single-quoting lets `unset` itself evaluate the
subscript arithmetic, so nothing is expanded by this line. Copilot custom
instructions now cover the idiom too: `review-guidance.instructions.md` in
`.github/instructions/` uses the `*.instructions.md` filename and `applyTo`
frontmatter key that Copilot code review requires (a plain `.md` name with
`apply-to` would be silently ignored). Note that template sync ships only the
`.just/` tree, so derived repos wanting this review guidance must copy
`.github/instructions/` themselves
([#339](https://github.com/fini-net/template-repo/issues/339)).

**No more phantom test runners.** `cue_sync.awk` and `cue-verify.just` comments
referenced `.just/lib/cue_sync_test.sh` unconditionally — but `clean_template`
strips that file from every derived repo, so downstream repos carried comments
pointing at a missing file (flagged twice in
[fini-clock#18](https://github.com/fini-net/fini-clock/pull/18)). Both comments
now describe the actual derived-repo caller (`cue-sync-from-github`)
([#337](https://github.com/fini-net/template-repo/issues/337)).

### v9.3 - install-prerequisites.sh cleanup (2026-09-10)

- Fixes issues [#335](https://github.com/fini-net/template-repo/issues/335)
  and [#333](https://github.com/fini-net/template-repo/issues/333)
- **Related PR:** [#356](https://github.com/fini-net/template-repo/pull/356)

**npm fallback for markdownlint-cli2 on macOS.** The macOS branch
already exits early when Homebrew is missing, which made the nested
`command -v brew` guard inside the `markdownlint-cli2` case dead code
— and when `brew install markdownlint-cli2` failed, the script gave
up with no fallback even when npm was available. The unreachable arm
is gone; a failed brew install now falls back to
`npm install -g markdownlint-cli2` so the tool still gets installed
([#335](https://github.com/fini-net/template-repo/issues/335)).

**Cross-platform unsupported-OS hint.** The "Unsupported OS" fallback — reached
precisely when the OS is neither macOS nor Linux — told users to `brew install
markdownlint-cli2`, a macOS-first path that sends other platforms down a dead
end. The hint now lists the cross-platform npm install first, with brew as a
macOS/Linux alternative, matching the Linux branch's existing npm guidance
([#333](https://github.com/fini-net/template-repo/issues/333)).

### v9.2 - check recipes fail gracefully and report accurately (2026-09-10)

- Fixes issues [#340](https://github.com/fini-net/template-repo/issues/340),
  [#328](https://github.com/fini-net/template-repo/issues/328), and
  [#334](https://github.com/fini-net/template-repo/issues/334)
- **Related PR:** [#355](https://github.com/fini-net/template-repo/pull/355)

**Graceful failure.** The lint/compliance recipes no longer die or lie
when optional tooling misbehaves:

- The repo description check in `compliance_check` no longer runs `$(gh repo
  view ...)` inside `[[ ... ]]`. A failed `gh repo view` (missing gh, expired
  auth, API error) could either abort the whole recipe under `set -euo pipefail`
  or yield an empty substitution that inverted the length test, reporting a
  healthy description as a compliance problem. The substitution now sits in an
  `if` assignment (matching the existing `REPO_META` pattern in the same file);
  on failure the check prints a yellow "skipped" note — no false verdict — and
  the recipe continues
  ([#340](https://github.com/fini-net/template-repo/issues/340)).
- `just shellcheck` no longer hard-fails when
  `.just/repo-toml.sh` generation fails (no `cue`, no `jq`, API
  hiccup). Since shellcheck itself could still run, a linting command
  shouldn't be a dependency on optional tools. On failure it now
  writes a stub with the expected variable declarations and continues
  with a warning. The declarations matter: an empty stub silences
  SC1091 for shellcheck but would leave `FLAG_*`/`REPO_*` unset and
  crash recipes that source the file under `set -u`. Verified the
  stub silences SC1091 for all 35 extracted scripts without needing
  `--source-path`, since shellcheck resolves the repo-relative
  `source .just/repo-toml.sh` from the repo root the recipe runs in
  ([#334](https://github.com/fini-net/template-repo/issues/334)).

**Accurate reporting.** The OpenSSF Token-Permissions heuristic no
longer reports a vacuous GREEN:

- `compliance_check` grepped workflows for `'^[[:space:]]*permissions:'`, which
  also matches job-level indented `permissions:` blocks — a workflow with no
  top-level block at all was silently reported as least-privilege compliant. The
  pattern is now anchored to `'^permissions:'`, and the CI-Tests heuristic gets
  a `\b` before its `just [a-z0-9_-]*test` alternative so prose like "adjust
  testing" can't match mid-word. The remaining word-boundary items from the
  original audit (`\bsecrets\.` for Dangerous-Workflow,
  `\b(tox|jest|rspec|vitest)\b` for CI-Tests, `-w sudo`) had already landed in
  v8.5/v8.8 rounds
  ([#328](https://github.com/fini-net/template-repo/issues/328)). A
  fixture-driven regression test for these checks is planned with the
  [#330](https://github.com/fini-net/template-repo/issues/330)
  test-infrastructure work.

### v9.1 - template-sync security and correctness (2026-09-10)

- Fixes issues [#347](https://github.com/fini-net/template-repo/issues/347),
  [#348](https://github.com/fini-net/template-repo/issues/348),
  [#346](https://github.com/fini-net/template-repo/issues/346),
  [#336](https://github.com/fini-net/template-repo/issues/336), and
  [#338](https://github.com/fini-net/template-repo/issues/338)
- **Related PR:** [#352](https://github.com/fini-net/template-repo/pull/352)

**Security.** Two defenses land in the template sync system:

- `checksums_verify` and `checksums_diff` no longer build predictable
  `/tmp/<name>-$$.<ext>` paths; both use `mktemp` like their sibling
  `template_update.sh` always has. This closes the classic symlink
  race on multi-user hosts where an attacker pre-creates the
  enumerable PID-based filename. Existing `trap cleanup EXIT`
  handlers are unchanged ([#348](https://github.com/fini-net/template-repo/issues/348)).
- `update_from_template` now validates every `filepath` key from the
  remote manifest before any filesystem operation. A new
  `validate_filepath()` in `.just/lib/common.sh` requires paths to
  start with `.just/` and rejects `..` segments, backslashes, embedded
  quotes, and control characters; a manifest entry like
  `../../../.bashrc` is skipped with a red warning and counted under
  `Failed`, so the sync exits 1 — defense in depth against a
  compromised or misconfigured template repo, since manifest
  checksums come from the same remote as the paths they verify.
  Filepath keys are passed to jq via `--arg` instead of string
  interpolation (closing a jq expression breakout for keys containing
  `"`), manifest-key iteration is NUL-delimited so an embedded
  newline stays intact for the guards to reject, and rejection
  diagnostics print the untrusted value through a
  `sanitize_for_display` helper that strips raw control bytes - an
  adversarial manifest can't spoof output lines or inject terminal
  escape sequences into the message reporting its rejection
  ([#347](https://github.com/fini-net/template-repo/issues/347)).

**Correctness.**

- `template_sync_test` no longer hard-fails in derived repos: its harness
  (`.just/lib/template_sync_test.sh`, `.just/testing.just`, fixtures) is
  stripped by `clean_template`, so the recipe previously died with "No such file
  or directory" everywhere except template-repo. It now exits early with a
  friendly yellow message unless `.repo.toml` points at
  `fini-net/template-repo`, mirroring the `checksums_generate` guard
  ([#346](https://github.com/fini-net/template-repo/issues/346)).
- The cleaned-file jq predicate in both `checksums_verify` and `process_file()`
  carries explicit parentheses so the `|`/`or` precedence doesn't have to be
  re-derived by every reviewer, and the status messages now mention the tracked
  `.just/lib/*.awk` files that `generate_checksums.sh` includes
  ([#336](https://github.com/fini-net/template-repo/issues/336)).
- Checksum mismatch errors from `download_file()` print expected vs actual
  values, making CI failures actionable without manual re-runs. Rollback (backup
  restore) behavior is unchanged
  ([#338](https://github.com/fini-net/template-repo/issues/338)).
- `checksums_verify` routes every manifest key through the same
  `validate_filepath()` gate (and `checksums_diff` its user-supplied
  filepath), sourcing `.just/lib/common.sh` instead of carrying a
  duplicate inline `compute_checksum()`.

**Testing.** A new `04_path_traversal` fixture feeds a manifest with
traversal (`../evil.txt`), embedded-quote (`.just/bad"quote.sh`),
and non-prefix (`outside/no-prefix.sh`) entries alongside one safe
entry, and asserts every bad path is skipped while the safe file
updates normally. Wiring it up surfaced two dormant harness bugs in
`.just/lib/template_sync_test.sh`, now fixed:

- `run_test` resolved fixture paths relative to the repo root, but
  `cd`'d into a temp workspace before checking
  `expected_output.txt` / `expected_state`, so neither check ever
  ran — every fixture "passed" as long as the update script didn't
  crash. Fixture paths are now absolutized up front, so the checks
  execute.
- The multi-line `grep -qF "$expected"` comparison OR-splits lines,
  letting any single matching line pass the whole block; it now
  requires every expected line to appear in order. Color-code
  stripping also moved from `sed '\x1b'` (unsupported on BSD/macOS
  sed) to `awk` so normalized output is actually colorless.

### v9.0 - asciinema recording of pr/again behind asciinema-record flag (2026-09-05)

- Fixes issue [#324](https://github.com/fini-net/template-repo/issues/324)
- **Related PR:** [#345](https://github.com/fini-net/template-repo/pull/345)

`just pr` and `just again` can now capture a replayable terminal
recording of the whole flow via `asciinema rec`. Recordings are useful
for debugging flaky recipes, reproducing past runs, and as lightweight
"verify" artifacts. The feature is **opt-in**: a new
`asciinema-record` flag in `.repo.toml` (default `false`) follows the
existing flag pattern (`claude-review`, `copilot-review`,
`standard-release`). With the flag off — the default — behavior is
unchanged and no `.cast` files are ever written.

**Recipe restructure.** The bodies of `pr` and `again` moved into
hidden inner recipes (`_pr_inner`, `_again_inner`) and the public
recipes became thin wrappers that dispatch based on the flag:

- flag false (or `repo-toml.sh` missing) → `just _pr_inner` +
  `just pr_checks`, byte-for-byte the same command sequence as before
- flag true + `asciinema` on PATH → wrap the flow in
  `asciinema rec ... -c "just _pr_inner && just pr_checks"`
- flag true + binary missing → yellow warning, run unrecorded

One structural change was unavoidable: `pr` previously ran
`pr_checks` as a just post-dependency (`pr: _has_commits &&
pr_checks`), which executes *after* the recipe body — outside any
recording the body could start. To capture check watching inside the
recording, `pr` now chains `pr_checks` in its body (`just _pr_inner
&& just pr_checks`) and the dependency line is just
`pr: _has_commits`. The flag-off path is equivalent: same guard run
up front (`_has_commits` stays a pre-dependency), same command order,
same short-circuit — `_pr_inner` failure still prevents
`pr_checks` from running, and the wrapper propagates the failure exit
code.

**Naming.** Casts land in `.cache/` (already gitignored via `/.cache`)
so they never dirty `git status`:

- `pr` records to a pid-named temp file first
  (`.cache/pr-<pid>.cast.tmp`) and renames to
  `.cache/pr-<PRNUM>-<pid>.cast` once `gh pr create` returns a PR
  number; if creation fails or is interrupted, the cast survives as
  `.cache/pr-<pid>.cast` so failed-run debugging still works
- `again` knows the PR number up front (via `gh pr view`) and records
directly to `.cache/again-<PRNUM>-<pid>.cast` (pid-only fallback
when no PR is found, e.g. run from a non-PR branch)

**Exit status fidelity.** asciinema 2.x and 3.x disagree on `rec`
exit semantics: 3.x exits 0 regardless of the recorded command's
status unless `--return` is passed, while 2.x propagates the child's
status by default and has no `--return` flag. The wrappers probe
`asciinema rec --help` for `--return` support at runtime rather than
hardcoding either behavior, so `pr`/`again` report the real child
exit code (verified: a failing `git push` propagates 128 through
the recording on 3.2.0).

**Failure handling.** `asciinema rec` invocations follow the v8.8
guard convention (`RC=0; asciinema rec ... || RC=$?`) since a non-zero
child exit is a handled case, not a recipe bug. There is no
retry-on-asciinema-failure: a non-zero `asciinema rec` exit means the
child flow ran or was interrupted, and blindly re-running could issue
a duplicate `gh pr create`. If `asciinema` produced no cast at all
(no TTY, e.g. from CI), both wrappers say so and exit with the
child's code.

**Supporting changes.**

- `.repo.toml` gains `asciinema-record = false`; `docs/repo-toml.cue`
  documents the flag; `repo_toml_generate` extracts/emits
  `FLAG_ASCIINEMA_RECORD`
- `cue-verify` validates the flag: enabled + binary present →
  green info; enabled + binary missing → soft yellow warning
  (non-fatal — CI runners won't have asciinema installed and the
  recipes degrade gracefully); disabled → silent, since that's the
  default state for every repo
- new-repo bootstrap (`cue-sync-from-github`) writes
  `asciinema-record = false` by default

**Caveats.** Under asciinema 3.x a missing TTY is auto-detected and
the session records headless (verified); under 2.x `rec` requires an
interactive terminal, and the wrappers handle a missing cast file by
exiting with the child's code after reporting it. `.cast` files
capture raw terminal input/output with no secrets filtering; if a
secret leaks into a recording, delete the file. Default-off mitigates
exposure for the vast majority of runs.

### v8.9 - fix copilot_rollback parsing for legacy backups (2026-09-05)

- Fixes issue [#332](https://github.com/fini-net/template-repo/issues/332)
- **Related PR:** [#344](https://github.com/fini-net/template-repo/pull/344)

`copilot_rollback` (`.just/copilot.just`) reconstructed backup filenames by
splitting on the *first* underscore (`safe_path =${filename%%_*}`). That worked
for current URL-encoded names (post-v6.3, where `/` is `%2F` and `_` is `%5F`,
so the safe path contains no raw underscores) but broke every **legacy**
backup - the old scheme encoded `/` as `_`, so legacy safe paths are full of
underscores. The first-underscore split truncated the path at its first
underscore and let the timestamp pick up path fragments, which meant the legacy
fallback decode branch (`${safe_path//_/\/}`, added back in v5.4) could never
see a full path - it was unreachable by design. Rollback listed wrong targets,
restored to wrong paths, or silently skipped valid legacy backups. Copilot
flagged this recurrence on 12 fini-net repos' v8.\* sync PRs; v7.9
([#216](https://github.com/fini-net/template-repo/pull/216)) fixed the
timestamp-underscore collision for new-format backups only, so this closes the
remaining half of [#199](https://github.com/fini-net/template-repo/issues/199).

Backup names are now parsed by matching the timestamp **pattern** from
the end of the filename (`^ (.*)_([0-9]{8}_[0-9]{6}_[0-9]+)\.bak$`)
rather than by underscore position - neither a first- nor a
last-underscore split works, since the timestamp itself contains two
underscores. The greedy `.*` leaves the full prefix as the safe path,
so both the URL-decode branch (new format) and the legacy `_` for `/`
fallback decode correctly again. Names that match no known format are
skipped with an explicit warning instead of restoring to a guessed
path.

Testing the fix surfaced a second, older bug in the same recipe: the
`"$BACKUP_DIR"/*.bak` globs skipped dot-prefixed filenames entirely
(bash globs exclude dotfiles by default), so backups of `.just/*`
files - the primary thing this repo backs up - never appeared in the
rollback listing at all. `shopt -s dotglob` before the globbing fixes
that; the loop's `[[ -f "$backup" ]]` guard already keeps directories
out of the dotglob-expanded results.

One inherent ambiguity remains and is unchanged: a legacy backup of a
top-level file whose *own name* contained an underscore (e.g.
`my_file.md` -> `my_file_20260128_161000_12345.bak`) decodes to
`my/file.md`, because the legacy scheme simply cannot encode that
distinction. That limitation is baked into the old format and would
need sidecar metadata to fix; it predates this change.

### v8.8 - guard `set -e` bare commands and jq-derived integer comparisons (2026-09-05)

- Fixes issue [#326](https://github.com/fini-net/template-repo/issues/326)
- Fixes issue [#327](https://github.com/fini-net/template-repo/issues/327)
- **Related PR:** [#341](https://github.com/fini-net/template-repo/pull/341)

Two related classes of `set -euo pipefail` fragility that kept
recurring across v8.\* PRs are now fixed at every remaining call site
and documented as a convention in the headers of `copilot.just` and
`gh-process.just`, instead of being patched one-off each time a review
trips over a new instance.

**Issue [#326](https://github.com/fini-net/template-repo/issues/326) - bare
commands under `set -e`.** In `copilot_pick` and `copilot_refresh`
(`.just/copilot.just`), bare `gh api graphql` calls that were not wrapped in
`if`/`&&`/`||` aborted the recipe on any transient GraphQL failure before the
friendly fallback messaging could print. Three sites are fixed:

1. `copilot_pick`'s comment fetch now has a `|| { ... }` block that
  prints a "transient API error - try again" message and exits 1
  deliberately (its temp files are now cleaned by an EXIT trap set
  before the first early exit).
2. `copilot_refresh`'s `THREAD_IDS` fetch falls back to `[]` - a failed
  fetch reads as "nothing to resolve" and the recipe continues.
3. `copilot_refresh`'s post-review `COPILOT_COUNT` fetch falls back to
  empty and is normalized to 0, so the Found/No-suggestions messaging
  always prints.

`_wait_for_checks` (`.just/gh-process.just`) also had a bare
`gum spin`; it now uses the `spin_ok=0; ... || spin_ok=$?` idiom
(established for the copilot spinner in v8.4) and falls back to plain
`poll_for_checks` if gum itself fails.

**Issue [#327](https://github.com/fini-net/template-repo/issues/327) - unguarded
integers from jq/temp files.** Values derived from `jq` or read from temp files
and fed into `[[ ... -eq/-gt ... ]]` crashed with bash "integer expression
expected" when the upstream call failed or returned empty. The v8.3 follow-up
added `${var:-0}` defaults in `wait_for_copilot.sh` but the pattern was not
applied to new sites. All remaining sites are now normalized with `2>/dev/null
|| echo "0"` plus a `[[ "$var" =~ ^[0-9]+$ ]] || var=0` regex guard:
`COMMENT_COUNT` (copilot_pick), `THREAD_COUNT` and `COPILOT_COUNT`
(copilot_refresh), and the `COPILOT_COUNT` pair in `pr_checks` and
`claude_review` (`.just/gh-process.just`) - the latter read from the `/tmp`
count file, the exact site flagged in Claude's review of
[#300](https://github.com/fini-net/template-repo/pull/300).

### v8.7 - pr_checks skips redundant Copilot wait on gh observer path (2026-09-01)

- Fixes issue [#320](https://github.com/fini-net/template-repo/issues/320)
- **Related PR:** [#322](https://github.com/fini-net/template-repo/pull/322)

`pr_checks` (`.just/gh-process.just`) ran `.just/lib/wait_for_copilot.sh` after
the CI watcher exited to stop the one-shot `reviewThreads` GraphQL query from
racing Copilot (the fix for
[#299](https://github.com/fini-net/template-repo/issues/299) in v8.3). That wait
is correct for the `gh pr checks --watch` fallback path, which only watches CI
check runs and does not synchronize with Copilot. But on the `gh observer` path
it is dead time: `gh observer` has gated its own exit on Copilot review
completion since
[gh-observer #409](https://github.com/fini-net/gh-observer/issues/409) (default
`wait_for_copilot: true`, `copilot_max_wait: 180s`), so by the time control
returns to `pr_checks` the review state is already settled. The second wait
therefore spun through its initial delay and first poll before observing the
already-finished review, adding up to ~180s on repos where Copilot is
auto-requested but slow to land and a smaller but still pointless delay on every
PR.

The fix tracks which watcher ran in a new `used_gh_observer` flag set in the
CI-watcher dispatch block. The Copilot wait block now branches on that flag: on
the `gh observer` path it prints a one-line `Copilot wait already handled by gh
observer` note and falls straight through to the GraphQL query; on the `gh pr
checks --watch` path the existing `wait_for_copilot.sh` spinner runs unchanged.
The downstream one-shot `reviewThreads` query is untouched — it runs against
settled state on both paths, which was the whole point of
[#299](https://github.com/fini-net/template-repo/issues/299).

No correctness impact; purely wasted wall-clock removed. Filed as an
enhancement (cleanup) for that reason.

### v8.6 - compliance_check verifies a custom social preview image (2026-09-01)

- Fixes issue [#242](https://github.com/fini-net/template-repo/issues/242)
- **Related PR:** [#321](https://github.com/fini-net/template-repo/pull/321)

`compliance_check` (`.just/compliance.just`) verified nearly all of the
GitHub community-standards surface but did not check whether a custom
social preview image had been uploaded under Settings > General >
Social preview - the image GitHub renders in link unfurls, social-media
cards, and the explore pages; a missing one is the cheapest way for an
otherwise polished repo to look unfinished next to its peers. The
REST `repos/{owner}/{repo}` endpoint does not expose social-preview
state, so the new block queries the GraphQL `Repository` object's
`usesCustomOpenGraphImage` field (`true` only when an admin has
uploaded a custom image), sitting adjacent to the existing
repo-description check so the `[gh]`-prefixed checks stay grouped.

Both `gh` calls in the block are guarded to preserve the recipe's
report-only contract (reddening is possible, non-zero exit is not): a
failed fetch prints a distinct "could not reach GitHub" red message and
falls through to the remaining checks, instead of aborting the recipe
under `set -euo pipefail` or silently reddening with a false negative.
Dogfooding note: this very repo would fail the check today
(`usesCustomOpenGraphImage: false`), which is a good signal the check
does what it says on the tin.

## August 2026

### v8.5 - compliance_check gains OpenSSF Scorecard-aligned checks (2026-08-28)

- Fixes issue [#314](https://github.com/fini-net/template-repo/issues/314)
- **Related PR:** [#317](https://github.com/fini-net/template-repo/pull/317)

`compliance_check` (`.just/compliance.just`) previously verified a handful
of GitHub community-standards files plus branch protection and stopped
there. OpenSSF Scorecard defines a broader set of security-health checks,
many of which are detectable with plain `git`, `gh api`, and `grep` - no
new dependencies.

Eleven new heuristics were appended to the recipe, each report-only
(reddening is possible, non-zero exit is not), prefixed `[openssf]` or
`[gh,openssf]` when the check overlaps GitHub community standards
(Code-Review, which extends the existing branch-protection lookup into
ruleset parameters):

Binary-Artifacts (`file` on tracked files + blobs over 1MB via
`wc -c`), CI-Tests (workflow greps for common test-runner invocations,
including `just <anything>test` recipes), Code-Review (active branch
rulesets requiring reviews), Dangerous-Workflow (`pull_request_target`
paired with `secrets.` usage, `sudo` in workflows), Dependency-Update-Tool
(dependabot/renovate config presence), Maintained (commit within 90
days), Pinned-Dependencies (`uses:` lines without a 40-hex SHA or
`sha256:` digest), Packaging (publish/release workflow commands), SAST
(CodeQL/SonarCloud/Semgrep presence), Signed-Releases (release assets
with `.sig`/`.asc`/`.pem`/`.intoto.jsonl`, BLUE skip when the repo has
no releases), and Token-Permissions (workflows missing a top-level
`permissions:` block).

Two portability pitfalls bit during development and are worth recording:

1. **Unmatched globs break grep-driven checks.** Bash leaves
    `.github/workflows/*.yaml` literal when no `.yaml` files exist, and
    grep then exits 2 (file not found) even when it matched `.yml` files -
    an `if grep` treats any non-zero exit as failure, silently inverting
    the check. Affected checks either recurse the directory
    (`grep -r .github/workflows`, guarded by a `[[ -d ]]` test) or guard
    the glob expansion themselves.
2. **`stat` flags are platform-dependent.** The binary-size heuristic
    originally used `stat -f%z` (BSD/macOS only); it now pipes
    `xargs -0 wc -c` output through awk and skips `total` lines, which
    works on both BSD and GNU.

Verified live on the template repo itself: six `[openssf]` checks pass,
SAST/CI-Tests/Code-Review/Token-Permissions pass, and the three REDs
(docs images flagged as Binary-Artifacts, no Packaging workflow, no
signed release assets) are true findings. All 33 recipe scripts pass
`just shellcheck`.

Review rounds caught three real bugs and several false positives in
the heuristics before merge: the Code-Review check always read GREEN
(`.parameters.required_reviewers` is an *array*, and in jq's type
ordering any array sorts greater than any number - the field is now
`required_approving_review_count`, the numeric approval threshold
Scorecard actually cares about), the `dangerous` variable could abort
workflow-less repos under `set -u` before its consumer ran (now
pre-initialized), and local `uses: ./path` actions were flagged by
Pinned-Dependencies though repo-local composite actions are already
repo-controlled (now exempt). Bare tokens in the CI-Tests heuristic
and the `sudo` grep are word-bounded (`majestic` no longer counts as
a test framework), the Dangerous-Workflow `secrets\.` grep anchors
only the left boundary with `\b` because `-w` can never match
`secrets.NAME`, `uses:` patterns allow the YAML list dash in front
(`- uses:` - in 11 of this repo's 62 occurrences the check had been
vacuously GREEN), and the rulesets and releases fetches are shared
instead of duplicated.

### v8.4 - pr_checks waits for Copilot; shared poll script; claude_review cleanup (2026-08-14)

- Fixes issue [#299](https://github.com/fini-net/template-repo/issues/299)
- **Related PR:** [#300](https://github.com/fini-net/template-repo/pull/300)
- Follow-up to v8.3
  ([#288](https://github.com/fini-net/template-repo/issues/288)), which only
  wired the in-progress / zero-comment detection into `copilot_refresh`

The v8.3 fix closed [#288](https://github.com/fini-net/template-repo/issues/288)
for `copilot_refresh` but left the main PR flow (`just pr` / `just again` ->
`pr_checks` in `.just/gh-process.just`) running a **one-shot** `reviewThreads`
query the moment the CI watcher exited. The watcher only waits for CI checks;
Copilot's review is a dynamic workflow run, not a PR check, so it provides no
synchronization with Copilot at all. When CI settled before Copilot finished
(~2-3 min), `pr_checks` printed "🐈‍⬛ No unresolved Copilot suggestions - looks
good!" - a false negative indistinguishable from a real clean review.

Five fixes ship in v8.4:

1. **`pr_checks` waits for Copilot (main issue).** The v8.3
  poll/state-machine is extracted into a shared
  `.just/lib/wait_for_copilot.sh` and called from `pr_checks` after
  the CI watcher, before the thread-count query (gated on
  `FLAG_COPILOT_REVIEW`). `MODE=nonfatal` lets `pr_checks` fall
  through to the thread query when Copilot was never requested instead
  of failing the whole PR flow, at the cost of a minimum ~20s latency
  before falling through - a deliberate trade of correctness for
  speed (the prior one-shot query raced and produced false negatives).
2. **`copilot_refresh` deduplicated.** The printf-generated temp poll
  script is replaced with a call to the same shared script
  (`MODE=fatal`), so the two paths can't drift again.
3. **`claude_review` early exits no longer skip the Copilot summary.**
  When no Claude comment existed, `claude_review` exited *before* the
  deferred Copilot-count display, so the end-of-run summary never
  mentioned Copilot and the temp file leaked. The Copilot-count block
  now runs first, above every early-exit gate (the disabled-flag gate
  included), so the summary and temp-file cleanup always run.
4. **Stale-review signal after push.** Completion is a Copilot-authored
  review whose `commit.oid` matches the PR's HEAD sha, replacing the
  v8.3 `submittedAt > REQUEST_TIME` filter and working for both
  auto-requested and refresh-requested reviews. At timeout, or on the
  fast-fail path when a stale review is present, the script warns that
  the review is stale and suggests `just copilot_refresh`.
5. **REST fallback comment corrected.** GraphQL `reviewRequests` with
  the `... on Bot { login }` fragment reliably returns
  `copilot-pull-request-reviewer`, while REST
  `/pulls/N/requested_reviewers` returns `{"teams":[],"users":[]}` for
  Copilot - GraphQL is the reliable signal; REST is not a usable
  fallback.

Review follow-ups folded in before merge: the vestigial `USING_GUM=1`
env-var prefix was removed at both call sites (the shared script
always takes it as a positional arg), `wait_for_copilot.sh` was
converted to tabs and given its trailing newline for editorconfig
compliance, the final timeout `exit 1` now honors `MODE` (exits 0 in
nonfatal mode, matching the fast-fail path and the docstring
contract), and `copilot_refresh`'s failure branch cleans up the stale
sentinel and any stray count file.

### v8.3 - copilot_refresh detects in-progress and zero-comment reviews (2026-08-04)

- Fixes issue [#288](https://github.com/fini-net/template-repo/issues/288)
- **Related PR:** [#289](https://github.com/fini-net/template-repo/pull/289)

The `copilot_refresh` poll loop in `.just/copilot.just` had four bugs
that surfaced while watching Copilot review a live PR (#85 on
adRise/tubi-observability, `gh 2.95.0`):

1. **No in-progress detection.** The poll only queried `reviews(last: 1)`,
  never `reviewRequests`, so it could not tell "still processing" from
  "never started" and printed dots until the 180s timeout even when
  everything was fine.
2. **Zero-comment reviews never registered as complete.** The loop
  required *both* a review state *and* `comment_count > 0`, so Copilot's
  "looks good, no suggestions" review (`COMMENTED` with
  `comments.totalCount == 0`) timed out and exited 1 - a false failure
  for the *best* outcome.
3. **`gh pr view --json reviewRequests` silently drops Bot reviewers.**
  Any detection built on that field will not work. The fix queries
  GraphQL `reviewRequests` directly with a `... on Bot { login }`
  fragment (Copilot shows up as `copilot-pull-request-reviewer` there;
  REST `/pulls/{n}/requested_reviewers` returns `Copilot`).
4. **`reviews(last: 1)` could miss Copilot's review.** If Claude or a
    human reviewed after Copilot, the `last: 1` + jq author filter
    yielded nothing and the loop fell back to "not complete". The fix
    uses `reviews(last: 10)` and selects the Copilot-authored review
    client-side.
5. **Stale reviews from earlier refresh cycles produced false
    "complete".** `copilot_refresh` is meant to be called repeatedly on
    the same PR (make changes -> refresh -> iterate), but the "is there
    already a Copilot review" check matched any Copilot-authored review
    regardless of when it was submitted. The next refresh would hit the
    stale review from the prior cycle immediately and print
    `Review complete after 10s` without ever waiting for Copilot to
    process the new commits. `submittedAt` was already fetched by the
    GraphQL query but never used. The fix captures `REQUEST_TIME` right
    after the REST POST that requests the reviewer and filters the jq
    selection with `.submittedAt > $requestTime` (string comparison works
    for ISO-8601 UTC timestamps).

The rewritten poll loop runs a single GraphQL call per iteration that
fetches both `reviewRequests(first: 10)` (with Bot/User/Team fragments)
and `reviews(last: 10)`, then applies a three-state machine:

1. Copilot review exists with any state -> **complete** (0 comments is
  reported as "no suggestions", not a failure).
2. Else if Copilot is in `reviewRequests` -> **in progress**, keep
  polling (and track that we have seen it in progress so a later
  disappearance is not mistaken for "never started").
3. Else -> fail fast with a useful message ("Copilot was not found in
  reviewRequests and has no review") instead of waiting 180s, including
  a REST fallback hint if GraphQL ever stops surfacing the Bot
  reviewer.

The fail-fast path requires two consecutive "not found" polls before
exiting 1, so a single GraphQL read that lags the prior REST POST that
requested the review (cross-service eventual consistency on GitHub's
side) does not produce a false failure on the very first poll.

## June 2026 - Bug squash June

### v8.2 - document unset single-quote idiom (2026-06-29)

- Fixes issue [#203](https://github.com/fini-net/template-repo/issues/203)
- **Related PR:** [#222](https://github.com/fini-net/template-repo/pull/222)

`.just/lib/update_pr_body.sh` trims trailing blank lines from the
PR footer with a `while`/`unset` loop:

```bash
unset 'footer_content[${#footer_content[@]}-1]'
```

This is correct — bash's `unset` builtin evaluates its subscript as
arithmetic even when the argument is single-quoted, so
`${#footer_content[@]}` resolves at call time inside `unset`, not in
the calling shell. The single quotes are load-bearing: without them
the calling shell would expand `${#footer_content[@]}` to the array
length *before* `unset` ran, producing a literal index like
`footer_content[5-1]` that would never shrink as the loop iterated.

The idiom kept tripping reviewers as a false-positive bug. Copilot flagged it as
a hard error in [fini-net/gh-amp#17](https://github.com/fini-net/gh-amp/pull/17)
(claiming the single quotes prevented evaluation), and Claude's deeper review on
template-repo PR [#174](https://github.com/fini-net/template-repo/pull/174)
confirmed it was safe but suggested documenting the fragility. Each re-flag
costs a review round-trip.

v8.2 adds a three-line comment directly above the `unset` inside the
loop, explaining why the single-quoting is correct and what it
guards against. No behavior change; the `15_trailing_blanks` fixture
in `pr_body_test` continues to exercise the loop.

### v8.1 - fix awk backslash mangling in cue-sync (2026-06-29)

- Fixes issue [#198](https://github.com/fini-net/template-repo/issues/198)
- **Related PR:** [#221](https://github.com/fini-net/template-repo/pull/221)

`cue-sync-from-github` escaped the GitHub description for TOML but
passed the result to awk via `-v desc=...`. awk's `-v` assignment
processes backslash escape sequences before the program runs, so any
backslash in a repo description (Windows paths, regexes, prose) was
silently mangled — `C:\path\to\thing` became `C:athothing`. The
resulting TOML was structurally valid, so `cue vet` didn't catch it;
the trailing `cue-verify` then detected a mismatch against the GitHub
API, restored the backup, and exited 1 — leaving sync permanently
broken for any repo with a backslash in its description.

The initial fix double-escaped backslashes before the quote-escape
step so awk's `-v` un-escaped them back to single backslashes. That
prevented the mangling but produced **invalid TOML** — a raw
`description = "C:\path"` contains an illegal `\p` escape, so
`cue vet` failed on the modified file and the sync still broke. The
same unescaped write also affected the else branch that creates a
new `.repo.toml` from scratch, where there was no previous file to
restore from, so the failure was permanent on first-time sync.

v8.1 moves the contract to its root: the description is passed to
awk via the environment (`desc=...`), not `-v`, so no escape
processing happens before the program runs. The awk program itself
applies TOML-escaping (`\`→`\\`, `"`→`\"`) on emit via a new
`toml_escape()` helper, so the output is valid TOML regardless of
the description's contents. The else branch that bootstraps a new
`.repo.toml` mirrors the same escape in shell before `printf`. The
mirrored escape step in the test runner (`cue_sync_test.sh`) is
gone — both paths now pass the raw description and let awk own the
escaping. `ENVIRON` is POSIX awk, supported by gawk, mawk, nawk,
and busybox awk on all target platforms.

### v8.0 - extract shared `cue_sync.awk` (2026-06-29)

- Fixes issue [#196](https://github.com/fini-net/template-repo/issues/196)
- **Related PR:** [#219](https://github.com/fini-net/template-repo/pull/219)

The awk program powering `cue-sync-from-github` was duplicated verbatim between
`.just/cue-verify.just` (the production recipe) and `.just/lib/cue_sync_test.sh`
(the test runner). The test file even acknowledged the hazard with a "keep this
in sync with the recipe" comment — the exact fragility that caused the original
[#165](https://github.com/fini-net/template-repo/issues/165) regression the test
suite was built to guard against. If the recipe's awk was silently modified
without updating the test copy, the tests kept passing while production code
regressed: the test validated a **copy**, not the production path.

v8.0 extracts the awk program to a standalone file,
`.just/lib/cue_sync.awk`, and both the recipe and the test runner now
invoke it via `awk -f .just/lib/cue_sync.awk`. A change to the awk is
automatically exercised by both callers, and the "keep in sync"
comment is gone.

To keep derivative repos in lockstep with future awk changes, the
checksum generator (`.just/lib/generate_checksums.sh`) now globs
`.just/lib/*.awk` alongside `*.sh`, so `cue_sync.awk` becomes a
CHECKSUMS-tracked file and flows through `just update_from_template`.
The `cue-sync-tests.yml` workflow path triggers also gained
`.just/lib/cue_sync.awk` so the test suite runs whenever the awk is
edited. `clean_template` intentionally **keeps** `cue_sync.awk`
(only the test infra is stripped) because `cue-verify.just`, which
derived repos retain, depends on it.

### v7.9 - fix `copilot_rollback` restoring to wrong path (2026-06-29)

- **Related PR:** [#216](https://github.com/fini-net/template-repo/pull/216)
- Fixes issue [#199](https://github.com/fini-net/template-repo/issues/199)

`copilot_rollback` reconstructed the original file path from the backup
filename by stripping suffixes from the **right**. Because the timestamp
format (`YYYYMMDD_HHMMSS_PID`) contains two literal underscores,
`${filename%_*}` only removed the trailing `_<PID>.bak` and left the
`YYYYMMDD_HHMMSS` fragment glued onto the encoded path. The result was
a non-existent target like `.just/copilot.just_20260626_143022`, so the
restore silently wrote to the wrong file and the real source was never
restored (issue [#199](https://github.com/fini-net/template-repo/issues/199)).

The parser now strips from the **left**: `${filename%%_*}` takes
everything before the first `_` as the safe path (safe because
`safe_path` is `%5F`-encoded and contains no literal `_`), and
`${filename#*_}` yields the full `YYYYMMDD_HHMMSS_PID` timestamp. The
backup-writing code was already correct; only the parser needed fixing.

### Docs - clarify `.just/*` versioning rule and emoji wording in CLAUDE.md (2026-06-28)

- No CHECKSUMS-tracked file changed in this entry, so no version bump.
- No issue for this improvement.
- **Related PR:** [#215](https://github.com/fini-net/template-repo/pull/215)

`CLAUDE.md` previously scattered the "bump version + add release-notes
entry" rule across three places (the dev-workflow step, and two bullets
in "Important implementation notes"), making it easy to miss that the
rule applies to **every** `.just/*` file, not only `gh-process.just`.
The guidance is now consolidated into a dedicated
[Versioning `.just/*` changes](../CLAUDE.md#versioning-just-changes)
section that states the two coupled actions once and lists the
affected modules explicitly.

The emoji guidance was also reworded to make explicit that the leading
emoji on the first commit is a free choice by the committer — there is
no `just` recipe that randomizes or validates it, despite the prior
wording implying a convention without a mechanism.

### v7.8 - fail on malformed web_url in repo_toml_generate (2026-06-28)

- Fixes issue [#200](https://github.com/fini-net/template-repo/issues/200)
- **Related PR:** [#214](https://github.com/fini-net/template-repo/pull/214)

`repo_toml_generate` derived `ORG_NAME` and `REPO_NAME` from `WEB_URL`
via two `sed -E` substitutions at `.just/repo-toml.just:43-44`. On a
no-match, `sed` echoes the input through unchanged, so the subsequent
`-z` validation at lines 47-52 could not catch malformed `web_url`
values: `not-a-url` passed through unchanged (non-empty, so `-z` was
happy) and produced garbage derived names, while
`https://github.com/org/repo/extra` silently dropped the trailing
segment and produced a wrong `REPO_NAME`.

v7.8 replaces the sed calls and the `-z` guard with a single bash
regex match:

```bash
if [[ "$WEB_URL_RAW" =~ ^https://github\.com/([^/]+)/([^/]+)$ ]]; then
    ORG_NAME="${BASH_REMATCH[1]}"
    REPO_NAME="${BASH_REMATCH[2]}"
else
    echo "Error: web_url does not match expected format"
    exit 1
fi
```

This mirrors the cue schema at `docs/repo-toml.cue:24`
(`^https://github\\.com/[^/]+/[^/]+$`) as defense-in-depth: `cue vet`
runs earlier in the recipe (lines 20-24) and would already reject most
malformed values, but the extraction now fails explicitly on the same
pattern so a future schema loosening or a bypassed cue stage can't
silently produce garbage.

The strict match rejects:

- Missing scheme / wrong host (`not-a-url`, `http://example.com/o/r`)
- Bare host or empty org/repo (`https://github.com/`, `https://github.com/org`)
- Extra path segments (`https://github.com/org/repo/extra`)
- Trailing slash (`https://github.com/org/repo/`)
- Empty string

### v7.7 - fix errexit bypass in cue-sync-from-github (2026-06-28)

- **Related PR:** [#213](https://github.com/fini-net/template-repo/pull/213)
- **Related issue:** [#197](https://github.com/fini-net/template-repo/issues/197)

The `cue-sync-from-github` recipe wrote its awk output via
`awk ... > .repo.toml.tmp && mv .repo.toml.tmp .repo.toml`
at `.just/cue-verify.just:233`. The script runs under `set -euo pipefail`,
but commands in a `&&` list are exempt from errexit — so if `awk` failed,
the failure was swallowed and the recipe continued with the stale
`.repo.toml`, proceeding to the `cue vet` and `just cue-verify` stages
unexpectedly. This undermined the two-stage validation that v6.9 added
specifically to catch silent sync failures.

v7.7 splits the `&&`-joined line into two separate commands so `set -e`
behaves as intended: if `awk` exits non-zero, the recipe aborts
immediately and `mv` is skipped, leaving the backup/restore path intact.

### v7.6 - guard gh-observer detection when gh absent (2026-06-28)

- **Related PR:** [#212](https://github.com/fini-net/template-repo/pull/212)
- **Related issue:** [#201](https://github.com/fini-net/template-repo/issues/201)

`.just/lib/install-prerequisites.sh:75` ran `gh extension list` to detect
`gh-observer` without first verifying that `gh` itself was installed. The
top-level `gh` guard at line 39 only covered the `gh` tool detection
block, leaving the `gh-observer` detection at line 75 unguarded. On a
system without `gh`, the scan emitted a `command not found` error
(despite the `2>/dev/null` redirection, which only suppresses stderr
from `gh`, not the shell's own "command not found" message for a missing
binary).

v7.6 adds a `command -v gh &>/dev/null &&` guard to the `gh-observer`
detection block. When `gh` is absent, `gh-observer` now falls cleanly
into the `MISSING` list instead of producing noisy errors, matching the
behavior of every other tool in the scan.

### v7.5 - skip workflow watcher in pr_checks when repo has no workflows (2026-06-28)

- **Related PR:** [#211](https://github.com/fini-net/template-repo/pull/211)
- **Related issue:** [#182](https://github.com/fini-net/template-repo/issues/182)

`pr_checks` was unconditionally invoking `gh observer` (or `gh pr checks --watch`)
even on repos with no `.github/workflows` directory. The previous guard in the `pr`
recipe body (`exit 0` when workflows were absent) never actually prevented
`pr_checks` from running: in just, subsequent dependencies (`recipe: dep && post_dep`)
always execute after the recipe body exits successfully — `exit 0` ends the bash
subprocess, but just still dispatches `post_dep`.

v7.5 moves the guard into `pr_checks` itself, wrapping only the watcher invocation
in `if [[ -d ".github/workflows" ]]; then ... fi`. The misleading dead-code guard
in the `pr` recipe body was also removed. The Copilot/Claude review steps after
the watcher are unaffected and continue to run regardless.

### v7.4 - fix is_cleaned jq filter in checksums_verify (2026-06-26)

- **Related PR:** [#208](https://github.com/fini-net/template-repo/pull/208)
- **Related issue:** [#195](https://github.com/fini-net/template-repo/issues/195)

The `is_cleaned` jq filter in `.just/template-sync.just` was always evaluating
to true for any non-empty `cleaned_files` list, causing `checksums_verify` to
silently report "removed by clean_template" for every missing file regardless
of whether it was actually listed in `cleaned_files`.

The broken filter `any($fp | startswith(.))` rebinds `.` to `$fp` inside `any`,
so `startswith(.)` becomes `startswith($fp)` — a string always starts with
itself, so the result is always true.

The same bug was fixed in `.just/lib/template_update.sh` in v6.7 (PR
[#163](https://github.com/fini-net/template-repo/pull/163)) but the companion
check in `template-sync.just` was missed. v7.4 applies the same corrected
filter:

```jq
any(. as $p | $fp | startswith($p + "/") or $fp == $p)
```

This correctly matches only files that are equal to a cleaned path or are
nested under a cleaned directory.

### v7.3 - shellcheck auto-generates repo-toml.sh (2026-06-26)

- **Related PR:** [#207](https://github.com/fini-net/template-repo/pull/207)
- **Related issue:** [#192](https://github.com/fini-net/template-repo/issues/192)

`just shellcheck` reported 4 confusing `SC1091` "Not following" errors on every
fresh-clone run, because `.just/repo-toml.sh` is gitignored and generated by
`just repo_toml_generate`. Four recipes in `.just/gh-process.just`
(`release`, `pr_checks`, `claude_review`, `release_age`) `source` that file, so
shellcheck emits a cryptic `openBinaryFile: does not exist` message that gives
no hint how to fix it.

v7.3 adds a guard at the top of the `shellcheck` recipe in
`.just/shellcheck.just`: if `.just/repo-toml.sh` is missing, it runs
`just repo_toml_generate` automatically. If generation fails (missing `cue`/`jq`
or `.repo.toml`), the recipe prints a single clear warning and exits non-zero
rather than continuing and emitting 4 misleading failures.

### v7.2 - clean_template strips cue-sync test infra; mktemp portability (2026-06-26)

- **Related PR:** [#205](https://github.com/fini-net/template-repo/pull/205)
- **Related issue:** [#194](https://github.com/fini-net/template-repo/issues/194)

`just clean_template` already removed the PR-body test infrastructure
(`.just/testing.just`, `.just/lib/pr_body_test.sh`, `.just/test/`, and the
`pr-body-tests.yml` / `checksums-verify.yml` workflows) but the cue-sync test
infra added in v6.9 (PR
[#175](https://github.com/fini-net/template-repo/pull/175)) was never added to
the cleanup. Derived repos that ran `clean_template` shipped a dead
`.just/lib/cue_sync_test.sh` runner whose missing-fixtures guard at line 156–160
exits 0 with "Tests skipped" — `just cue_sync_test` asserted nothing and went
green in 9+ derived repos.

v7.2 adds `.github/workflows/cue-sync-tests.yml` and `.just/lib/cue_sync_test.sh`
to `_remove_template_files` and to `CLEANED_FILES` in `generate_checksums.sh`,
matching the existing `pr_body_test.sh` pattern. The `cue_sync_test` recipe
itself was already removed via the wholesale `.just/testing.just` deletion.

v7.2 also strips `.github/workflows/template-sync.yml`, which runs
`just template_sync_test` — a recipe that references the now-removed
`template_sync_test.sh`. Derived repos were left with a workflow that fails
on every qualifying push/PR. The same `_remove_template_files` / `CLEANED_FILES`
pattern applies. The `update_from_template` machinery
(`.just/template-sync.just`, `.just/lib/template_update.sh`,
`.just/lib/generate_checksums.sh`, `.just/CHECKSUMS.json`) is intentionally
retained so derived repos can still self-update from template-repo.

While touching the runner, fix `mktemp -d` at `cue_sync_test.sh:119` to use a
portable template (`mktemp -d -t cue_sync_test.XXXXXX`) so it works on
BSD/macOS, which require X's in the template. Flagged by Copilot in
[fini-projects#31](https://github.com/fini-net/fini-projects/pull/31).

### v7.1 - Drop npm fallback for markdownlint-cli2 (2026-06-25)

- **Related PR:** [#186](https://github.com/fini-net/template-repo/pull/186)
- Fixes issue [#185](https://github.com/fini-net/template-repo/issues/185)

PR [#186](https://github.com/fini-net/template-repo/pull/186) pinned
`markdownlint-cli2` via Homebrew to satisfy Scorecard's Pinned-Dependencies
check, but the macOS install path still fell back to `npm install -g
markdownlint-cli2` when Homebrew was absent — an unpinned install that left the
Scorecard warning in place. v7.1 removes the npm fallback so the prerequisites
installer is brew-only on macOS, matching the PR's stated goal.

**Changes:**

- **Removed the npm fallback branch** in `.just/lib/install-prerequisites.sh`
  for the macOS `markdownlint-cli2` case. The `elif command -v npm` arm
  (with its yellow "falling back to npm (unpinned - Scorecard may still
  warn)" message) is gone; the remaining `else` now reports "Homebrew is
  not installed! Install Homebrew first." and points at
  <https://brew.sh>, without suggesting Node.js as an alternative.
- **Stripped the npm parenthetical** from the unsupported-OS install
  hint line, which now reads `markdownlint-cli2: brew install
  markdownlint-cli2` instead of `... (or npm install -g markdownlint-cli2)`.
- **Linux case unchanged** — the linux branch still prints an npm hint
  when neither brew is available, since brew is uncommon on Linux and
  the hint is user-facing guidance rather than an automated fallback.

### v7.0 - Resolve v6.9/v6.10 version-label confusion (2026-06-24)

- **Related PR:** [#178](https://github.com/fini-net/template-repo/pull/178)

PR [#175](https://github.com/fini-net/template-repo/pull/175) (v6.9) landed on
`main` as a single squash commit, but the messy branch history that preceded it
leaked two artifacts through into the shipped state: the `pr` recipe comment in
`.just/gh-process.just` read `# PR create v6.10`, and `RELEASE_NOTES.md` carried
a separate `### v6.10 - Complete cue-sync test matrix` section describing
follow-up review work that never existed as its own release. The
`.just/CHECKSUMS.json` manifest was similarly misaligned - its "latest" entries
for `.just/cue-verify.just`, `.just/testing.just`, and
`.just/lib/cue_sync_test.sh` pointed at intermediate branch commits (`dc02707`,
`1f0b3c3`, `626d593`) with empty `version` strings, rather than the squash
commit (`d499305`) that actually landed on `main`.

v7.0 reconciles the labels so the version recorded for each file matches
what actually shipped.

**Changes:**

- **Reverted the `pr` recipe comment** in `.just/gh-process.just` from
  `# PR create v6.10` back to `# PR create v6.9`, undoing the spurious
  bump. (The pr recipe logic itself is unchanged in v7.0 - this PR only
  touches the comment text and bookkeeping.) The commit that performs
  this revert is itself tagged `v7.0` in the regenerated manifest, so it
  becomes the new latest checkpoint for `gh-process.just` while
  `d499305` is recorded as the prior `v6.9` historical entry.
- **Folded the v6.10 release notes into v6.9.** The four bullets that described
  the cue-sync test-matrix completion (the `commented_topics.toml` and
  `active_keys.toml` fixtures, trailing newlines on the v6.9-added files, and
  the `SC2002` fix in `cue_sync_test.sh`) all shipped inside PR
  [#175](https://github.com/fini-net/template-repo/pull/175)'s squash, so they
  belong under v6.9. The standalone `### v6.10` section and its month header are
  removed; the bullets are appended to the existing v6.9 "Changes" list.
- **Regenerated `.just/CHECKSUMS.json`:**
  - Dropped the orphan intermediate-branch commits (`dc02707`,
    `1f0b3c3`, `626d593`) from the manifests for `cue-verify.just`,
    `testing.just`, and `lib/cue_sync_test.sh`. These never reached
    `main` and were producing misleading "latest" pointers.
  - Retagged the surviving latest entry for each of those files to
    point at the real main squash commit `d499305` with `version:
    "v6.9"`, so `just checksums_verify` in derived repos resolves
    against the commit they actually received.
  - For `gh-process.just`, recorded this PR's commit (`80f3451`) as the
    new `v7.0` latest entry and demoted the previous latest to a
    historical `v6.9` entry pinned to `d499305`.
  - Refreshed `generated_at`.

No issue was filed for this work - it was a pure bookkeeping follow-up
to PR [#175](https://github.com/fini-net/template-repo/pull/175)'s landing.

### v6.9 - Handle commented/missing topics & defer backup deletion (2026-06-24)

- **Related PR:** [#175](https://github.com/fini-net/template-repo/pull/175)
- Fixes issue [#165](https://github.com/fini-net/template-repo/issues/165)

`just cue-sync-from-github` silently failed to sync `topics` (and would
have failed for `description` too) when the corresponding line in
`.repo.toml` was either **commented out** (`# topics = []`) or **missing
entirely** from the `[about]` section. The recipe still reported
"Successfully synced from GitHub to .repo.toml", and the trailing
`just cue-verify` was the only signal of the failure - by which point
the `.repo.toml.backup` restore point had already been deleted.

**Root cause:** The awk block's match patterns anchored on `^topics =`/`^description =`, so a leading `#` defeated the match, and there was
no insert-if-missing logic. Compounding this, the backup was deleted as
soon as `cue vet` passed - but `topics` is optional in the CUE schema,
so `cue vet` passing does not prove the sync wrote anything.

**Changes:**

- **Rewrote the awk block in `.just/cue-verify.just`** to:
  - Match commented-out lines via a `[#[:space:]]*` prefix tolerance, so
    `# topics = [...]` is rewritten in place just like an active line.
  - Track whether each key (`description`, `topics`) was written during
    the pass, and insert any missing keys at the end of the `[about]`
    block, *before* any trailing blank line that separates it from the
    next section. Blank lines inside `[about]` are buffered and flushed
    only after pending missing-key insertions, so the inserted key lands
    adjacent to the preceding key (e.g. `license`) rather than after the
    blank line (which would visually attach it to the next `[section]`).
    Missing keys are flushed either when the next `[section]` begins or
    at EOF via an `END` block. This preserves the original field order of
    any other keys in `[about]` (e.g. `license`).
- **Deferred backup deletion** in `cue-sync-from-github`: the
  `.repo.toml.backup` is now preserved through both `cue vet` *and* the
  trailing `just cue-verify`. If `cue-verify` reports a mismatch (the
  signal for a silent topics-write failure), the working copy is
  restored from backup rather than leaving a half-synced file behind.
- Removed the duplicate trailing `just cue-verify` call that existed
  outside the existing-file branch; the verification now runs inside
  each branch (existing-file and create-new-file) so the backup
  restore logic can wrap it.
- Added `.just/test/fixtures/cue_sync/commented_topics.toml` and a corresponding
  test case. This is the headline fix for issue
  [#165](https://github.com/fini-net/template-repo/issues/165), yet the original
  test matrix only covered `commented_description` - `commented_topics` is the
  exact regression the awk change targets.
- Added `.just/test/fixtures/cue_sync/active_keys.toml` and a happy-path
  test case with both `description` and `topics` active, guarding against
  any future awk change silently breaking the pre-existing in-place
  replace behaviour.
- Fixed `cat "$output" | sed ...` (SC2002) in `cue_sync_test.sh` debug
  output; `just shellcheck` flags this.

### v6.8 - Trailing blank line accumulation fix (2026-06-23)

- **Related PR:** [#174](https://github.com/fini-net/template-repo/pull/174)
- Fixes issue [#173](https://github.com/fini-net/template-repo/issues/173)

Running `just again` repeatedly on a PR caused trailing blank lines to
accumulate at the bottom of the PR description. Each `pr_update` cycle
added ~2 trailing blank lines, so a PR iterated on 8 times ended up with
~16 trailing blank lines after the `## Meta` section.

**Root cause:** A feedback loop between three actors, each appending a
trailing newline:

1. GitHub's REST/GraphQL API appends a trailing `\n` when storing a PR
  body via `gh pr edit --body-file`.
2. `jq -r '.body'` in `pr_update` appends its own trailing `\n` (jq
  always emits a trailing newline on raw output).
3. `.just/lib/update_pr_body.sh` emitted `footer_content` verbatim,
  preserving trailing blank lines instead of trimming them.

**Changes:**

- **Trim trailing blank lines from `footer_content`** -
  `.just/lib/update_pr_body.sh` now strips trailing empty entries from
  the `footer_content` bash array before emitting the footer. This
  breaks the accumulation cycle at the parser regardless of how many
  newlines the GitHub API or jq add during round-trips. The header is
  intentionally left untrimmed to keep the fix scoped to the documented
  bug.
- **Regression test fixture** - Added
  `.just/test/fixtures/pr_bodies/15_trailing_blanks/` with an input
  body carrying 4 trailing blank lines (simulating the post-round-trip
  state after a few `pr_update` cycles) and an expected output with
  those blanks stripped. Auto-discovered by `pr_body_test.sh`.

**Related:** The v4.4 blank-line preservation fix (PR
[#50](https://github.com/fini-net/template-repo/pull/50)) correctly guarded
blank lines *between* sections but inadvertently also preserved the
trailing-blank-line accumulation path this issue describes. The v5.8 CRLF
normalization (PR [#107](https://github.com/fini-net/template-repo/pull/107)) is
a related robustness effort.

### v6.7 - Fix update_from_template failures on test fixtures (2026-06-20)

- **Related PR:** [#163](https://github.com/fini-net/template-repo/pull/163)
- Fixes issue [#162](https://github.com/fini-net/template-repo/issues/162)

Running `just update_from_template` in a derived repo failed with seven
`Download failed after 3 attempts` lines for `.just/test/fixtures/...` paths.
Three compounding bugs were found and fixed.

**Changes:**

- **Exclude test fixtures from the manifest** - `.just/lib/generate_checksums.sh`
  now uses `git ls-files '.just/*.just' ':(exclude).just/test/**'` so git's
  pathspec `*` (which matches across `/`) no longer pulls nested fixture paths
  like `.just/test/fixtures/template_sync/01_unmodified_file/expected_state/.just/test.just`
  into `CHECKSUMS.json`. Those fixtures are only meaningful inside template-repo
  itself and should never be distributed to derived repos. Regenerated the
  manifest, which dropped from 25 to 18 tracked files.
- **Fix `is_cleaned` jq scoping bug** - The `any($fp | startswith(.))`
  expression in `template_update.sh` rebound `.` to `$fp` after the pipe, so
  `startswith(.)` became `startswith($fp)` — always true. This silently treated
  *every* missing file as "cleaned", masking the fixture symptom and breaking
  `update_from_template` for genuinely new template modules. Replaced with
  `any(. as $p | $fp | startswith($p))` to capture the array element before
  piping.
- **`mkdir -p` before download** - `download_file` now creates the target
  directory with `mkdir -p "$(dirname "$filepath")"` before writing
  `${filepath}.tmp`. Previously the nested `.just/test/fixtures/.../.just/`
  directory didn't exist in derived repos, so `curl -o` failed on every retry.
- **Surface curl stderr on failure** - The final failure branch now captures
  curl's stderr to a temp file and prints it (`curl error: ...`) instead of
  `2>/dev/null` swallowing the real "no such directory" error, which is what
  produced the misleading "Download failed after 3 attempts" message.
- **Backward compat** - `.just/test` remains in `CLEANED_FILES` so derived repos
  that somehow already received the fixture files still skip them as cleaned.

## May 2026 - The Repolish Updates

### v6.6 - Cleaner Copilot Review Feedback (2026-05-22)

- **Related PRs:** [#152](https://github.com/fini-net/template-repo/pull/152)
- Fixes issue [#151](https://github.com/fini-net/template-repo/issues/151)

Improved Copilot review feedback in two ways: filtering out resolved suggestions
and auto-resolving old suggestions before requesting fresh reviews. Previously,
resolved suggestions cluttered the output and stale suggestions from previous
review rounds lingered alongside fresh ones, making it hard to tell which items
still needed attention.

**Changes:**

- **Unresolved-only filter** - Added `isResolved` filter to the GraphQL query
  so only open Copilot review threads are shown.
- **Resolve before refresh** - `copilot_refresh` now fetches all unresolved
  Copilot review thread IDs via GraphQL, then calls the `resolveReviewThread`
  mutation on each one before requesting the new Copilot review.
- **Cleaner feedback** - Resolved suggestions are excluded from the count and
  display, reducing noise after addressing feedback.
- **Detailed reporting** - Shows how many suggestions were resolved and warns
  if any failed to resolve (e.g., due to permission issues).
- **Clean feedback loop** - Each refresh starts with a clean slate so all
  suggestions come from the latest review round.

### v6.5 - Install gh-observer (2026-05-01)

- **Related PR:** [#142](https://github.com/fini-net/template-repo/pull/142)
- Fixes issue [#123](https://github.com/fini-net/template-repo/issues/123)

Added `gh-observer` as a required tool in the prerequisites installation script.
The `gh-observer` extension was already used by the `pr` recipe (v5.7) but wasn't
listed in the prerequisites, so a missing installation would silently fall back
to the polling loop. Now it's properly detected, installed, and reported alongside
the other tools.

**Changes:**

- **gh-observer in prerequisites** - Added `gh-observer` (the `gh observer` extension)
  to `install-prerequisites.sh`: detection via `gh extension list`, Homebrew-style
  installation using `gh extension install chicks-net/gh-observer` on macOS, and
  manual install instructions for Linux and other platforms.

## April 2026 - Guard rails

### v6.4 - Prerequisites Update and Cue Schema Fix (2026-04-23)

- **Related PR:** [#131](https://github.com/fini-net/template-repo/pull/131)
- Fixes issue [#118](https://github.com/fini-net/template-repo/issues/118)

Added `cue` as a required tool in the prerequisites installation script and
fixed a regex bug in the repo-toml Cue schema.

**Changes:**

- **Cue in prerequisites** - Added `cue` (the Cue validation tool) to the
  `install-prerequisites.sh` script: detection, Homebrew installation on
  macOS, and manual install instructions for Linux and other platforms.
- **Web URL regex fix** - Changed `web_url` regex in `docs/repo-toml.cue`
  from `[^/]+/.+` to `[^/]+/[^/]+` to prevent matching URLs with trailing
  path segments that aren't valid repository URLs.

### v6.3 - Copilot Path Encoding and Portability Fixes (2026-04-23)

- **Related PR:** [#130](https://github.com/fini-net/template-repo/pull/130)
- Fixes issue [#114](https://github.com/fini-net/template-repo/issues/114)

Fixed four bugs in `.just/copilot.just` identified across 15 PR code reviews.

**Changes:**

- **`sed -i` portability** - Replaced `sed -i` (which differs between BSD and GNU)
  with a temp-file approach (`sed ... > file.tmp && mv file.tmp file`) for
  cross-platform compatibility.
- **URL-encoded backup paths** - Backup filenames now use URL-encoding
  (`%2F` for `/`, `%5F` for `_`, `%25` for `%`) instead of replacing `/` with `_`,
  which was ambiguous and lossy. `copilot_rollback` decodes the new format with a
  legacy fallback for old backups.
- **Unambiguous suggestion matching** - `copilot_pick` now matches suggestions by
  both file path and line number (instead of line number alone), preventing
  incorrect matches when multiple files have suggestions on the same line.
- **Self-contained polling script** - `copilot_refresh` now writes the poll loop
  to a temp script file and passes variables as arguments, instead of serializing
  the function with `declare -f` which breaks with complex function state.

### v6.2 - Template Sync Refinements (2026-04-23)

- **Related PR:** [#129](https://github.com/fini-net/template-repo/pull/129)
- Fixes issue [#116](https://github.com/fini-net/template-repo/issues/116)

Improved robustness of the template sync system with better error handling
and smarter path matching for cleaned files.

**Changes:**

- **Checksum verification on download** - `template_update.sh` now verifies
  downloaded files against expected checksums before moving them into place,
  catching corrupted or incomplete downloads immediately. Passes the expected
  checksum from the manifest to `download_file()` so mismatches are detected
  before overwriting local files.
- **Directory-aware cleaned file matching** - Both `template-sync.just` and
  `template_update.sh` now use `startswith` matching instead of exact path
  matching when checking cleaned files. This means if a directory is listed
  in `cleaned_files`, any file under that directory is properly recognized as
  cleaned, not just the exact directory path itself.
- **Missing checksum tool error** - `checksums_verify` recipe now explicitly
  exits with an error message if neither `sha256sum` nor `shasum` is found,
  instead of silently producing empty output.

### v6.1 - Shell Escaping in repo_toml_generate (2026-04-23)

- **Related PR:** [#126](https://github.com/fini-net/template-repo/pull/126)
- Fixes issue [#117](https://github.com/fini-net/template-repo/issues/117)

Fixed improper shell quoting in `repo_toml_generate` that could produce broken
output when `.repo.toml` values contain shell metacharacters (spaces, quotes,
dollar signs, backticks, etc.). Identified across 15 PRs in code review.

**Changes:**

- **jq @sh for JSON-sourced values** - `DESCRIPTION`, `LICENSE`, `GIT_SSH`,
  `WEB_URL`, and all feature flags now use `jq @sh` to produce properly
  single-quoted shell-safe strings (e.g., `'value with spaces'`)
- **printf %q for derived values** - `ORG_NAME`, `REPO_NAME`, and `TOPICS_CSV`
  use `printf '%q'` via new `shell_quote()` helper since these come from `sed`
  and `paste`, not `jq`
- **Safe array items** - Topics array items now use `shell_quote()` instead
  of bare `"$topic"` interpolation
- **shell_quote() helper** - New function reduces repetition and provides a
  single point of maintenance for shell escaping logic
- **WEB_URL_RAW intermediate** - Strips `@sh` quoting before URL parsing since
  `sed` needs the raw URL, not the shell-quoted form

The generated `.just/repo-toml.sh` file format changes slightly:
double-quoted values (`V="x"`) become single-quoted (`V='x'`) or
`printf %q`-escaped, which are all functionally equivalent when sourced.

### v6.0 - Claude Code Launch Recipe (2026-04-23)

- **Related PR:** [#125](https://github.com/fini-net/template-repo/pull/125)
- Fixes issue [#112](https://github.com/fini-net/template-repo/issues/112)

**Add `claude` recipe** - New recipe in `.just/claude.just` that launches Claude Code from the repo root.
Just recipes run from the repo root by default, so no `cd` is needed — running `just claude` always starts Claude Code with full project context regardless of the user's current directory

### v5.9 - PR Checks Requires Active Pull Request (2026-04-19)

- Fixes issue [#115](https://github.com/fini-net/template-repo/issues/115)
- **Fix PR:** [#122](https://github.com/fini-net/template-repo/pull/122)
- **Regression PR:** [#97](https://github.com/fini-net/template-repo/pull/97)

Added a sanity check to `pr_checks` requiring that you're on a branch with an
active pull request before attempting to watch checks or display AI reviews.
Previously, running `pr_checks` outside of PR context would fail with cryptic
errors from `gh` commands that expect a PR association. Now it fails early with
a clear message, consistent with other recipes like `pr_update` and `pr_verify`
that already had this guard.

- **Dependency change** - `pr_checks` now depends on `_on_a_pull_request` instead
  of running unconditionally
- **Consistent behavior** - Matches the pattern used by other PR-dependent recipes

This was a regression that slipped in during v5.7. The history of the
`_on_a_pull_request` guard on `pr_checks`:

- **v4.0–v4.4** — `pr_checks: _on_a_pull_request` (direct dependency, added in
  [#44](https://github.com/fini-net/template-repo/pull/44))
- **v4.5–v5.2** — `pr_checks: _wait_for_checks && claude_review` — the guard was
  inherited transitively through `_wait_for_checks: _on_a_pull_request`
- **v5.7** — [#97](https://github.com/fini-net/template-repo/pull/97) changed
  to `pr_checks: && claude_review` — `_wait_for_checks` was moved from a
  dependency to an inline fallback (the `gh observer` feature), which
  accidentally dropped the `_on_a_pull_request` guard that came transitively
  through it.
- **v5.9** — Restored `_on_a_pull_request` directly

## March 2026 - More resilience

### v5.8.1 - Executable permissions for template updates (2026-03-22)

- **Related PR:** [#110](https://github.com/fini-net/template-repo/pull/110)

Fixed an issue where downloaded shell scripts from template-repo would not have
executable permissions set. Previously, files like `.just/lib/template_update.sh`
and others would be downloaded but not marked as executable, requiring manual
`chmod +x` after running `update_from_template`.

**New behavior:**

- **Automatic chmod +x** - All downloaded `.just/lib/*.sh` files are now made
  executable automatically after successful download
- **Exception for common.sh** - The `common.sh` file is intentionally excluded
  from chmod since it's only sourced, never executed directly

This makes the `update_from_template` workflow fully self-contained - after
running it, all scripts are immediately usable without additional steps.

### v5.8 - CRLF-Resilient PR Body Updates (2026-03-21)

- **Related PR:** [#107](https://github.com/fini-net/template-repo/pull/107)

Fixed a bug where `pr_update` would silently fail or produce corrupted output
when the PR body contained Windows-style CRLF line endings. GitHub's API
occasionally returns PR bodies with `\r\n` line endings (especially on PRs
created or edited via certain clients), and the state machine parser in
`update_pr_body.sh` wasn't stripping the carriage returns before processing.

**Fix:**

- **CRLF normalization** - Added `line="${line%$'\r'}"` to strip trailing
  carriage returns at the top of the parse loop in `.just/lib/update_pr_body.sh`,
  before any pattern matching occurs. One line fix, but it prevents the HTML
  marker detection from missing `<!-- PR_BODY_DONE_START -->` when the line
  ends with `\r`.

**New test coverage:**

- **Test fixture 14** - Added `14_crlf_body` fixture with a `.gitattributes`
  override to preserve CRLF line endings in `input.md`. This ensures the
  test actually exercises the CRLF path rather than having git normalize the
  line endings away on checkout.

**Related fix:** This was originally surfaced while investigating issues with
`template_update.sh` ([PR #103](https://github.com/fini-net/template-repo/pull/103)),
where debugging the update script revealed that CRLF bodies from GitHub's API
could silently break `pr_update` in ways that were hard to diagnose.

The fix is minimal and surgical - one line added to `update_pr_body.sh` with
a new test fixture to cover the scenario. No behavior changes for PRs with
normal LF line endings.

## February 2026 - Learn from experience

### v5.7 - Utilize gh observer extension (2026-02-16)

- **Related PR:** [#97](https://github.com/fini-net/template-repo/pull/97)

Utilize the [gh observer extension](https://github.com/fini-net/gh-observer) if
it is installed.

## January 2026 - Avila Beach is awesome

### v5.6 - Release Version Validation (2026-01-30)

- **Related PR:** [#92](https://github.com/fini-net/template-repo/pull/92)

Added version format validation to the `release` recipe to prevent accidental releases with malformed version numbers. Previously, you could run `just release anything` and it would attempt to create a GitHub release with whatever string you provided, potentially creating confusing or invalid release tags.

**New safety check:**

- **Version format validation** - The `release` recipe now validates that the version parameter starts with 'v' followed by a digit (e.g., v1.0.0, v2.3.4)
- **Clear error message** - Displays red error message if format is invalid: "Error: Release version must start with 'v' followed by a digit"
- **Early exit** - Fails fast with exit code 1 before attempting to create the GitHub release
- **Shellcheck compatibility** - Added disable comment for SC2050 since shellcheck doesn't understand just's templating syntax (`{{rel_version}}`)

**Implementation details:**

- Uses bash regex pattern `^v[0-9]` to match the required format
- Validation runs after the `standard-release` flag check but before the actual `gh release create` command
- Prevents common typos like `just release 1.0.0` (missing 'v') or `just release vNext` (no digit)

This change makes the release workflow safer by catching version format errors upfront rather than creating malformed tags that would need manual cleanup. Complements the existing `standard-release` flag system from v5.3.

### v5.5 - Robust Copilot Suggestion Application (2026-01-28)

- Fixes issue [#76](https://github.com/fini-net/template-repo/issues/76)
- **Related PR:** [#88](https://github.com/fini-net/template-repo/pull/88)

Enhanced the `copilot_pick` recipe with the ability to directly apply Copilot suggestions, plus comprehensive safety improvements based on Claude Code review feedback. Previously, `copilot_pick` was read-only - you could view suggestions but had to manually apply them. Now you can apply suggestions directly with proper backup and rollback capabilities.

**New feature:** Interactive suggestion application with safety nets

- **Apply suggestions** - When viewing a suggestion, choose to apply it directly to the file
- **Automatic backup** - Creates timestamped backups in `.just/copilot_backups/` before making changes
- **Multi-line support** - Properly handles both single-line and multi-line code suggestions
- **Visual preview** - Shows diff-like before/after display with line counts for multi-line changes
- **Git integration** - Offers to push applied changes back to the PR automatically
- **Confirmation workflow** - Two-stage confirmation (view → apply → push) prevents accidents

**Critical safety fixes** from Claude Code review:

- **Fixed dangerous sed command** - Now properly escapes special characters and uses `|` delimiter instead of `/` to handle paths with slashes
- **Improved code extraction** - Enhanced AWK logic handles multiple code blocks and avoids naive truncation
- **Enhanced backup system** - Stores full file paths for proper restoration, prevents path traversal issues
- **Added integrity validation** - Checks backup readability, file size, and warns about uncommitted changes before restoration
- **Better UX for multi-line changes** - Shows first line plus line count instead of truncating output

**New recipe:** `copilot_rollback`

- **Interactive restoration** - Browse available backups and restore files with confirmation
- **Path reconstruction** - Properly converts safe backup filenames back to original file paths
- **Safety checks** - Validates backup integrity and checks for uncommitted changes before overwriting
- **Git integration** - Offers to push restored files back to PR

**Implementation details:**

- Uses relative git paths for backup storage to work across different working directories
- Escapes all sed special characters (`[ ] * ^ $ ( ) + ? { } | \`) to handle complex code suggestions
- Improved error handling with consistent backup system and proper cleanup
- Enhanced diff display for both single and multi-line suggestions
- Added `.just/copilot_backups/` to `.gitignore` (prevents committing backups)

The feature makes Copilot suggestions much more actionable while maintaining the safety-first approach that's central to this workflow. You can now iterate on Copilot feedback without leaving the terminal, with robust rollback capabilities if something goes wrong.

### v5.3 - Configurable Release Workflow (2026-01-28)

- Fixes issue [#82](https://github.com/fini-net/template-repo/issues/82)
- **Related PR:** [#84](https://github.com/fini-net/template-repo/pull/84)

Added the `standard-release` flag to `.repo.toml` that allows projects to disable the default release recipes when they need custom release mechanisms. Previously, all repos inherited the standard `release` and `release_age` recipes whether they needed them or not, which could cause confusion in projects with specialized release workflows.

**New flag:** `standard-release` in `.repo.toml`

- **Default behavior** - When `standard-release = true` (or unset), provides standard `release` and `release_age` recipes
- **Custom workflows** - Set `standard-release = false` to disable standard recipes for projects with custom release processes
- **Graceful messaging** - Disabled recipes display informational messages and exit cleanly (exit 0)
- **Claude Code integration** - Updated `release_age` recipe to be more Claude-friendly with structured output and clear messaging

**Implementation details:**

- Modified `.just/gh-process.just` to check the flag before executing release logic
- Sources `.just/repo-toml.sh` for flag access (integrates with v4.6 metadata system)
- Both `release` and `release_age` recipes respect the flag
- Informational messages explain why the recipe is disabled when flag is false
- Maintains backwards compatibility - repos without the flag get standard behavior

This allows template-repo to serve both simple projects that want the standard release workflow and complex projects that need custom release automation, all while using the same template base.

### v5.2 - Template Sync System (2026-01-27)

- Fixes issue [#55](https://github.com/fini-net/template-repo/issues/55)
- **Related PR:** [#83](https://github.com/fini-net/template-repo/pull/83)

Implemented a safe update mechanism that allows derived repos to pull changes from template-repo while preserving local customizations.

**New module:** `.just/template-sync.just`

- **Multi-version checksum tracking** - `.just/CHECKSUMS.json` manifest tracks historical checksums of all `.just/*.just` files from git history
- **Safe updates** - Only modifies files whose checksums match a known template version
- **Local preservation** - Files with modifications are skipped with clear warnings
- **Diagnostic tools** - `checksums_verify` and `checksums_diff` for preview and inspection

**Four new recipes:**

1. `checksums_generate` - Generate versioned checksums from git history (template-repo only)
2. `update_from_template` - Update .just modules from template-repo (derived repos)
3. `checksums_verify` - Check local files against template versions
4. `checksums_diff <file>` - Show diff between local and latest template version

**Implementation details:**

- `.just/lib/generate_checksums.sh` - Extracts checksums from git history with version tagging
- `.just/lib/template_update.sh` - Core update logic with retry, backup, and rollback
- `.just/lib/template_sync_test.sh` - Test suite with fixtures
- Platform-compatible checksums (sha256sum on Linux, shasum on macOS)
- Network retry logic (3 attempts with exponential backoff)
- Automatic backup and restore on download failures

**Test coverage:**

- Test fixtures in `.just/test/fixtures/template_sync/`
- Scenarios: unmodified file update, modified file skip, already latest
- GitHub Actions workflow for continuous validation

### v5.1 - On-Demand Copilot Reviews (2026-01-XX)

Add `copilot_refresh` recipe to request new Copilot reviews on demand.

- **Fixes issue:** [#77](https://github.com/fini-net/template-repo/issues/77)
- **Related PR:** [#79](https://github.com/fini-net/template-repo/pull/79)

- **copilot_refresh recipe** - Request a fresh Copilot review on current PR
  - Uses GitHub REST API to add copilot-pull-request-reviewer[bot] as reviewer
  - Waits for review completion with animated spinner (via gum) or dots fallback
  - Displays suggestion count and points to copilot_pick for interactive browsing
  - Smart error handling for common failure scenarios

Implementation details:

- Polls every 3 seconds for up to 45 seconds for review completion
- Uses same GraphQL query as copilot_pick to detect completed reviews
- Does not check copilot-review flag (user-initiated action)
- Complements existing copilot_pick
  ([#67](https://github.com/fini-net/template-repo/issues/67),
  [#72](https://github.com/fini-net/template-repo/pull/72)) workflow

### v5.0 - Robust PR Body Updates with HTML Markers

- **Related PR:** [#78](https://github.com/fini-net/template-repo/pull/78)

Completely rewrote the `pr_update` recipe to eliminate data loss when updating
PR descriptions. The previous AWK-based implementation (v4.0-4.4) was fragile
and could corrupt or lose manual edits to PR descriptions, especially when
custom sections existed between Done and Meta, or when code blocks contained
`## Done` markers.

**Fixes issue:** [#57](https://github.com/fini-net/template-repo/issues/57)

The new implementation uses HTML comment markers for reliable section boundaries
and includes comprehensive test coverage:

- **HTML comment markers** - New PRs now include invisible `<!-- PR_BODY_DONE_START -->`
  and `<!-- PR_BODY_DONE_END -->` markers that provide precise boundaries for
  the Done section, eliminating ambiguity from section header detection.

- **Standalone library script** - Extracted PR body manipulation into
  `.just/lib/update_pr_body.sh` - a standalone, testable bash script with
  state machine parsing, code block tracking to avoid false positives on
  `## Done` inside code examples, and backwards compatibility with old PRs.

- **Comprehensive test suite** - Added 13 test cases in `.just/test/fixtures/pr_bodies/`
  covering basic scenarios (Done + Meta, custom sections, multiple sections),
  edge cases (code blocks, nested markdown, missing sections, empty body), and
  data preservation (checkboxes, tables, HTML comments, verify sections).

- **Test infrastructure** - New `.just/lib/pr_body_test.sh` test runner and
  `just pr_body_test` recipe for running tests. Automated in CI via new
  `.github/workflows/pr-body-tests.yml` workflow.

- **Backwards compatibility** - Old PRs without HTML markers continue to work
  using section header detection as fallback. When updated, they automatically
  receive the new markers for future reliability.

- **State machine parser** - Uses BEFORE_DONE → IN_DONE → AFTER_DONE state
  transitions with proper code block tracking, ensuring `## Done` inside
  triple-backtick blocks doesn't confuse the parser.

- **Smart section insertion** - When no Done section exists, intelligently
  inserts it after introductory content but before the first section header,
  maintaining proper PR structure.

Implementation details:

- Modified `pr` recipe to insert HTML markers when creating new PRs
- Replaced complex 48-line AWK logic in `pr_update` with 10-line call to
  library script
- All scripts pass shellcheck validation
- Tests run automatically on relevant file changes via GitHub Actions
- Created new `.just/testing.just` module for test recipes

This is a breaking change internally (complete rewrite of PR body update logic)
but maintains the same external interface. The change makes the workflow
significantly more robust - custom sections, verification timestamps, task
lists, tables, and other manual edits are now reliably preserved across
updates.

### v4.9 - Copilot Suggestion Count

- **Fixes issue:** [#73](https://github.com/fini-net/template-repo/issues/73)
- **Related PR:** [#74](https://github.com/fini-net/template-repo/pull/74)

Enhanced the Copilot review display to show a count of suggestions instead of
raw JSON output, making it easier to quickly assess how many items need attention.
Previously, after PR checks completed, you'd see the full JSON dump of all Copilot
suggestions, which was hard to scan at a glance. Now you get a clear summary of
how many suggestions there are, and the count appears both immediately after checks
and at the end of Claude's review output.

- **Count display** - Shows "Total Copilot suggestions: N" after PR checks complete,
  or "No Copilot suggestions - looks good!" when clean. Replaces the immediate
  JSON dump with human-friendly feedback.

- **Summary in claude_review** - Displays the same count summary at the end of the
  `claude_review` recipe output, providing a quick reference after you've read
  Claude's feedback. Makes it easy to remember if there are Copilot items to
  address without scrolling back through terminal history.

- **Safer temp file naming** - Uses PR metadata (owner, repo name, PR number) to
  generate unique temp filenames at `/tmp/copilot_count_${OWNER}_${REPO}_${PR}`.
  Prevents collisions when working with multiple PRs across different repositories.
  File is automatically cleaned up after display.

- **Maintained behavior** - Still outputs the full JSON for those who want to parse
  it programmatically or review detailed suggestions. The count is additive, not a
  replacement.

The change makes the workflow feel more polished - you get immediate actionable
feedback ("3 suggestions to review") rather than having to eyeball JSON arrays.
Pairs nicely with the `copilot_pick` recipe from v4.8 for diving into specific
suggestions when needed.

### v4.8 - Copilot Suggestion Picker

- **Fixes issue:** [#67](https://github.com/fini-net/template-repo/issues/67)
- **Related PR:** [#72](https://github.com/fini-net/template-repo/pull/72)

Added an interactive picker for browsing and viewing GitHub Copilot PR review
suggestions without leaving the terminal. Previously, you could see a JSON dump
of all Copilot suggestions after PR checks completed, but navigating through
multiple suggestions was cumbersome. The new `copilot_pick` recipe provides a
streamlined interface for exploring Copilot feedback.

- **`copilot_pick`** - Interactive recipe using `gum` to display Copilot
  suggestions in a browsable list. Shows `file:line - preview` format for
  quick scanning, then displays the full suggestion body when selected.
  Requires the `gum` tool for interactive selection.

- **Prerequisite checks** - Validates that both `gum` (for interactive UI)
  and `jq` (for JSON parsing) are installed before proceeding, with helpful
  installation instructions if missing.

- **GraphQL integration** - Fetches Copilot review comments using GitHub's
  GraphQL API with proper limits documented (last 20 reviews, first 100
  comments per review). Sufficient for most PRs but noted in case of very
  active discussions.

- **Robust error handling** - Validates line number extraction with regex
  check to prevent cryptic jq errors. Shows clear error messages if selection
  format is unexpected or if no suggestions are found.

- **Cleanup handling** - Properly manages temporary files with a single trap
  that cleans up both temp files on exit. Fixed an initial bug where dual
  traps would overwrite each other, potentially leaving temp files behind if
  errors occurred early in execution.

The recipe fills the gap between the automated post-checks JSON dump and
opening the PR in a browser - perfect for quickly reviewing specific Copilot
suggestions while staying in your terminal workflow. Exit gracefully with
Ctrl+C if you don't want to view any suggestions.

### v4.6 - Conditional AI Review Display

- **Fixes issue:** [#63](https://github.com/fini-net/template-repo/issues/63)
- **Related PR:** [#64](https://github.com/fini-net/template-repo/pull/64)

Added repository metadata extraction system that enables flag-based conditional
display of AI code reviews. Previously, Copilot and Claude reviews were always
displayed after PR checks completed, regardless of whether they were enabled or
relevant for the project. Now you can control this behavior via `.repo.toml`
flags.

The new `.just/repo-toml.just` module generates a sourceable shell script
(`.just/repo-toml.sh`) containing all repository metadata as shell variables.
This eliminates repeated parsing of `.repo.toml` throughout the codebase and
provides a single source of truth for configuration data.

- **`repo_toml_generate`** - Exports `.repo.toml` to shell variables with automatic
  derivation of org/repo names from URLs, conversion of TOML arrays to both bash
  arrays and CSV strings, and feature flags as strings ("true"/"false")
- **`repo_toml_check`** - Validates generated file exists and checks staleness
  (warns if `.repo.toml` modified since last generation)
- **Conditional reviews** - Modified `pr_checks` and `claude_review` recipes to
  source the generated metadata and only display reviews when corresponding flags
  (`copilot-review`, `claude-review`) are enabled in `.repo.toml`
- **Graceful degradation** - If generated file is missing, warns user and defaults
  flags to false rather than failing hard

The generated file is gitignored since it's environment-specific and regenerated
on demand. This architecture enables future recipes to access repository metadata
without parsing overhead, and provides a clean pattern for flag-based feature
toggles across the workflow.

### v4.7 - Stale Review Detection

- **Fixes issue:** [#69](https://github.com/fini-net/template-repo/issues/69)
- **Related PR:** [#70](https://github.com/fini-net/template-repo/pull/70)

Enhanced the `claude_review` recipe to detect and warn when Claude's PR review
feedback doesn't apply to the latest code. Previously, the recipe would blindly
display Claude's most recent comment even if you'd pushed new commits since the
review was written, leading to confusion about whether the feedback was still
relevant.

Now the recipe compares timestamps between Claude's latest comment and your most
recent commit to provide context-aware status:

- **Missing review** - Shows informational message with latest commit SHA and
  suggests re-running `just claude_review` or checking browser for workflow
  status. Helpful when the review workflow is still running.

- **Stale review** - Displays yellow warning with both timestamps (review
  created vs. latest commit), age difference in minutes, and clear disclaimer
  that feedback may not apply to latest code. Still shows the comment content
  but prepends "⚠️ Claude Code Review exists but is STALE" header.

- **Current review** - Normal display with "(current)" indicator confirming the
  feedback applies to your latest code.

Implementation details:

- **Cross-platform date handling** - Works on both Linux (GNU date) and macOS
  (BSD date) with proper fallbacks
- **Graceful degradation** - If date parsing fails, shows warning but continues
  to display comment
- **Always exits 0** - Won't break workflow chains (maintains `pr_checks &&
  claude_review` compatibility)
- **Uses timestamp comparison** - After investigating `.github/workflows/claude-code-review.yml`,
  discovered Claude uses `gh pr comment` which creates IssueComments (not
  PullRequestReviews), so commit SHA association isn't available. Timestamp
  comparison is the correct approach.

The recipe now provides better UX by setting clear expectations about whether
you're looking at fresh feedback or outdated suggestions. Particularly useful
during rapid iteration when you're pushing frequent commits and want to know if
you should wait for a new review.

### v4.5 - Smart Polling for PR Checks

- **Fixes issue:** [#60](https://github.com/fini-net/template-repo/issues/60)
- **Related PR:** [#61](https://github.com/fini-net/template-repo/pull/61)

Replaced the fixed 8-second sleep in the `pr` recipe with an intelligent polling
loop that waits for GitHub checks to actually start running. Previously, we'd
always wait 8 seconds after creating a PR before watching checks - wasting time
when GitHub responded quickly (2-3 seconds) and occasionally failing when GitHub
was slow (10+ seconds).

The new `_wait_for_checks` recipe polls the GitHub API every 2 seconds with a
30-second timeout, exiting immediately when checks appear. This provides:

- **Faster feedback** - No wasted time when GitHub responds quickly (typically 2-6s vs fixed 8s)
- **More reliable** - Handles slow API responses gracefully (up to 30 seconds)
- **Better UX** - Animated spinner via `gum spin` shows "Waiting for GitHub checks to start..."
- **Graceful degradation** - Falls back to simple progress dots when `gum` not available
- **Smart timeout** - Continues with warning message if checks never appear

The polling function is declared separately so it can be exported to `gum spin`'s
subshell context. Uses colored output (GREEN for success, YELLOW for timeout) and
the `USING_GUM` environment variable to conditionally show progress indicators
based on available tooling.

## December 2025 - Finer refinements

### v4.4 - PR Update Blank Line Preservation

- **Related PR:** [#50](https://github.com/fini-net/template-repo/pull/50)

Fixed a bug in the `pr_update` recipe where blank lines after the Done section
were being incorrectly removed. The AWK script that preserves sections after
Done had a logic error - after setting `after_done=1`, it continued to match
and skip blank lines because the condition `in_done && /^$/` remained true
even after transitioning to the "after done" state.

- Added `!after_done` guard to blank line and commit matching conditions
- Prevents eating blank lines once we've moved past the Done section
- Preserves original spacing between sections (e.g., Done and Meta)

The fix ensures that when `pr_update` regenerates the Done section with current
commits, it maintains proper markdown formatting with blank lines separating
different sections of the PR description.

### v4.3 - Release Tag Visibility

- **Related PR:** [#49](https://github.com/fini-net/template-repo/pull/49)

Enhanced the `release` recipe to automatically pull the newly created tag so it's
immediately visible in your local repository. Previously, after running
`just release v1.2.3`, the tag would exist on GitHub but wouldn't show up in
`git tag` locally until you manually ran `git pull`. Now the workflow handles
this for you.

- Added `git pull` command after `gh release create`
- Included 1-second sleep to allow GitHub API to finish processing
- Makes the release workflow feel more complete and immediate

This is a small quality-of-life improvement that removes a tiny paper cut from
the release process. When you create a release, you should see it locally right
away without extra steps.

### v4.2 - Prerequisites Installation Script

- **Related PR:** [#48](https://github.com/fini-net/template-repo/pull/48)

Added a standalone shell script to automate installation and verification of all
prerequisites needed to run the just recipes in this repository:

- **`install-prerequisites.sh`** - Intelligent installation helper that checks
  for all required tools (just, gh, shellcheck, markdownlint-cli2, jq) and
  either auto-installs them (macOS with Homebrew) or provides the appropriate
  installation commands (Linux with apt-get, dnf, or pacman). Shows what's
  already installed vs. what's missing with clear colored output. Includes
  proper error handling for missing package managers and Node.js/npm for
  markdownlint-cli2. Makes onboarding new contributors or setting up new
  development environments significantly smoother.

The script is fully executable, passes shellcheck validation, and provides a
friendly user experience with color-coded output and helpful error messages.
Run `./.just/lib/install-prerequisites.sh` to check your environment or install
missing tools.

### v4.1 - Release Monitoring and Iteration Workflow

- **Related PR:** [#46](https://github.com/fini-net/template-repo/pull/46)

Added three new recipes to improve release management and iterative PR workflows:

- **`release_age`** - Checks how long ago the last release was published and
  provides actionable feedback. Displays the release tag, publication date, age
  in days, and commit count since release. Warns (in yellow) if the release is
  more than 60 days old, suggesting it might be time for a new release. Works
  cross-platform with both GNU date (Linux) and BSD date (macOS). Uses `gh`
  API for robust JSON parsing of release data.

- **`claude_review`** - Broke out Claude Code review comment display into its
  own standalone recipe. Previously only callable via `pr_checks`, it can now
  be run independently to quickly see Claude's latest PR comment without
  re-running all the checks. Still chains automatically from `pr_checks` for
  the full workflow.

- **`again`** - Convenience recipe for iterative PR development. Chains
  together the common workflow of pushing new commits, updating the PR
  description with current commits, and re-watching the PR checks. Saves
  typing when you're in the flow of making changes, getting feedback, and
  iterating. Includes a 2-second sleep between PR update and check watching
  to give GitHub's API time to catch up.

These recipes improve different phases of the development cycle - `release_age`
for project maintenance awareness, `claude_review` for quick feedback access,
and `again` for rapid PR iteration.

## November 2025 - The Polish Updates

### v4.0 - PR Description Management

- **Related PR:** [#44](https://github.com/fini-net/template-repo/pull/44)

Added two new recipes for managing pull request descriptions dynamically:

- **`pr_update`** - Updates the "Done" section of the PR description with the
  current list of commits from the branch. Extracts commits using `git cherry`,
  preserves other sections (Meta, Verify, etc.), and updates the PR body via
  `gh pr edit`. Useful when you add commits after PR creation and want to keep
  the description in sync.

- **`pr_verify`** - Adds or appends content to a "Verify" section in the PR
  description. Reads from stdin, timestamps each entry, and formats as a code
  block. If no Verify section exists, creates one before the Meta section. If
  one exists, appends new timestamped entries. Perfect for logging test results
  or verification steps.

Both recipes include a new sanity check (`_on_a_pull_request`) that verifies
you're on a branch with an active pull request before attempting updates. This
prevents cryptic errors when running these commands outside of PR context.

Other improvements in this release:

- Simplified bash strict mode settings (removed `-x` tracing flag)
- Standardized PR existence checks across recipes
- Better error handling with exit code 103 for missing PRs
- Initialize awk variables properly to avoid undefined behavior
- Updated documentation to show new recipes

### v3.9 - Shellcheck Error Fixes

- **Related PR:** [#40](https://github.com/fini-net/template-repo/pull/40)

Before adding the shellcheck tooling in v3.8bis, we knew there were a bunch of
shellcheck warnings in the gh-process module itself. This release fixes all
of those issues - better variable quoting, improved conditional syntax, and
other shellcheck best practices. Nothing user-facing changed, but the code is
now cleaner and more robust. This should also mean that our future AI code
reviews will have less trivial stuff to complain about.

### v3.8bis - Shellcheck Integration

- **Related PRs:** [#37](https://github.com/fini-net/template-repo/pull/37),
  [#39](https://github.com/fini-net/template-repo/pull/39)

Added a whole new module for linting bash scripts embedded in just recipes.
The `shellcheck` recipe extracts bash scripts from all justfiles in the repo,
writes them to temporary files, and runs shellcheck on each one. It's pretty
meta - using just to check just recipes.

- New `.just/shellcheck.just` module with 138 lines of awk magic
- Automatically finds recipes with bash shebangs
- Detailed reporting showing which file and recipe each issue is in
- Purple section headings because why not
- Returns proper exit codes for CI integration

This immediately found issues in our own code, which led to v3.9.

### v3.8 - Git Alias Expansion

- **Related PR:** [#35](https://github.com/fini-net/template-repo/pull/35)

Expanded all git aliases to use standard git commands, making this justfile
work for everyone without requiring custom git configuration. Previously,
you needed my personal git aliases (`stp`, `pushup`, `co`) configured to use
this workflow. Now it just works out of the box.

- `git stp` → `git status --porcelain`
- `git pushup` → `git push -u origin HEAD`
- `git co` → `git checkout`

Added inline comments showing the old alias names for reference, so if you're
used to seeing `stp` in the output, you know what's happening.

### v3.7 - Pre-PR Hook Support

- **Related PRs:** [#32](https://github.com/fini-net/template-repo/pull/32),
  [#33](https://github.com/fini-net/template-repo/pull/33)

Added support for optional pre-PR hooks to allow project-specific automation
before creating pull requests. The `pr` recipe now checks for
`.just/pr-hook.just` and runs it if present. This is particularly useful for
projects that need to rebuild assets (like Hugo sites) before pushing.

- Added conditional hook execution in PR workflow
- Hidden `_pr-hook` recipe (internal use)
- Updated documentation with workflow versioning

### v3.6 - Quote Consistency

- **Related PR:** [#31](https://github.com/fini-net/template-repo/pull/31)

Improved shell script robustness with more consistent quoting of variables and
just template parameters. Small change, but makes the scripts more reliable
when dealing with branch names or paths that might contain spaces.

### v3.5 - Spacing and Multi-Commit Handling

- **Related PR:** [#30](https://github.com/fini-net/template-repo/pull/30)

Cleaned up the codebase and improved handling of branches with multiple commits:

- Better formatting and spacing throughout
- Cleaned up vestigial variables from earlier iterations
- Improved quoting of just variables
- More consistent handling of multiple commits on a branch

## October 2025 - The AI Review Update

### v3.4 - Graceful Failure Handling

- **Related PR:** [#26](https://github.com/fini-net/template-repo/pull/26)

Fixed an issue where broken GitHub Actions would prevent the review comments
from being displayed. The workflow now continues to show AI reviews even if
some checks fail, because you probably want to see those reviews even more when
things are broken.

### v3.3 - Copilot and Claude Review Integration

- **Related PR:** [#25](https://github.com/fini-net/template-repo/pull/25)

This was a big one. After PR checks complete, the workflow now automatically
fetches and displays comments from both GitHub Copilot and Claude Code reviews
right in your terminal. No more switching to the browser to see what the bots
think.

- Added GraphQL query to fetch Copilot PR review comments
- Displays Copilot suggestions after PR checks complete
- Shows Claude's most recent comment
- Uses `jq` to parse and filter review data

## August 2025 - The Safety Update

### v3.2 - Commit Verification

- **Related PR:** [#21](https://github.com/fini-net/template-repo/pull/21)

Added a sanity check to prevent accidentally creating empty PRs. The `pr` recipe now verifies that your branch actually has commits before allowing you to create a pull request. Uses `git cherry` to compare against the release branch.

- New `_has_commits` dependency check
- Clear error message when branch is empty
- Exit code 101 for tracking

### Faster PR Check Monitoring

- **Related PR:** [#20](https://github.com/fini-net/template-repo/pull/20)

Changed the PR checks watcher to poll every 5 seconds instead of the default. Because who wants to wait around? GitHub's API might be lazy, but we don't have to be.

## June 2025 - The Beginning of this file

### v3.1 - Initial Release

- **Related PR:** [#11](https://github.com/fini-net/template-repo/pull/11)

Created as part of a larger refactoring effort to modularize the main justfile.
This file extracted all the Git/GitHub workflow automation into a separate
module.

Core recipes included from day one:

- `sync` - Return to main and pull latest
- `pr` - Create PR from current branch
- `merge` - Squash merge and clean up
- `branch` - Create dated feature branches
- `prweb` - Open PR in browser
- `release` - Create GitHub releases
- `pr_checks` - Watch PR checks (later enhanced)

Plus a bunch of sanity check helpers (`_on_a_branch`, `_main_branch`, etc.) to
keep you from footgunning yourself.

---

## Pre-history

Earlier versions of this code came from the `/justfile` in
[this repo](https://github.com/fini-net/template-repo/blob/main/justfile)
and some of my other repos, primarily
[www-chicks-net](https://github.com/chicks-net/www-chicks-net/blob/main/justfile).
It all started [very simply](https://github.com/chicks-net/www-chicks-net/commit/06f28b13d82e445951b10af1a57488a1dc9e1069).

I think there were some 2.x versions, but I haven't rediscovered them.
