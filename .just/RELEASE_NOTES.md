# Release Notes: gh-process.just

This file tracks the evolution of the Git/GitHub workflow automation module.

## November 2026

### v11.2 - shellcheck clean across .just/lib: glob dedupe match, mktemp exit propagation, fixture-pin drift guard (2026-11-04)

A plain `shellcheck .just/lib/*.sh` sweep now exits 0. Twelve of
the fifteen lib scripts were already clean; the sweep's value was
proving it, fixing the two real warnings it found, and converting
seventeen intentional infos into something the linter can read.

**The dedupe check reads as what it is.** generate_checksums.sh asked
`[[ " $seen_checksums " =~ " $checksum " ]]` - a quoted right-hand
side in a regex match, the exact idiom SC2076 exists to flag:
quoting makes the pattern match literally while most readers expect
regex semantics. The behavior was correct all along (quoted portions
of a `=~` pattern match literally, which was the intent, and sha256
hex has no metacharacters either way) - the idiom was the footgun.
It is now the glob form shellcheck recommends for literal matching -
`== *" $checksum "*` - same padded word-membership semantics, no
double reading required.

**template_update.sh no longer swallows a failed mktemp.** `readonly
MANIFEST_FILE=$(mktemp)` is SC2155's poster child: the declaration
masks the command substitution's status, so under `set -euo
pipefail` a failed mktemp sails through with an empty manifest path.
The assignment now precedes the readonly mark - failure propagates,
readonly semantics survive.

**The fixture pin moved in lockstep, and now guards itself.**
run_update_test patches template_update.sh by string-matching that
exact line with sed to point fixtures at the workspace manifest -
the same genre of drift contract as CLEANED_FILES, with the same
failure mode: edit one side and the sed silently matches nothing,
so four fixtures fetch into a real mktemp path and fail far away in
verify_expected_state. The pin now targets the bare assignment line
(the readonly that follows still applies in the fixture), and a
drift guard after the sed grep-verifies the rewrite and fails
pointedly - "fixture pin failed: update both together" - instead of
obliquely. The guard fired for real before shipping: breaking the
pattern on purpose failed all four update-script fixtures with the
message; restoring it went back to 32 green.

**SC2016 is the point here, and now the linter knows it.** The
seventeen remaining infos were deliberate: semver_selftest's echo
lines emit literal bash into a generated driver (the file already
said so in prose - "SC2016 is the point here"), and the pin's sed
keeps `\$(mktemp)` literal for the pattern match. Two function-scoped
`# shellcheck disable=SC2016` directives with why-comments turn that
prose into something the tool reads - the convention compliance.just
and copilot.just already use for the same code.

### v11.1 - homebrew-chicks #120 review follow-ups: single-quoted shellcheck trap, || true intent (2026-11-04)

- **Review:** [homebrew-chicks
  #120](https://github.com/chicks-net/homebrew-chicks/pull/120) - the
  v11.0 sync into the Homebrew tap

**The last double-quoted trap is gone.** The Claude review of the v11.0
sync asked for the cleanup trap in the `shellcheck` recipe to defer
expansion - `trap "rm -rf $CHECKS_TMPDIR" EXIT` captured the temp path
the moment the trap was set, safe only because `mktemp` paths never
contain spaces. It is now the single-quoted idiom the rest of the
suite already uses, expanding at trap-fire time with the variable
quoted, and the `# shellcheck disable=SC2064` that papered over the
old form is gone with it. The review pointed at cue-verify.just; the
trap actually lives in shellcheck.just - the sync carries all of
.just/, so the fix ships from here either way.

The compliance `|| true` on the `file_types` pipeline got a comment
stating what it is for: shielding `set -euo pipefail` from `file`
erroring on individual entries. The missing-binary case the review
worried about never reaches that line - the `command -v file` guard
has wrapped the whole block since v10.3, and compliance_test.sh fails
CI when `file` is absent so the check cannot pass vacuously.

**The version bump now lives where CLAUDE.md says it lives.** A
first cut of this change stamped v11.1 onto the file's title comment
instead of the documented bump spot - the `# PR create vX.Y` header
above the pr recipe - and that header had itself drifted to v10.9,
stale through v10.10 and v11.0, the same rot these notes previously
recorded at v5.4 and v6.10 (Claude review of #442). The duplicate
token is gone, the header reads v11.1, and checksums_generate now
refuses to mint a manifest while that header disagrees with the
newest RELEASE_NOTES.md entry - the guard's red paths are pinned by
the guard_selftest sandboxes, so the drift cannot quietly return.
The cleanup trap also gained the regression coverage the review
asked for: repo_toml_stub_test drives the real shellcheck recipe
with a TMPDIR containing a space and requires the temp tree not to
survive the run - the exact case the old double-quoted form
mishandled by word-splitting the path at trap-set time.

### v11.0 - release version-order confirmation (#436) (2026-11-02)

- Fixes issue [#436](https://github.com/fini-net/template-repo/issues/436)
- **Related PR:** [#439](https://github.com/fini-net/template-repo/pull/439)

**`just release` now asks before going backwards.** The recipe validated
version *format* but never *order*: GitHub's Latest badge follows the
newest *created* release rather than the highest version, so tagging
`v1.0.0` after `v1.2.0` quietly made the regression the thing users
see. The recipe now fetches the latest release, compares semver
precedence, and confirms via gum before creating anything that does
not strictly advance - backwards *or* semver-equal (a `+build`
re-tag). Declining is a clean cancel (exit 0, the copilot_rollback
convention): backport tags are legitimate, the check exists to catch
one-shot accidents like `v1.0.0` typed for `v1.3.0`. The major bump to
v11.0 (not v10.10) is deliberate - a release workflow that used to run
unattended now stops and asks.

The comparison is bash-native semver, not `sort -V`, which orders
`1.0.0-rc1` *after* `1.0.0` - the exact inversion this check exists
to catch. Short forms zero-pad, build metadata is ignored, and a
stable release legitimately follows its own rc. A table-driven
`semver_selftest` extracts the comparator live from the recipe, so
drift fails the suite. Edge cases - no releases yet, an unparseable
latest tag (legacy schemes in derived repos), a gh/network hiccup -
skip the check with a warning instead of blocking, and the baseline
is the latest-marked release, so a confirmed backport becomes the new
baseline instead of nagging forever. Review rounds tightened the
parse edges (degenerate grammar-legal tags like `v1.0.0-rc..1` or
`1..2` reject at parse time) and retired arithmetic numeric compare
entirely - `10#$n` wrapped past 2^63 on calendar-sized fields - in
favor of length-then-lexical comparison. Seven new fixtures (22-28)
cover confirm, decline, the `sort -V` inversion, re-tag, and the skip
paths. A non-interactive escape for automated backports is a known
follow-up.

### v10.9 - cleaned_files drift guard + not-locally-verifiable note (2026-11-02)

- Fixes issue [#381](https://github.com/fini-net/template-repo/issues/381)
- **Related PR:** [#438](https://github.com/fini-net/template-repo/pull/438)

**`CLEANED_FILES` now enforces its own sync.** The hand-maintained list
in `generate_checksums.sh` had to match the `rm` lines of
`_remove_template_files` with nothing catching drift - and two v9.9
sync reviews flagged exactly that confusion, since the list names
files that do not exist in derived repos. `checksums_generate` now
extracts the quoted-literal `rm` paths from `clean-template.just`
(minus the two named scratch `.tmp` files) and fails with a per-path
report unless they equal `CLEANED_FILES`, so drift is caught the
moment it is introduced. The sweep found one real divergence on
arrival: `docs/template-repo-banner.png` was removed by the recipe but
unlisted. `template-sync.yml` now also triggers on
`clean-template.just` edits, so the guard runs in template-repo CI.

Derived repos get a note, not a failure: the guard warns and skips
when `clean_template` has already removed the recipe, and the header
comment states the list runs only in template-repo. Diagnostics go to
stderr (stdout is the JSON manifest). A `guard_selftest` drives the
real script across eight scenarios - both drift directions,
comment-poisoning, zero-extraction, missing recipe, `"$VAR"` literals,
scratch exclusion - each red-checked by breaking the real guard three
ways.

### v10.8 - release accepts semver pre-release/build tags (2026-11-02)

- Fixes issue [#379](https://github.com/fini-net/template-repo/issues/379)
- **Related PR:** [#437](https://github.com/fini-net/template-repo/pull/437)

**`just release` accepts `v1.0.0-rc1` and `v1.0.0+build.5` again.**
The v9.7 quote-injection hardening (#359) had tightened the version
regex to reject semver pre-release and build-metadata tags - a
deliberate rejection, but documented only in these notes, so two v9.9
sync reviews
([fini-domains#62](https://github.com/fini-net/fini-domains/pull/62#issuecomment-5717899954),
[fini-projects#34](https://github.com/fini-net/fini-projects/pull/34#issuecomment-5670582615))
could not tell design from breakage. The regex now takes optional
`-prerelease` and `+build` suffixes, each independently optional.
The guard from #359 is unchanged in strength: the suffix classes
admit no shell metacharacters and both anchors stay, so the original
`v1"; touch /tmp/pwned #` payload still fails validation. This is a
grammar guard, not a semver validator - degenerate but
metacharacter-free suffixes pass, and the recipe comment owns that.

Accepting at the template level beats documenting the rejection: a
locally loosened line in a derived repo would show up as drift in
`checksums_verify` - the template advising an edit its own drift
detector flags. Review rounds folded in the real gap they found: a
pre-release published as a *normal* release would wear the GitHub
Latest crown, so detection strips the `+build` suffix first, then
tests for a hyphen - `v1.0.0-rc1` publishes with `--prerelease`,
`v1.0.0+build.5` publishes normally, and hyphenated build metadata
(`+build-5`) does not trip it. Fixtures 17-21 pin the acceptances, the
injection rejection, and the flag behavior. Monotonic ordering stayed
out of scope - its design choices are a separate conversation, tracked
in [#436](https://github.com/fini-net/template-repo/issues/436).

### v10.7 - copilot_rollback dotglob reset + security-boundary test coverage (2026-11-02)

- Fixes issues [#378](https://github.com/fini-net/template-repo/issues/378)
  and [#382](https://github.com/fini-net/template-repo/issues/382)
- **Related PR:** [#434](https://github.com/fini-net/template-repo/pull/434)

**`copilot_rollback` now restores default globbing** - the recipe
enabled `shopt -s dotglob` for the `*.bak` listing (#332) but never
reset it, a trap for any glob added later in the same recipe body
(#378). A matching `shopt -u dotglob` runs after the listing loop.

**The sync system's security boundary has direct assertions** (#382).
Two v9.9 sync reviews noted that `validate_filepath` /
`sanitize_for_display` and the backup-name parse shipped with no
tests for their rejection classes. A `security_boundary_selftest` now
asserts every documented rejection against the real sourced
`common.sh` - non-`.just/` prefixes, absolute paths, `..` segments,
quotes, backslashes, control characters - plus the deliberate accepts
and control-byte stripping. A new `stdin` fixture key gives recipe
fixtures deterministic input so no run can hang on a TTY, and three
new recipe fixtures drive `copilot_rollback` end to end: a
dot-prefixed restore (doubling as the dotglob regression test),
timestamp-split parse edges, and the legacy `_`-for-`/` fallback.
Fixture backup names diverge at alphanumeric characters so the
in-order matcher stays stable across C and en_US.UTF-8 collation.
`template-sync.yml` now also triggers on `.just/copilot.just` and
`.just/lib/common.sh`, neither of which ran sync CI before.

### v10.6 - template_sync_test: mismatch dump + DRY matcher/state helpers (2026-11-02)

- Fixes issues [#376](https://github.com/fini-net/template-repo/issues/376)
  and [#377](https://github.com/fini-net/template-repo/issues/377)
- **Related PR:** [#433](https://github.com/fini-net/template-repo/pull/433)

**A red fixture now answers "what did it actually print."** Mismatches
were a bare `Output mismatch` line, leaving the comparison to the
developer re-running the fixture by hand. The suite now dumps both
sides through the exact normalization the matcher uses, plus a
first-difference hint, and `State mismatch` names the offending file
and reason. The matcher and state-check blocks - duplicated verbatim
between the two runner modes and already drifting (SC2295) - now live
in shared helpers, and a `harness_selftest` drives the diagnostics
against a deliberately wrong scratch fixture so the dump paths have
coverage. The state walk sorts before checksumming so the reported
offender does not vary between machines.

### v10.5 - compliance suite: enforced terminal-token extraction guard (2026-11-02)

- **Related PR:** [#432](https://github.com/fini-net/template-repo/pull/432)
  (follow-up to [#431](https://github.com/fini-net/template-repo/pull/431))

**The single-quote constraint is now enforced, not just documented.**
A single quote landing inside a recipe pattern would silently truncate
`compliance_test.sh`'s extraction at the quote, exercising a partial
pattern. `extract_pattern` now takes the pattern's terminal token and
fails any extraction that does not end with it, self-testing the guard
on every run against a quote-injected throwaway copy so a stale
fixture fails loudly instead of passing vacuously. Extraction
diagnostics moved to stderr, and the constraint comment no longer
writes examples with literal single quotes that a future extraction
could trip over.

### v10.4 - compliance review follow-ups: single-quote constraint, missing-tool reporting (2026-11-02)

- **Related PR:** [#431](https://github.com/fini-net/template-repo/pull/431)
  (follow-up to [#430](https://github.com/fini-net/template-repo/pull/430))

Follow-ups from the review of #430's final head: the classification
comment block documents the single-quote extraction constraint and
the large-blob awk's blind spot for a file literally named `total`;
the missing-tool gate reports every missing tool instead of only the
last one checked; and the v10.3 release-notes description of
`MS Windows icon resource` was corrected to match shipped behavior
(favicon-style files are media, not red executables).

### v10.3 - compliance: binary-artifact split, portable grep, SUPPORT.md (2026-11-02)

- Fixes issues
  [#373](https://github.com/fini-net/template-repo/issues/373),
  [#380](https://github.com/fini-net/template-repo/issues/380), and
  [#386](https://github.com/fini-net/template-repo/issues/386)
- **Related PR:** [#430](https://github.com/fini-net/template-repo/pull/430)

**`compliance_check` no longer treats images and PDFs as contraband
(#373).** The Binary-Artifacts scan lumped media formats in with
executables, so derived repos legitimately shipping media printed red
on every run - and a permanently red check is noise that gets ignored.
Each file is now classified once: executables stay red, media becomes
a yellow advisory, blobs over 1MB get their own yellow size advisory,
and `MS Windows icon resource` counts as media so static sites stay
clean. Classification greps anchor to the `file` description with
word boundaries, so a text file *named* `ELF-notes.md` classifies by
content, not name.

**The OpenSSF heuristics no longer depend on GNU grep extensions
(#380).** `\b` boundaries silently degrade under the BSD grep macOS
ships - matches missed, no hint to the user. All three sites now use
POSIX character-class boundaries, verified on both greps.

**`compliance_check` now verifies `.github/SUPPORT.md` (#386)** - the
README links to it and the link dangled, exactly the rot a compliance
check exists to catch.

**New tests pin the behaviors that regress invisibly.**
`compliance_test.sh` extracts the live boundary and classification
patterns from `compliance.just` and exercises those, so someone
"simplifying" a boundary back to `\b` fails the suite instead of
shipping subtly wrong output. Fixtures plant a fake ELF, a JPEG, a
favicon, a 1.7MB blob, and text files *named* `ELF-notes.md` /
`PDF-spec.txt` that must classify as neither; extraction is
content-anchored so an unrelated grep cannot re-target the suite.
Runs in `cue-sync-tests.yml`, with matching `CLEANED_FILES` and
`clean_template` removals for derived repos.

### v10.2 - repo-toml stub sandboxing, repo_toml_check stub sentinel (2026-11-01)

- Fixes issue [#372](https://github.com/fini-net/template-repo/issues/372)
- **Related PR:** [#428](https://github.com/fini-net/template-repo/pull/428)

**`just shellcheck` no longer writes its fallback stub to the real
`.just/repo-toml.sh` path.** When generation failed (no `cue`/`jq` -
the #192 auto-generate fallback), the recipe wrote a hardcoded stub
to the real path - which then read as up-to-date to `repo_toml_check`'s
`-nt` test and silently fed stale defaults to every sourcing recipe
(`pr`, `again`, `pr_checks`, `claude_review`, `release`,
`release_age`). The stub now lives in the lint run's temp directory,
resolved via `--source-path` for that run only, so a failed lint can
no longer leave poison behind. A new sentinel rejects v10.1-era stubs
left at the real path: the file's first line is compared against the
stub marker before the `-nt` test, so a stale stub fails with a
"regenerate" hint instead of passing as up-to-date. Deleting the
stub is enough to heal - the sourcing recipes have their own fallback
defaults. `repo_toml_stub_test.sh` drives the real recipes in temp
workspaces, with a drift assertion on the stub's variable list and a
precedence pin that the real file wins over the sandboxed candidate.
In CI a missing `just`/`shellcheck` fails the suite rather than
skipping.

### v10.1 - asciinema .cache gitignore guard, sensitive-recording caveat, single-guard pr (2026-11-01)

- Fixes issues [#374](https://github.com/fini-net/template-repo/issues/374)
  and [#375](https://github.com/fini-net/template-repo/issues/375)
- **Related PR:** [#427](https://github.com/fini-net/template-repo/pull/427)

**The asciinema feature now guarantees `.cache/` is gitignored before
any recording starts.** The root `.gitignore` is neither
CHECKSUMS-tracked nor shipped by `update_from_template`, so a derived
repo flipping the opt-in flag on (v9.9) had nothing stopping
`git add -A` from sweeping a `.cast` file into a commit. A hidden
`_ensure_cache_ignored` recipe runs before both recording paths: it
creates `.cache/`, probes with `git check-ignore` on a path *under*
it (directory-only patterns do not match a not-yet-existing path),
and appends a root-anchored `/.cache` entry when nothing covers it -
repairing a missing trailing newline so the entry cannot glue onto
the last line. Recordings are also now labeled as what they are -
sensitive local artifacts that can capture `gh` output or tokens -
with a review-before-sharing caveat in both paths and `cue-verify`.

**`pr` no longer runs `_has_commits` twice** - since v9.9 both the
wrapper and `_pr_inner` declared it, so the `git cherry` check ran
twice per invocation. The guard fires exactly once, inside the recipe
body it protects. `asciinema_cache_test.sh` drives the real recipe
and `cue-verify` behavior end to end; the removal-list work also
caught a v10.0 straggler (`repo_urls_test.sh` listed in
`CLEANED_FILES` with no matching removal block).

### v10.0 - clean_template repoints .repo.toml URLs; cue sync refuses stale URLs (2026-10-31)

- Fixes issue [#420](https://github.com/fini-net/template-repo/issues/420)
- **Related PR:** [#426](https://github.com/fini-net/template-repo/pull/426)

**Derived repos used to ship with `.repo.toml` still describing
template-repo.** `clean_template` fixed the README but never touched
`.repo.toml`, and `cue-sync-from-github` picks its GitHub target from
`urls.web_url` - so every sync re-imported the *template's* description
and topics, and the trailing `cue-verify` passed because both sides
of the comparison pointed at template-repo. One derived repo went
three PRs before noticing.

A new `_clean_repo_toml` recipe repoints `[urls]` from the origin
remote, validates with `cue vet`, and syncs real metadata in the same
pass - inserting whichever key is missing, adding a `placeholder`
topic when the repo has none (the CUE schema requires at least one),
and warning instead of failing when a brand-new repo has no GitHub
description yet. All of `clean_template`'s recipes now run at the
repo root, so the relative paths are correct from any invocation
directory. A shared `.just/lib/repo_urls.sh` centralizes the URL
parsing, and both `cue-sync-from-github` and `cue-verify` now
cross-check `web_url` against the git origin: sync refuses any
mismatch before writing anything, verify treats a repo-name mismatch
as fatal (the stale-URL shape) and an org-only mismatch as a warning
(the normal contributor-fork clone). `_clean_readme` also learned
HTTPS remotes, which previously broke the README badges.
`repo_urls_test.sh` covers the parsing, the classifier, the repoint
transform, and the recipe behaviors end to end. Also fixed the
template's own triple-space description typo - the smoking gun that
let a derived repo notice - and the CONTRIBUTING recipe listing,
drifted since `PR create v5.4`.

## September 2026

### v9.9 - self-contained positional-argument recipes + bare-justfile test pass (2026-09-14)

- Fixes issues [#367](https://github.com/fini-net/template-repo/issues/367)
  and [#368](https://github.com/fini-net/template-repo/issues/368)
- **Related PR:** [#369](https://github.com/fini-net/template-repo/pull/369)

**The four argument-taking recipes no longer depend on root-justfile
configuration.** v9.7 moved `claude`, `branch`, `release`, and
`checksums_diff` to positional shell parameters - but positional
parameters only populate when `set positional-arguments := true` is
present somewhere in the justfile/import tree, and the root justfile
holding that setting is not CHECKSUMS-tracked. Every derived repo that
pulled v9.7 broke: `just claude <anything>` launched claude with no
arguments, `just branch my-feature` dropped the name, and `release` /
`checksums_diff` failed with `$1: unbound variable`. A second `set`
inside a shipped module is a hard redefinition error, so the fix is
the per-recipe `[positional-arguments]` attribute (just >= 1.29.0),
which ships with the module and stays inert next to the template's
own root `set`.

The harness no longer tests against a configuration real consumers
never have: it had baked the setting into every sandbox justfile,
which is exactly why the v9.7 breakage sailed through CI green. A
new `bare_justfile` fixture mode (plus `modules`/`shims` options)
mirrors a derived-repo justfile, and four bare fixtures pin the
invariant that tracked modules must be self-contained. The bare
fixtures also surfaced a latent harness bug where the expected-output
matcher aborted the whole suite on the first missing line, so no
failing fixture could ever be reported.

### v9.8 - claude_review is the single print site for the Copilot summary line (2026-09-13)

- **Related PR:** [#363](https://github.com/fini-net/template-repo/pull/363)

`pr_checks` and `claude_review` both read the same count file and
both echoed the `🐈‍⬛ No unresolved Copilot suggestions` summary line -
printed twice on every `just pr` / `just again` run. `pr_checks` no
longer echoes it; the summary prints exactly once, from
`claude_review`.

### v9.7 - injection hardening: positional args for branch/release/claude (2026-09-12)

- Fixes issues [#353](https://github.com/fini-net/template-repo/issues/353)
  and [#359](https://github.com/fini-net/template-repo/issues/359)
- **Related PR:** [#362](https://github.com/fini-net/template-repo/pull/362)

**The last `{{...}}` argument templating is gone from user-facing
recipes.** PR [#352](https://github.com/fini-net/template-repo/pull/352)
(v9.1) proved empirically that interpolating a recipe argument into
the body via `{{arg}}` is command-injectable at the templating layer.
The three remaining sites now take the positional form: `branch` runs
`git checkout -b "$USER/$NOW-$1"`, `release` reads `rel_version="$1"`
up front, and the variadic `claude *args` became a shebang recipe
running `claude "$@"` - verified end to end, with the injection
payload staying a literal string through both forms.

**The release regex is now actually load-bearing (#359).** The old
`^v[0-9]` start-anchored-only check let `v1"; touch /tmp/pwned #`
break out of the quoting in `gh release create`. The guard is now
`^v[0-9]+(\.[0-9]+){0,2}$`; the strict form deliberately rejected
prerelease suffixes (see v10.8 for how that aged).

### v9.6 - release-process hygiene: editorconfig pre-push guard (2026-09-12)

- Fixes issue [#329](https://github.com/fini-net/template-repo/issues/329)
- **Related PR:** [#361](https://github.com/fini-net/template-repo/pull/361)

**The 3-space indent regression finally has a local gate.** Numbered-list
continuation lines in this very file kept landing with a 3-space
indent, and editorconfig CI failed for it three times across two
consecutive versions - every failure caught *after* the push, which
is exactly where you want it not to be. The new `editorconfig_check`
recipe runs in `_pr-hook`, so `just pr` fails locally first
(best-effort: a missing binary warns and exits 0; CI stays the hard
enforcement), and `_again_inner` now invokes `_pr-hook` too, since
the second regression arrived through `just again`. The prerequisites
installer knows about `editorconfig-checker`, and CLAUDE.md gains the
explicit RELEASE_NOTES.md indentation rule aimed at the actual
culprit - AI agents appending list items mid-PR.

### v9.5 - test infrastructure: wait_for_copilot suite + recipe-gate coverage (2026-09-11)

- Fixes issues [#330](https://github.com/fini-net/template-repo/issues/330)
  and [#354](https://github.com/fini-net/template-repo/issues/354)
- **Related PR:** [#360](https://github.com/fini-net/template-repo/pull/360)

**The Copilot-wait state machine finally has tests.** The shared poll
loop sits on the critical path of every `just pr` run, needed two
rounds of bug fixes in v8.4 alone, and had no automated test. The new
suite runs the production script byte-for-byte with `gh`/`sleep`
shims; the mock `gh` plays fixture responses in order and applies the
real `--jq` filter with real jq. Ten fixtures cover the branch
matrix, sentinel files are asserted on stale exits, and an
`exact_output.txt` mode requires byte-for-byte output so extra dots
fail instead of passing a substring check.

**Recipe gates are now tested, not just the update script.**
`template_sync_test.sh` grew a recipe mode: `recipe` fixtures get a
sandboxed workspace with the real modules and mocked curl, running
the actual `just checksums_verify` / `checksums_diff` and asserting
exit codes, ordered output, and expected state. Five fixtures cover
the invalid-manifest-key rejection, the file states, the success
path, and traversal-argument rejection. Both runners went into the
`clean_template` removal lists in the same commit they appeared - the
v7.2 lesson - so `update_from_template` never resurrects them.

### v9.4 - misleading comment fixes (2026-09-11)

- Fixes issues [#339](https://github.com/fini-net/template-repo/issues/339)
  and [#337](https://github.com/fini-net/template-repo/issues/337)
- **Related PR:** [#357](https://github.com/fini-net/template-repo/pull/357)

The comment above `unset 'footer_content[...]'` in `update_pr_body.sh`
existed to stop recurring false-positive reviews of the single-quoted
`unset` idiom - and Copilot flagged the *comment* itself, because the
"calling shell" framing invited exactly the wrong mental model. It now
says what the code does in one accurate sentence, and Copilot custom
instructions cover the idiom too
(`.github/instructions/review-guidance.instructions.md`, using the
filename and `applyTo` keys Copilot actually requires). Note that
template sync ships only the `.just/` tree, so derived repos must
copy the instructions themselves. Also: `cue_sync.awk` and
`cue-verify.just` comments referenced a test runner that
`clean_template` strips from every derived repo - flagged twice
downstream - so both now describe the actual derived-repo caller.

### v9.3 - install-prerequisites.sh cleanup (2026-09-10)

- Fixes issues [#335](https://github.com/fini-net/template-repo/issues/335)
  and [#333](https://github.com/fini-net/template-repo/issues/333)
- **Related PR:** [#356](https://github.com/fini-net/template-repo/pull/356)

The macOS branch exits early when Homebrew is missing, which made the
nested `command -v brew` guard in the `markdownlint-cli2` case dead
code - and a failed brew install gave up with no fallback even when
npm was available. The unreachable arm is gone and the npm fallback
landed (#335). The unsupported-OS hint no longer tells non-mac users
to `brew install` down a dead end - it lists the cross-platform npm
route first (#333).

### v9.2 - check recipes fail gracefully and report accurately (2026-09-10)

- Fixes issues [#340](https://github.com/fini-net/template-repo/issues/340),
  [#328](https://github.com/fini-net/template-repo/issues/328), and
  [#334](https://github.com/fini-net/template-repo/issues/334)
- **Related PR:** [#355](https://github.com/fini-net/template-repo/pull/355)

**Graceful failure.** The repo description check in `compliance_check`
no longer runs `$(gh repo view ...)` inside `[[ ... ]]` - a failed
`gh` call either aborted the recipe under `set -euo pipefail` or
yielded an empty substitution that inverted the length test,
reporting a healthy description as a compliance problem. It now
prints a yellow "skipped" note and continues (#340). And `just
shellcheck` no longer hard-fails when `.just/repo-toml.sh` generation
fails - a linting command should not be a dependency on optional
tools. It writes a stub with the expected variable declarations
instead; the declarations matter, since an empty stub would leave
`FLAG_*` unset and crash sourcing recipes under `set -u` (#334).

**Accurate reporting.** The Token-Permissions heuristic grepped
`'^[[:space:]]*permissions:'`, which matches job-level blocks too - a
workflow with no top-level block at all was reported as
least-privilege compliant. The pattern is now anchored to
`'^permissions:'` (#328).

### v9.1 - template-sync security and correctness (2026-09-10)

- Fixes issues [#347](https://github.com/fini-net/template-repo/issues/347),
  [#348](https://github.com/fini-net/template-repo/issues/348),
  [#346](https://github.com/fini-net/template-repo/issues/346),
  [#336](https://github.com/fini-net/template-repo/issues/336), and
  [#338](https://github.com/fini-net/template-repo/issues/338)
- **Related PR:** [#352](https://github.com/fini-net/template-repo/pull/352)

**Security.** `checksums_verify`/`checksums_diff` no longer build
predictable `/tmp/<name>-$$.<ext>` paths - both use `mktemp`, closing
the classic symlink race on multi-user hosts (#348).
`update_from_template` now validates every `filepath` key from the
remote manifest before any filesystem operation: `.just/` prefix
required, `..` segments, backslashes, quotes, and control characters
rejected, so a manifest entry like `../../../.bashrc` is skipped,
counted under `Failed`, and the sync exits 1 - defense in depth,
since manifest checksums come from the same remote as the paths they
verify. Filepath keys go to jq via `--arg`, iteration is
NUL-delimited, and rejection diagnostics print through a
`sanitize_for_display` helper that strips raw control bytes - an
adversarial manifest cannot spoof output lines or inject terminal
escape sequences into the message reporting its rejection (#347).
Both verify recipes route every manifest key through the same gate,
sourcing `common.sh` instead of carrying a duplicate checksum helper.

**Correctness.** `template_sync_test` no longer hard-fails in derived
repos - its harness is stripped by `clean_template`, so it exits
early with a friendly message unless `.repo.toml` points at
template-repo (#346). The cleaned-file jq predicate carries explicit
parentheses so `|`/`or` precedence is not re-derived by every
reviewer (#336), and checksum mismatch errors print expected vs
actual (#338). Wiring the new `04_path_traversal` fixture surfaced
two dormant harness bugs: fixture paths were never absolutized, so
the output and state checks never ran at all, and the multi-line
comparison OR-split lines so any single matching line passed.

### v9.0 - asciinema recording of pr/again behind asciinema-record flag (2026-09-05)

- Fixes issue [#324](https://github.com/fini-net/template-repo/issues/324)
- **Related PR:** [#345](https://github.com/fini-net/template-repo/pull/345)

`just pr` and `just again` can capture a replayable terminal recording
of the whole flow via `asciinema rec` - **opt-in** through a new
`asciinema-record` flag in `.repo.toml` (default `false`), so default
behavior is unchanged and no `.cast` files are ever written unless
asked for. The recipe bodies moved into hidden `_pr_inner` /
`_again_inner` recipes so the wrappers can dispatch, and `pr_checks`
moved from a just post-dependency into the chained command - a
post-dependency executes *after* the recipe body, outside any
recording the body could start. Casts land in gitignored `.cache/`:
`pr` records to a pid-named temp file and renames it once
`gh pr create` returns a PR number (a failed or interrupted run keeps
the pid-named cast for debugging), while `again` knows the PR number
up front. The wrappers probe `asciinema rec --help` for `--return`
support at runtime because 2.x and 3.x disagree on exit semantics, so
`pr`/`again` always report the real child exit code. There is
deliberately no retry-on-asciinema-failure: a non-zero exit means the
flow ran or was interrupted, and blindly re-running could issue a
duplicate `gh pr create`. `.cast` files capture raw terminal I/O with
no secrets filtering - which is why default-off is the right default.

### v8.9 - fix copilot_rollback parsing for legacy backups (2026-09-05)

- Fixes issue [#332](https://github.com/fini-net/template-repo/issues/332)
- **Related PR:** [#344](https://github.com/fini-net/template-repo/pull/344)

`copilot_rollback` reconstructed backup filenames by splitting on the
first underscore - fine for URL-encoded names, but broken for every
*legacy* backup, where the old scheme encoded `/` as `_` and safe
paths are full of underscores. The legacy fallback decode branch was
unreachable by design. Names are now parsed by matching the timestamp
pattern from the end (`^(.*)_([0-9]{8}_[0-9]{6}_[0-9]+)\.bak$`) -
neither a first- nor a last-underscore split works, since the
timestamp itself contains two underscores. Testing surfaced an older
bug in the same recipe: bash globs skip dot-prefixed filenames
entirely, so backups of `.just/*` files - the primary thing this repo
backs up - never appeared in the rollback listing at all
(`shopt -s dotglob` fixes it). One inherent ambiguity remains: a
legacy backup of a file whose own name contained an underscore decodes
with `_` as `/`, because the old format simply cannot encode the
distinction.

### v8.8 - guard `set -e` bare commands and jq-derived integer comparisons (2026-09-05)

- Fixes issue [#326](https://github.com/fini-net/template-repo/issues/326)
- Fixes issue [#327](https://github.com/fini-net/template-repo/issues/327)
- **Related PR:** [#341](https://github.com/fini-net/template-repo/pull/341)

Two classes of `set -euo pipefail` fragility that kept recurring
across v8.\* PRs, fixed at every remaining call site and documented as
a convention in the `copilot.just` and `gh-process.just` headers
instead of being patched one-off each time a review trips over a new
instance. Bare commands under `set -e` (#326): unguarded `gh api
graphql` calls in `copilot_pick` and `copilot_refresh` aborted the
recipe on transient failures before the friendly fallback messaging
could print - each now has an explicit fallback - and `_wait_for_checks`
guards its `gum spin` the same way. Unguarded integers from jq or temp
files (#327): counts fed into `[[ ... -eq ... ]]` crashed with
"integer expression expected" when the upstream call failed or
returned empty - all sites now normalize with a default plus a regex
guard before comparing.

## August 2026

### v8.7 - pr_checks skips redundant Copilot wait on gh observer path (2026-09-01)

- Fixes issue [#320](https://github.com/fini-net/template-repo/issues/320)
- **Related PR:** [#322](https://github.com/fini-net/template-repo/pull/322)

`pr_checks` ran the Copilot wait after the CI watcher exited -
correct for the `gh pr checks --watch` fallback, which never
synchronizes with Copilot, but dead time on the `gh observer` path,
which has gated its own exit on Copilot completion since
gh-observer #409. The wait now branches on which watcher ran: a
one-line note on the observer path, the existing spinner on the
fallback. Purely wasted wall-clock removed, up to ~180s on repos where
Copilot is slow to land.

### v8.6 - compliance_check verifies a custom social preview image (2026-09-01)

- Fixes issue [#242](https://github.com/fini-net/template-repo/issues/242)
- **Related PR:** [#321](https://github.com/fini-net/template-repo/pull/321)

`compliance_check` now verifies a custom social preview image was
uploaded (Settings > General > Social preview) - the image GitHub
renders in link unfurls and social cards, and a missing one is the
cheapest way for an otherwise polished repo to look unfinished. The
REST endpoint does not expose it, so the check queries the GraphQL
`usesCustomOpenGraphImage` field, with both `gh` calls guarded to
preserve the report-only contract. Dogfooding note: this repo failed
the check the day it landed - a good sign it does what it says on
the tin.

### v8.5 - compliance_check gains OpenSSF Scorecard-aligned checks (2026-08-28)

- Fixes issue [#314](https://github.com/fini-net/template-repo/issues/314)
- **Related PR:** [#317](https://github.com/fini-net/template-repo/pull/317)

Eleven OpenSSF Scorecard-aligned heuristics appended to
`compliance_check`, each report-only and detectable with plain `git`,
`gh api`, and `grep` - no new dependencies: Binary-Artifacts, CI-Tests,
Code-Review, Dangerous-Workflow, Dependency-Update-Tool, Maintained,
Pinned-Dependencies, Packaging, SAST, Signed-Releases,
Token-Permissions. Verified live: the three REDs were true findings.
Review rounds caught real bugs before merge - the Code-Review check
always read GREEN because jq sorts any array above any number; a
`set -u` abort on workflow-less repos; local composite actions
wrongly flagged by Pinned-Dependencies - and word-bounded the
bare-token greps (`majestic` no longer counts as a test framework).
Two portability pitfalls worth remembering: unmatched globs make
grep exit 2 even when other patterns matched (silently inverting an
`if grep`), and `stat` flags are platform-dependent (pipe `wc -c`
through awk instead).

### v8.4 - pr_checks waits for Copilot; shared poll script; claude_review cleanup (2026-08-14)

- Fixes issue [#299](https://github.com/fini-net/template-repo/issues/299)
- **Related PR:** [#300](https://github.com/fini-net/template-repo/pull/300)
- Follow-up to v8.3 ([#288](https://github.com/fini-net/template-repo/issues/288))

v8.3 fixed the Copilot race for `copilot_refresh` but left the main PR
flow running a one-shot query the moment the CI watcher exited - CI
settling before Copilot finished (~2-3 min) printed "looks good!" as
a false negative. Five fixes: the poll state machine is extracted
into shared `.just/lib/wait_for_copilot.sh`, now called from
`pr_checks` too (nonfatal mode falls through when Copilot was never
requested); `copilot_refresh` deduplicates onto the same script so
the paths cannot drift; `claude_review`'s early exits no longer skip
the Copilot summary or leak the temp file; completion is now a
Copilot-authored review matching the PR's HEAD sha (replacing the
timestamp filter), with stale-review warnings pointing at
`copilot_refresh`; and the REST fallback comment corrected - GraphQL
with the `... on Bot` fragment is the reliable Copilot signal, REST
returns empty.

### v8.3 - copilot_refresh detects in-progress and zero-comment reviews (2026-08-04)

- Fixes issue [#288](https://github.com/fini-net/template-repo/issues/288)
- **Related PR:** [#289](https://github.com/fini-net/template-repo/pull/289)

Four bugs in the `copilot_refresh` poll loop, surfaced while watching
Copilot review a live PR: no in-progress detection (dots until the
180s timeout even when everything was fine); zero-comment reviews
never registered as complete - the *best* outcome timed out as a
failure; `gh pr view --json reviewRequests` silently drops Bot
reviewers (GraphQL with a `... on Bot` fragment is the reliable
signal); and `reviews(last: 1)` missed Copilot's review whenever
Claude or a human reviewed after it. The rewritten loop runs one
GraphQL call per iteration through a three-state machine - complete /
in-progress / fail-fast with a useful message - and requires two
consecutive "not found" polls before failing, since GitHub's
cross-service reads lag the REST POST that requested the review.

## June 2026 - Bug squash June

### v8.2 - document unset single-quote idiom (2026-06-29)

- Fixes issue [#203](https://github.com/fini-net/template-repo/issues/203)
- **Related PR:** [#222](https://github.com/fini-net/template-repo/pull/222)

`update_pr_body.sh` trims trailing blank lines from the PR footer
with `unset 'footer_content[${#footer_content[@]}-1]'`. The single
quotes are load-bearing: bash's `unset` evaluates its subscript as
arithmetic even when the argument is single-quoted, so the array
length resolves at call time inside `unset`. Without them the calling
shell would expand the length first, producing an index that never
shrinks as the loop iterates. The idiom kept tripping reviewers as a
false-positive bug - each re-flag costs a review round-trip - so
v8.2 adds the three-line comment explaining it directly above the
line. No behavior change.

### v8.1 - fix awk backslash mangling in cue-sync (2026-06-29)

- Fixes issue [#198](https://github.com/fini-net/template-repo/issues/198)
- **Related PR:** [#221](https://github.com/fini-net/template-repo/pull/221)

`cue-sync-from-github` passed the GitHub description to awk via `-v`,
and awk's `-v` assignment processes backslash escapes before the
program runs - `C:\path\to\thing` silently became `C:athothing`,
structurally valid TOML, so `cue vet` passed and the trailing
`cue-verify` restored the backup and exited 1: sync permanently
broken for any repo with a backslash in its description. The first
fix double-escaped for awk but emitted raw backslashes - *invalid*
TOML (`\p` is an illegal escape), so `cue vet` failed instead. The
contract now lives at its root: the description arrives via the
environment (`ENVIRON`, POSIX awk) and the awk program owns the TOML
escaping on emit.

### v8.0 - extract shared `cue_sync.awk` (2026-06-29)

- Fixes issue [#196](https://github.com/fini-net/template-repo/issues/196)
- **Related PR:** [#219](https://github.com/fini-net/template-repo/pull/219)

The awk program powering `cue-sync-from-github` was duplicated
verbatim between the production recipe and the test runner - the test
validated a *copy*, not the production path, the exact fragility that
caused the original #165 regression the suite was built to guard
against. It now lives in `.just/lib/cue_sync.awk`, invoked by both;
the checksum generator globs `*.awk` so it is CHECKSUMS-tracked and
flows to derived repos; and `clean_template` intentionally keeps it,
because `cue-verify.just` depends on it. The "keep this in sync"
comment is gone.

### v7.9 - fix `copilot_rollback` restoring to wrong path (2026-06-29)

- **Related PR:** [#216](https://github.com/fini-net/template-repo/pull/216)
- Fixes issue [#199](https://github.com/fini-net/template-repo/issues/199)

`copilot_rollback` reconstructed the original path by stripping
suffixes from the right, but the timestamp format
(`YYYYMMDD_HHMMSS_PID`) contains two literal underscores, so the
restore silently wrote to a non-existent target and the real source
was never restored. The parser now splits from the left: everything
before the first `_` is the safe path (URL-encoded, so it contains no
literal underscores). See v8.9 for the legacy-name half of this bug -
and the dotfile half hiding underneath it.

### Docs - clarify `.just/*` versioning rule and emoji wording in CLAUDE.md (2026-06-28)

- No CHECKSUMS-tracked file changed in this entry, so no version bump.
- **Related PR:** [#215](https://github.com/fini-net/template-repo/pull/215)

CLAUDE.md previously scattered the "bump version + add release-notes
entry" rule across three places, making it easy to miss that it
applies to every `.just/*` module, not just `gh-process.just`. The
guidance is now a single
[Versioning `.just/*` changes](../CLAUDE.md#versioning-just-changes)
section. The emoji guidance was also reworded to make explicit that
the leading emoji is a free choice by the committer - no recipe
randomizes or validates it.

### v7.8 - fail on malformed web_url in repo_toml_generate (2026-06-28)

- Fixes issue [#200](https://github.com/fini-net/template-repo/issues/200)
- **Related PR:** [#214](https://github.com/fini-net/template-repo/pull/214)

`repo_toml_generate` derived `ORG_NAME`/`REPO_NAME` via `sed`, and on
a no-match sed echoes the input through unchanged - so `not-a-url`
passed the non-empty validation and produced garbage derived names,
while extra path segments silently dropped. A bash regex match
mirroring the cue schema (`^https://github\.com/([^/]+)/([^/]+)$`)
now extracts the names explicitly and fails on anything else, as
defense-in-depth behind `cue vet`.

### v7.7 - fix errexit bypass in cue-sync-from-github (2026-06-28)

- **Related PR:** [#213](https://github.com/fini-net/template-repo/pull/213)
- **Related issue:** [#197](https://github.com/fini-net/template-repo/issues/197)

The recipe wrote its awk output via `awk ... > tmp && mv tmp target`.
Commands in a `&&` list are exempt from errexit, so an awk failure was
swallowed and the recipe continued with the stale `.repo.toml` -
undermining the two-stage validation v6.9 added specifically to catch
silent sync failures. Split into two commands so `set -e` behaves as
intended.

### v7.6 - guard gh-observer detection when gh absent (2026-06-28)

- **Related PR:** [#212](https://github.com/fini-net/template-repo/pull/212)
- **Related issue:** [#201](https://github.com/fini-net/template-repo/issues/201)

`install-prerequisites.sh` ran `gh extension list` without first
verifying `gh` itself was installed - and the `2>/dev/null` suppressed
stderr from `gh`, not the shell's own "command not found" for a
missing binary. A `command -v gh` guard makes `gh-observer` fall
cleanly into the MISSING list like every other tool.

### v7.5 - skip workflow watcher in pr_checks when repo has no workflows (2026-06-28)

- **Related PR:** [#211](https://github.com/fini-net/template-repo/pull/211)
- **Related issue:** [#182](https://github.com/fini-net/template-repo/issues/182)

`pr_checks` unconditionally invoked the watcher even on repos with
no `.github/workflows` directory - and the guard in the `pr` body
never helped, because just dispatches post-dependencies regardless
of the body's `exit 0`. The guard now wraps the watcher inside
`pr_checks` itself.

### v7.4 - fix is_cleaned jq filter in checksums_verify (2026-06-26)

- **Related PR:** [#208](https://github.com/fini-net/template-repo/pull/208)
- **Related issue:** [#195](https://github.com/fini-net/template-repo/issues/195)

The `is_cleaned` filter `any($fp | startswith(.))` rebinds `.` to
`$fp`, so `startswith(.)` becomes a string starts-with-itself -
always true, silently reporting every missing file as "removed by
clean_template". Fixed in `template_update.sh` in v6.7 but the
companion check in `template-sync.just` was missed; both now carry
`any(. as $p | $fp | startswith($p + "/") or $fp == $p)`.

### v7.3 - shellcheck auto-generates repo-toml.sh (2026-06-26)

- **Related PR:** [#207](https://github.com/fini-net/template-repo/pull/207)
- **Related issue:** [#192](https://github.com/fini-net/template-repo/issues/192)

`just shellcheck` reported confusing SC1091 "Not following" errors on
every fresh clone, because `.just/repo-toml.sh` is gitignored and
generated, not committed. The shellcheck recipe now runs
`repo_toml_generate` automatically when the file is missing, and
prints a single clear warning and exits non-zero if generation fails,
instead of continuing with four misleading errors.

### v7.2 - clean_template strips cue-sync test infra; mktemp portability (2026-06-26)

- **Related PR:** [#205](https://github.com/fini-net/template-repo/pull/205)
- **Related issue:** [#194](https://github.com/fini-net/template-repo/issues/194)

`clean_template` stripped the PR-body test infra but never the v6.9
cue-sync test infra, so derived repos shipped a dead
`cue_sync_test.sh` whose missing-fixtures guard exited 0 with "Tests
skipped" - green, asserting nothing, in 9+ derived repos. The
runner, its workflow, and `template-sync.yml` (which invoked a
now-removed recipe and failed on every qualifying push) are now
stripped too. The `update_from_template` machinery is intentionally
retained so derived repos can still self-update. Also fixed
`mktemp -d` to use a portable template for BSD/macOS.

### v7.1 - Drop npm fallback for markdownlint-cli2 (2026-06-25)

- **Related PR:** [#186](https://github.com/fini-net/template-repo/pull/186)
- Fixes issue [#185](https://github.com/fini-net/template-repo/issues/185)

The macOS install path still fell back to `npm install -g
markdownlint-cli2` when Homebrew was absent - an unpinned install
that defeated the Scorecard Pinned-Dependencies point of pinning via
brew. The fallback is gone; the macOS path is brew-only.

### v7.0 - Resolve v6.9/v6.10 version-label confusion (2026-06-24)

- **Related PR:** [#178](https://github.com/fini-net/template-repo/pull/178)

PR #175 (v6.9) landed as a single squash, but its messy branch
history leaked through: a `# PR create v6.10` comment for a version
that never existed as its own release, a phantom v6.10
release-notes section, and CHECKSUMS "latest" entries pointing at
intermediate branch commits that never reached `main`. v7.0 reverts
the spurious bump, folds the phantom section into v6.9, and
regenerates the manifest against the commits that actually shipped.

### v6.9 - Handle commented/missing topics & defer backup deletion (2026-06-24)

- **Related PR:** [#175](https://github.com/fini-net/template-repo/pull/175)
- Fixes issue [#165](https://github.com/fini-net/template-repo/issues/165)

`cue-sync-from-github` silently failed to sync `topics` (or
`description`) when the line in `.repo.toml` was commented out or
missing entirely - then reported "Successfully synced", and the
backup had already been deleted, leaving the trailing `cue-verify` as
the only (post-hoc) signal of failure. The awk block now tolerates a
commented prefix and inserts missing keys at the end of `[about]`,
buffering blank lines so insertions land adjacent to the preceding
key; the backup now survives both `cue vet` *and* `cue-verify`, with
restore on mismatch. Added the `commented_topics` fixture - the exact
regression this targets, missing from the original test matrix -
plus an active-keys happy path.

### v6.8 - Trailing blank line accumulation fix (2026-06-23)

- **Related PR:** [#174](https://github.com/fini-net/template-repo/pull/174)
- Fixes issue [#173](https://github.com/fini-net/template-repo/issues/173)

Each `pr_update` cycle added ~2 trailing blank lines - GitHub's API,
jq's raw output, and the update script each appended one - so a PR
iterated on 8 times ended up with ~16 trailing blanks after
`## Meta`. The fix trims trailing empty entries from the
`footer_content` array in `update_pr_body.sh`, breaking the
accumulation cycle at the parser regardless of how many newlines the
round-trip adds. Fixture 15 pins it. Related: the v4.4 blank-line fix
guarded blanks *between* sections but inadvertently preserved this
trailing-accumulation path.

### v6.7 - Fix update_from_template failures on test fixtures (2026-06-20)

- **Related PR:** [#163](https://github.com/fini-net/template-repo/pull/163)
- Fixes issue [#162](https://github.com/fini-net/template-repo/issues/162)

`update_from_template` in a derived repo failed with seven "Download
failed after 3 attempts" lines for `.just/test/fixtures/...` paths -
three compounding bugs. Test fixtures leaked into CHECKSUMS via git's
pathspec `*` matching across `/` (now excluded; the manifest dropped
from 25 to 18 files). The `is_cleaned` jq scoping bug (see v7.4)
treated *every* missing file as cleaned, masking the symptom. And
`download_file` never created the target directory, so `curl -o`
failed on every retry - with curl's stderr swallowed by
`2>/dev/null`, producing the misleading retry message.

## May 2026 - The Repolish Updates

### v6.6 - Cleaner Copilot Review Feedback (2026-05-22)

- **Related PR:** [#152](https://github.com/fini-net/template-repo/pull/152)
- Fixes issue [#151](https://github.com/fini-net/template-repo/issues/151)

Copilot review feedback decluttered: the GraphQL query filters to
unresolved threads only, and `copilot_refresh` auto-resolves old
threads before requesting the fresh review, so each refresh starts
with a clean slate. The count and display exclude resolved
suggestions, with a report of how many were resolved and a warning if
any failed.

### v6.5 - Install gh-observer (2026-05-01)

- **Related PR:** [#142](https://github.com/fini-net/template-repo/pull/142)
- Fixes issue [#123](https://github.com/fini-net/template-repo/issues/123)

`gh-observer` joined the prerequisites list - the extension was
already used by the `pr` recipe since v5.7, but was never installed
by the script, so a missing installation silently fell back to the
polling loop.

## April 2026 - Guard rails

### v6.4 - Prerequisites Update and Cue Schema Fix (2026-04-23)

- **Related PR:** [#131](https://github.com/fini-net/template-repo/pull/131)
- Fixes issue [#118](https://github.com/fini-net/template-repo/issues/118)

`cue` joined the prerequisites script (detection, Homebrew install on
macOS, manual instructions elsewhere), and the `web_url` regex in
`docs/repo-toml.cue` changed from `[^/]+/.+` to `[^/]+/[^/]+` so URLs
with trailing path segments cannot validate.

### v6.3 - Copilot Path Encoding and Portability Fixes (2026-04-23)

- **Related PR:** [#130](https://github.com/fini-net/template-repo/pull/130)
- Fixes issue [#114](https://github.com/fini-net/template-repo/issues/114)

Four bugs in `.just/copilot.just` identified across 15 PR code
reviews: `sed -i` replaced with a temp-file approach (BSD/GNU differ);
backup filenames now URL-encode (`%2F` for `/`, `%5F` for `_`)
instead of the ambiguous, lossy `_` substitution, with
`copilot_rollback` decoding the new format and falling back for
legacy backups; `copilot_pick` matches suggestions by both file and
line number, so same-line suggestions in different files cannot
collide; and `copilot_refresh` writes its poll loop to a temp script
passing variables as arguments, instead of serializing functions with
`declare -f`.

### v6.2 - Template Sync Refinements (2026-04-23)

- **Related PR:** [#129](https://github.com/fini-net/template-repo/pull/129)
- Fixes issue [#116](https://github.com/fini-net/template-repo/issues/116)

Template sync robustness: downloaded files are checksum-verified
against the manifest before moving into place; cleaned-file matching
is directory-aware via `startswith`, so files under a listed
directory count as cleaned; and `checksums_verify` fails with a real
error when neither `sha256sum` nor `shasum` is found, instead of
silently producing empty output.

### v6.1 - Shell Escaping in repo_toml_generate (2026-04-23)

- **Related PR:** [#126](https://github.com/fini-net/template-repo/pull/126)
- Fixes issue [#117](https://github.com/fini-net/template-repo/issues/117)

`repo_toml_generate` could produce broken output when `.repo.toml`
values contained shell metacharacters. JSON-sourced values now use
`jq @sh`, sed/paste-derived values use `printf '%q'` via a new
`shell_quote()` helper, and a `WEB_URL_RAW` intermediate strips the
`@sh` quoting before URL parsing. The generated file shifts from
double-quoted to single-quoted values - functionally equivalent when
sourced.

### v6.0 - Claude Code Launch Recipe (2026-04-23)

- **Related PR:** [#125](https://github.com/fini-net/template-repo/pull/125)
- Fixes issue [#112](https://github.com/fini-net/template-repo/issues/112)

New `claude` recipe launching Claude Code from the repo root - just
recipes run from the root by default, so `just claude` always starts
with full project context regardless of the caller's directory.

### v5.9 - PR Checks Requires Active Pull Request (2026-04-19)

- Fixes issue [#115](https://github.com/fini-net/template-repo/issues/115)
- **Fix PR:** [#122](https://github.com/fini-net/template-repo/pull/122)
- **Regression PR:** [#97](https://github.com/fini-net/template-repo/pull/97)

`pr_checks` now requires an active PR (`_on_a_pull_request`
dependency) instead of failing with cryptic `gh` errors outside PR
context, matching `pr_update` and `pr_verify`. The guard's history is
a small morality tale: present v4.0-v4.4, inherited transitively
v4.5-v5.2, then accidentally dropped in v5.7 when `_wait_for_checks`
moved from a dependency to an inline fallback - restored directly.

## March 2026 - More resilience

### v5.8.1 - Executable permissions for template updates (2026-03-22)

- **Related PR:** [#110](https://github.com/fini-net/template-repo/pull/110)

Downloaded `.just/lib/*.sh` files are now made executable
automatically, so `update_from_template` is fully self-contained -
previously they required manual `chmod +x`. `common.sh` is exempt: it
is only sourced, never executed.

### v5.8 - CRLF-Resilient PR Body Updates (2026-03-21)

- **Related PR:** [#107](https://github.com/fini-net/template-repo/pull/107)

`pr_update` could silently produce corrupted output when the PR body
contained Windows-style CRLF line endings - GitHub's API returns them
occasionally, and the state machine parser was not stripping the
carriage returns, so the HTML marker detection could miss
`<!-- PR_BODY_DONE_START -->`. One line added to `update_pr_body.sh`
(`line="${line%$'\r'}"` before any pattern matching), plus fixture 14
with a `.gitattributes` override so the test actually exercises CRLF
rather than git normalizing it away. Originally surfaced while
debugging `template_update.sh` in
[PR #103](https://github.com/fini-net/template-repo/pull/103).

## February 2026 - Learn from experience

### v5.7 - Utilize gh observer extension (2026-02-16)

- **Related PR:** [#97](https://github.com/fini-net/template-repo/pull/97)

Utilize the
[gh observer extension](https://github.com/fini-net/gh-observer) if
it is installed.

## January 2026 - Avila Beach is awesome

### v5.6 - Release Version Validation (2026-01-30)

- **Related PR:** [#92](https://github.com/fini-net/template-repo/pull/92)

The `release` recipe now validates the version format before creating
a GitHub release - previously `just release anything` attempted a
release with whatever string you provided. The check requires `v`
followed by a digit, fails fast with a red error, and prevents typos
like `just release 1.0.0` (missing `v`) or `vNext`. Tightened further
in v9.7.

### v5.5 - Robust Copilot Suggestion Application (2026-01-28)

- Fixes issue [#76](https://github.com/fini-net/template-repo/issues/76)
- **Related PR:** [#88](https://github.com/fini-net/template-repo/pull/88)

`copilot_pick` can now apply Copilot suggestions directly, with
safety nets: timestamped backups in `.just/copilot_backups/` (added to
`.gitignore`), multi-line support with a visual preview, a two-stage
confirm workflow, and an offer to push applied changes back to the
PR. The new `copilot_rollback` recipe restores from those backups
interactively. Review-driven safety fixes landed in the same release:
the dangerous sed command now escapes special characters and uses a
`|` delimiter, AWK extraction handles multiple code blocks, backups
store full paths to prevent traversal, and restoration validates
integrity before overwriting.

### v5.3 - Configurable Release Workflow (2026-01-28)

- Fixes issue [#82](https://github.com/fini-net/template-repo/issues/82)
- **Related PR:** [#84](https://github.com/fini-net/template-repo/pull/84)

New `standard-release` flag in `.repo.toml` lets projects with custom
release mechanisms disable the default `release` / `release_age`
recipes - they display an informational message and exit 0. Unset or
`true` keeps standard behavior, so repos without the flag are
unchanged.

### v5.2 - Template Sync System (2026-01-27)

- Fixes issue [#55](https://github.com/fini-net/template-repo/issues/55)
- **Related PR:** [#83](https://github.com/fini-net/template-repo/pull/83)

The safe update mechanism: derived repos can pull changes from
template-repo while preserving local customizations. A new
`.just/template-sync.just` module ships four recipes -
`checksums_generate` (versioned checksums from git history,
template-repo only), `update_from_template` (only modifies files
whose checksums match a known template version), `checksums_verify`,
and `checksums_diff`. Backing it: multi-version checksum tracking in
`.just/CHECKSUMS.json`, retry-with-backoff downloads, automatic
backup and restore, and a fixture-driven test suite with CI.

### v5.1 - On-Demand Copilot Reviews (2026-01-XX)

- **Fixes issue:** [#77](https://github.com/fini-net/template-repo/issues/77)
- **Related PR:** [#79](https://github.com/fini-net/template-repo/pull/79)

New `copilot_refresh` recipe requests a fresh Copilot review on the
current PR via the REST API, polls for completion with a spinner
(gum) or dots fallback, and displays the suggestion count with a
pointer to `copilot_pick`. Complements the v4.8 picker workflow.

### v5.0 - Robust PR Body Updates with HTML Markers

- **Related PR:** [#78](https://github.com/fini-net/template-repo/pull/78)
- **Fixes issue:** [#57](https://github.com/fini-net/template-repo/issues/57)

Complete rewrite of `pr_update` to eliminate data loss. The old AWK
implementation was fragile: manual edits could be corrupted when
custom sections existed between Done and Meta, or when code blocks
contained `## Done` markers. The new implementation puts invisible
HTML comment markers around the Done section for unambiguous
boundaries, tracks code blocks so `## Done` inside a fenced example
cannot confuse the parser, inserts a missing Done section
intelligently, and falls back to header detection for old PRs - which
then receive markers for future updates. The logic lives in a
standalone testable script, `.just/lib/update_pr_body.sh`, with 13
fixtures and CI. Same external interface; much more robust.

### v4.9 - Copilot Suggestion Count

- **Fixes issue:** [#73](https://github.com/fini-net/template-repo/issues/73)
- **Related PR:** [#74](https://github.com/fini-net/template-repo/pull/74)

The post-checks JSON dump of Copilot suggestions became a count
summary - "Total Copilot suggestions: N" right after checks complete,
with the same summary repeated at the end of `claude_review` so you
remember whether there are items to address without scrolling back.
Temp filenames now use PR metadata
(`/tmp/copilot_count_${OWNER}_${REPO}_${PR}`) so multi-PR work
cannot collide. Full JSON still prints for programmatic parsing -
the count is additive, not a replacement.

### v4.8 - Copilot Suggestion Picker

- **Fixes issue:** [#67](https://github.com/fini-net/template-repo/issues/67)
- **Related PR:** [#72](https://github.com/fini-net/template-repo/pull/72)

New `copilot_pick` recipe: browse Copilot PR review suggestions in a
`gum` list (`file:line - preview` format), view the full body on
selection. Validates `gum` and `jq` up front with install hints,
fetches via GraphQL (limits documented), handles line-number
extraction robustly, and cleans up temp files with a single trap
(fixed an initial dual-trap bug that could leave temp files behind).
Fills the gap between the automated post-checks dump and opening the
PR in a browser.

### v4.6 - Conditional AI Review Display

- **Fixes issue:** [#63](https://github.com/fini-net/template-repo/issues/63)
- **Related PR:** [#64](https://github.com/fini-net/template-repo/pull/64)

New `.just/repo-toml.just` module generates a sourceable
`.just/repo-toml.sh` holding all repository metadata as shell
variables - single source of truth, no repeated `.repo.toml`
parsing. `repo_toml_generate` exports values with derived org/repo
names and TOML arrays as both bash arrays and CSV; `repo_toml_check`
validates staleness. `pr_checks` and `claude_review` now display
reviews only when the corresponding `.repo.toml` flags
(`copilot-review`, `claude-review`) are enabled, defaulting flags to
false when the generated file is missing rather than failing hard.
The generated file is gitignored, regenerated on demand.

### v4.7 - Stale Review Detection

- **Fixes issue:** [#69](https://github.com/fini-net/template-repo/issues/69)
- **Related PR:** [#70](https://github.com/fini-net/template-repo/pull/70)

`claude_review` now warns when Claude's feedback predates your
latest push instead of blindly displaying it as current: missing
review, stale review (with both timestamps and a disclaimer), or
current - with cross-platform date handling and a permanent exit 0 so
workflow chains never break. Timestamp comparison is the correct
approach because Claude's workflow comments via `gh pr comment`
(IssueComments carry no commit SHA association).

### v4.5 - Smart Polling for PR Checks

- **Fixes issue:** [#60](https://github.com/fini-net/template-repo/issues/60)
- **Related PR:** [#61](https://github.com/fini-net/template-repo/pull/61)

The fixed 8-second post-PR sleep became a polling loop: ask GitHub
every 2 seconds (30-second timeout) whether checks have started, with
a `gum spin` spinner and a dots fallback. Faster feedback when GitHub
is quick (2-6s typical), graceful when it is slow.

## December 2025 - Finer refinements

### v4.4 - PR Update Blank Line Preservation

- **Related PR:** [#50](https://github.com/fini-net/template-repo/pull/50)

Fixed a logic error in `pr_update`'s AWK script where blank lines
after the Done section were eaten even after transitioning past it -
an `!after_done` guard now preserves the original spacing between
sections.

### v4.3 - Release Tag Visibility

- **Related PR:** [#49](https://github.com/fini-net/template-repo/pull/49)

`just release` now runs `git pull` after `gh release create` (with a
1-second sleep for the API to settle) so the new tag is visible
locally right away instead of requiring a manual pull. A tiny paper
cut, removed.

### v4.2 - Prerequisites Installation Script

- **Related PR:** [#48](https://github.com/fini-net/template-repo/pull/48)

New `install-prerequisites.sh`: checks for every required tool (just,
gh, shellcheck, markdownlint-cli2, jq), auto-installs via Homebrew on
macOS or prints the right commands for Linux, and shows what is
installed vs missing in color. Run
`./.just/lib/install-prerequisites.sh` to check your environment.

### v4.1 - Release Monitoring and Iteration Workflow

- **Related PR:** [#46](https://github.com/fini-net/template-repo/pull/46)

Three new recipes: `release_age` (how long ago the last release was,
with a yellow nudge past 60 days), `claude_review` (Claude's latest
PR comment as a standalone recipe, still chained from `pr_checks`),
and `again` (push, update the PR description, re-watch checks - the
common iterate loop in one command).

## November 2025 - The Polish Updates

### v4.0 - PR Description Management

- **Related PR:** [#44](https://github.com/fini-net/template-repo/pull/44)

New `pr_update` (refresh the "Done" section of the PR description
with current commits via `git cherry`) and `pr_verify` (append
timestamped verification output to a "Verify" section). Both are
guarded by a new `_on_a_pull_request` sanity check so running them
outside PR context fails with a clear message instead of cryptic
`gh` errors.

### v3.9 - Shellcheck Error Fixes

- **Related PR:** [#40](https://github.com/fini-net/template-repo/pull/40)

Fixed all the shellcheck warnings the v3.8bis tooling found in the
gh-process module itself - better quoting, better conditionals.
Nothing user-facing changed, but future AI code reviews have less
trivial stuff to complain about.

### v3.8bis - Shellcheck Integration

- **Related PRs:** [#37](https://github.com/fini-net/template-repo/pull/37),
  [#39](https://github.com/fini-net/template-repo/pull/39)

New `.just/shellcheck.just` module: extracts the bash scripts from
all just recipes, runs shellcheck on each, and reports which file
and recipe each issue is in. It's pretty meta - using just to check
just recipes - 138 lines of awk magic, purple section headings
because why not. Immediately found issues in our own code, which led
to v3.9.

### v3.8 - Git Alias Expansion

- **Related PR:** [#35](https://github.com/fini-net/template-repo/pull/35)

Expanded the git aliases to standard git commands - previously the
workflow required my personal aliases (`stp`, `pushup`, `co`)
configured. Now it works out of the box for everyone, with inline
comments showing the old alias names for reference.

### v3.7 - Pre-PR Hook Support

- **Related PRs:** [#32](https://github.com/fini-net/template-repo/pull/32),
  [#33](https://github.com/fini-net/template-repo/pull/33)

Optional pre-PR hooks: the `pr` recipe checks for
`.just/pr-hook.just` and runs it if present - useful for projects
that need to rebuild assets (like Hugo sites) before pushing.

### v3.6 - Quote Consistency

- **Related PR:** [#31](https://github.com/fini-net/template-repo/pull/31)

More consistent quoting of variables and just template parameters.
Small change, more reliable with branch names or paths containing
spaces.

### v3.5 - Spacing and Multi-Commit Handling

- **Related PR:** [#30](https://github.com/fini-net/template-repo/pull/30)

Cleaned up formatting and vestigial variables, improved quoting, and
made branches with multiple commits behave consistently.

## October 2025 - The AI Review Update

### v3.4 - Graceful Failure Handling

- **Related PR:** [#26](https://github.com/fini-net/template-repo/pull/26)

Broken GitHub Actions no longer prevent the review comments from
displaying - you probably want to see the AI reviews even more when
things are broken.

### v3.3 - Copilot and Claude Review Integration

- **Related PR:** [#25](https://github.com/fini-net/template-repo/pull/25)

This was a big one. After PR checks complete, the workflow fetches
and displays both Copilot and Claude review comments right in the
terminal - no more switching to the browser to see what the bots
think. GraphQL query plus `jq` parsing.

## August 2025 - The Safety Update

### v3.2 - Commit Verification

- **Related PR:** [#21](https://github.com/fini-net/template-repo/pull/21)

`pr` now verifies the branch actually has commits before creating a
pull request (`git cherry` against the release branch, exit 101 on
empty) - no more accidental empty PRs.

### Faster PR Check Monitoring

- **Related PR:** [#20](https://github.com/fini-net/template-repo/pull/20)

The PR checks watcher polls every 5 seconds instead of the default.
Because who wants to wait around? GitHub's API might be lazy, but we
don't have to be.

## June 2025 - The Beginning of this file

### v3.1 - Initial Release

- **Related PR:** [#11](https://github.com/fini-net/template-repo/pull/11)

Created as part of a larger refactoring effort to modularize the main
justfile: all the Git/GitHub workflow automation (`sync`, `pr`,
`merge`, `branch`, `prweb`, `release`, `pr_checks`) extracted into
`.just/gh-process.just`, plus the sanity-check helpers
(`_on_a_branch`, `_main_branch`, `_has_commits`, and friends) that
keep you from footgunning yourself.

---

## Pre-history

Earlier versions of this code came from the `/justfile` in
[this repo](https://github.com/fini-net/template-repo/blob/main/justfile)
and some of my other repos, primarily
[www-chicks-net](https://github.com/chicks-net/www-chicks-net/blob/main/justfile).
It all started [very simply](https://github.com/chicks-net/www-chicks-net/commit/06f28b13d82e445951b10af1a57488a1dc9e1069).

I think there were some 2.x versions, but I haven't rediscovered them.
