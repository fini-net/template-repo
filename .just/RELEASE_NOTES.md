# Release Notes: gh-process.just

This file tracks the evolution of the Git/GitHub workflow automation module.

## June 2026 - Bug squash June

### v8.1 - fix awk backslash mangling in cue-sync (2026-06-29)

- Fixes issue [#198](https://github.com/fini-net/template-repo/issues/198)

`cue-sync-from-github` escaped the GitHub description for TOML but
passed the result to awk via `-v desc=...`. awk's `-v` assignment
processes backslash escape sequences before the program runs, so any
backslash in a repo description (Windows paths, regexes, prose) was
silently mangled — `C:\path\to\thing` became `C:athothing`. The
resulting TOML was structurally valid, so `cue vet` didn't catch it;
the trailing `cue-verify` then detected a mismatch against the GitHub
API, restored the backup, and exited 1 — leaving sync permanently
broken for any repo with a backslash in its description.

v8.1 double-escapes backslashes before the quote-escape step so awk's
`-v` un-escapes them back to single backslashes, and the TOML writer
sees the original value.

### v8.0 - extract shared `cue_sync.awk` (2026-06-29)

- Fixes issue [#196](https://github.com/fini-net/template-repo/issues/196)
- **Related PR:** [#219](https://github.com/fini-net/template-repo/pull/219)

The awk program powering `cue-sync-from-github` was duplicated verbatim
between `.just/cue-verify.just` (the production recipe) and
`.just/lib/cue_sync_test.sh` (the test runner). The test file even
acknowledged the hazard with a "keep this in sync with the recipe"
comment — the exact fragility that caused the original #165 regression
the test suite was built to guard against. If the recipe's awk was
silently modified without updating the test copy, the tests kept
passing while production code regressed: the test validated a **copy**,
not the production path.

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

`copilot_rollback` reconstructed the original file path from the backup
filename by stripping suffixes from the **right**. Because the timestamp
format (`YYYYMMDD_HHMMSS_PID`) contains two literal underscores,
`${filename%_*}` only removed the trailing `_<PID>.bak` and left the
`YYYYMMDD_HHMMSS` fragment glued onto the encoded path. The result was
a non-existent target like `.just/copilot.just_20260626_143022`, so the
restore silently wrote to the wrong file and the real source was never
restored (issue #199).

The parser now strips from the **left**: `${filename%%_*}` takes
everything before the first `_` as the safe path (safe because
`safe_path` is `%5F`-encoded and contains no literal `_`), and
`${filename#*_}` yields the full `YYYYMMDD_HHMMSS_PID` timestamp. The
backup-writing code was already correct; only the parser needed fixing.

### Docs - clarify `.just/*` versioning rule and emoji wording in CLAUDE.md (2026-06-28)

- No CHECKSUMS-tracked file changed in this entry, so no version bump.

CLAUDE.md previously scattered the "bump version + add release-notes
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

- **Related issue:** [#195](https://github.com/fini-net/template-repo/issues/195)

The `is_cleaned` jq filter in `.just/template-sync.just` was always evaluating
to true for any non-empty `cleaned_files` list, causing `checksums_verify` to
silently report "removed by clean_template" for every missing file regardless
of whether it was actually listed in `cleaned_files`.

The broken filter `any($fp | startswith(.))` rebinds `.` to `$fp` inside `any`,
so `startswith(.)` becomes `startswith($fp)` — a string always starts with
itself, so the result is always true.

The same bug was fixed in `.just/lib/template_update.sh` in v6.7 (PR #163)
but the companion check in `template-sync.just` was missed. v7.4 applies the
same corrected filter:

```jq
any(. as $p | $fp | startswith($p + "/") or $fp == $p)
```

This correctly matches only files that are equal to a cleaned path or are
nested under a cleaned directory.

### v7.3 - shellcheck auto-generates repo-toml.sh (2026-06-26)

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

- **Related issue:** [#194](https://github.com/fini-net/template-repo/issues/194)

`just clean_template` already removed the PR-body test infrastructure
(`.just/testing.just`, `.just/lib/pr_body_test.sh`, `.just/test/`, and the
`pr-body-tests.yml` / `checksums-verify.yml` workflows) but the cue-sync test
infra added in v6.9 (PR #175) was never added to the cleanup. Derived repos
that ran `clean_template` shipped a dead `.just/lib/cue_sync_test.sh` runner
whose missing-fixtures guard at line 156–160 exits 0 with "Tests skipped" —
`just cue_sync_test` asserted nothing and went green in 9+ derived repos.

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

While touching the runner, fix `mktemp -d` at `cue_sync_test.sh:119` to use
a portable template (`mktemp -d -t cue_sync_test.XXXXXX`) so it works on
BSD/macOS, which require X's in the template. Flagged by Copilot in
`fini-projects#31`.

### v7.1 - Drop npm fallback for markdownlint-cli2 (2026-06-25)

- **Related PR:** [#186](https://github.com/fini-net/template-repo/pull/186)
- Fixes issue [#185](https://github.com/fini-net/template-repo/issues/185)

PR #186 pinned `markdownlint-cli2` via Homebrew to satisfy Scorecard's
Pinned-Dependencies check, but the macOS install path still fell back to
`npm install -g markdownlint-cli2` when Homebrew was absent — an unpinned
install that left the Scorecard warning in place. v7.1 removes the npm
fallback so the prerequisites installer is brew-only on macOS, matching
the PR's stated goal.

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

PR #175 (v6.9) landed on `main` as a single squash commit, but the messy
branch history that preceded it leaked two artifacts through into the
shipped state: the `pr` recipe comment in `.just/gh-process.just` read
`# PR create v6.10`, and `RELEASE_NOTES.md` carried a separate
`### v6.10 - Complete cue-sync test matrix` section describing follow-up
review work that never existed as its own release. The
`.just/CHECKSUMS.json` manifest was similarly misaligned - its "latest"
entries for `.just/cue-verify.just`, `.just/testing.just`, and
`.just/lib/cue_sync_test.sh` pointed at intermediate branch commits
(`dc02707`, `1f0b3c3`, `626d593`) with empty `version` strings, rather
than the squash commit (`d499305`) that actually landed on `main`.

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
- **Folded the v6.10 release notes into v6.9.** The four bullets that
  described the cue-sync test-matrix completion (the
  `commented_topics.toml` and `active_keys.toml` fixtures, trailing
  newlines on the v6.9-added files, and the `SC2002` fix in
  `cue_sync_test.sh`) all shipped inside PR #175's squash, so they belong
  under v6.9. The standalone `### v6.10` section and its month header are
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
to PR #175's landing.

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
- Added `.just/test/fixtures/cue_sync/commented_topics.toml` and a
  corresponding test case. This is the headline fix for issue #165, yet
  the original test matrix only covered `commented_description` -
  `commented_topics` is the exact regression the awk change targets.
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

**Related:** The v4.4 blank-line preservation fix (PR #50) correctly
guarded blank lines *between* sections but inadvertently also preserved
the trailing-blank-line accumulation path this issue describes. The v5.8
CRLF normalization (PR #107) is a related robustness effort.

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

- **v4.0–v4.4** — `pr_checks: _on_a_pull_request` (direct dependency, added in #44)
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

Utilize the [gh observer extension](https://github.com/fini-net/gh-observer) if it is installed.

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
- Complements existing copilot_pick (#67, #72) workflow

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

- **Related PRs:** [#37](https://github.com/fini-net/template-repo/pull/37), [#39](https://github.com/fini-net/template-repo/pull/39)

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

- **Related PRs:** [#32](https://github.com/fini-net/template-repo/pull/32), [#33](https://github.com/fini-net/template-repo/pull/33)

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
