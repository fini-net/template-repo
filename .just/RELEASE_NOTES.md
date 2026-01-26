# Release Notes: gh-process.just

This file tracks the evolution of the Git/GitHub workflow automation module.

## January 2026 - Experience leads to more opportunities

### v4.6 - Conditional AI Review Display (#63)

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

**Related PRs:** [#63](https://github.com/fini-net/template-repo/pull/63)

### v4.7 - Stale Review Detection (#69)

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

**Related PRs:** [#69](https://github.com/fini-net/template-repo/pull/69)

### v4.5 - Smart Polling for PR Checks

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

**Related PRs:** [#50](https://github.com/fini-net/template-repo/pull/50)

### v4.3 - Release Tag Visibility

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

### v4.2 - Prerequisites Installation Script (#48)

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
Run `./.just/install-prerequisites.sh` to check your environment or install
missing tools.

**Related PRs:** [#48](https://github.com/fini-net/template-repo/pull/48)

### v4.1 - Release Monitoring and Iteration Workflow (#46)

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

**Related PRs:** [#46](https://github.com/fini-net/template-repo/pull/46)

## November 2025 - The Polish Updates

### v4.0 - PR Description Management (#44)

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

**Related PRs:** [#44](https://github.com/fini-net/template-repo/pull/44)

### v3.9 - Shellcheck Error Fixes (#40)

Before adding the shellcheck tooling in v3.8bis, we knew there were a bunch of
shellcheck warnings in the gh-process module itself. This release fixes all
of those issues - better variable quoting, improved conditional syntax, and
other shellcheck best practices. Nothing user-facing changed, but the code is
now cleaner and more robust. This should also mean that our future AI code
reviews will have less trivial stuff to complain about.

**Related PRs:** [#40](https://github.com/fini-net/template-repo/pull/40)

### v3.8bis - Shellcheck Integration (#37, #39)

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

**Related PRs:** [#37](https://github.com/fini-net/template-repo/pull/37), [#39](https://github.com/fini-net/template-repo/pull/39)

### v3.8 - Git Alias Expansion (#35)

Expanded all git aliases to use standard git commands, making this justfile
work for everyone without requiring custom git configuration. Previously,
you needed my personal git aliases (`stp`, `pushup`, `co`) configured to use
this workflow. Now it just works out of the box.

- `git stp` → `git status --porcelain`
- `git pushup` → `git push -u origin HEAD`
- `git co` → `git checkout`

Added inline comments showing the old alias names for reference, so if you're
used to seeing `stp` in the output, you know what's happening.

**Related PRs:** [#35](https://github.com/fini-net/template-repo/pull/35)

### v3.7 - Pre-PR Hook Support (#32, #33)

Added support for optional pre-PR hooks to allow project-specific automation
before creating pull requests. The `pr` recipe now checks for
`.just/pr-hook.just` and runs it if present. This is particularly useful for
projects that need to rebuild assets (like Hugo sites) before pushing.

- Added conditional hook execution in PR workflow
- Hidden `_pr-hook` recipe (internal use)
- Updated documentation with workflow versioning

**Related PRs:** [#32](https://github.com/fini-net/template-repo/pull/32), [#33](https://github.com/fini-net/template-repo/pull/33)

### v3.6 - Quote Consistency (#31)

Improved shell script robustness with more consistent quoting of variables and
just template parameters. Small change, but makes the scripts more reliable
when dealing with branch names or paths that might contain spaces.

**Related PRs:** [#31](https://github.com/fini-net/template-repo/pull/31)

### v3.5 - Spacing and Multi-Commit Handling (#30)

Cleaned up the codebase and improved handling of branches with multiple commits:

- Better formatting and spacing throughout
- Cleaned up vestigial variables from earlier iterations
- Improved quoting of just variables
- More consistent handling of multiple commits on a branch

**Related PRs:** [#30](https://github.com/fini-net/template-repo/pull/30)

## October 2025 - The AI Review Update

### v3.4 - Graceful Failure Handling (#26)

Fixed an issue where broken GitHub Actions would prevent the review comments
from being displayed. The workflow now continues to show AI reviews even if
some checks fail, because you probably want to see those reviews even more when
things are broken.

**Related PRs:** [#26](https://github.com/fini-net/template-repo/pull/26)

### v3.3 - Copilot and Claude Review Integration (#25)

This was a big one. After PR checks complete, the workflow now automatically
fetches and displays comments from both GitHub Copilot and Claude Code reviews
right in your terminal. No more switching to the browser to see what the bots
think.

- Added GraphQL query to fetch Copilot PR review comments
- Displays Copilot suggestions after PR checks complete
- Shows Claude's most recent comment
- Uses `jq` to parse and filter review data

**Related PRs:** [#25](https://github.com/fini-net/template-repo/pull/25)

## August 2025 - The Safety Update

### v3.2 - Commit Verification (#21)

Added a sanity check to prevent accidentally creating empty PRs. The `pr` recipe now verifies that your branch actually has commits before allowing you to create a pull request. Uses `git cherry` to compare against the release branch.

- New `_has_commits` dependency check
- Clear error message when branch is empty
- Exit code 101 for tracking

**Related PRs:** [#21](https://github.com/fini-net/template-repo/pull/21)

### Faster PR Check Monitoring (#20)

Changed the PR checks watcher to poll every 5 seconds instead of the default. Because who wants to wait around? GitHub's API might be lazy, but we don't have to be.

**Related PRs:** [#20](https://github.com/fini-net/template-repo/pull/20)

## June 2025 - The Beginning of this file

### v3.1 - Initial Release (#11)

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

**Related PRs:** [#11](https://github.com/fini-net/template-repo/pull/11)

---

## Pre-history

Earlier versions of this code came from the `/justfile` in
[this repo](https://github.com/fini-net/template-repo/blob/main/justfile)
and some of my other repos, primarily
[www-chicks-net](https://github.com/chicks-net/www-chicks-net/blob/main/justfile).
It all started [very simply](https://github.com/chicks-net/www-chicks-net/commit/06f28b13d82e445951b10af1a57488a1dc9e1069).

I think there were some 2.x versions, but I haven't found them again.
