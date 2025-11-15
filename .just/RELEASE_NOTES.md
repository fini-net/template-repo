# Release Notes: gh-process.just

This file tracks the evolution of the Git/GitHub workflow automation module.

## November 2025 - The Polish Updates

### v3.8 - Git Alias Expansion

Expanded all git aliases to use standard git commands, making this justfile
work for everyone without requiring custom git configuration. Previously,
you needed my personal git aliases (`stp`, `pushup`, `co`) configured to use
this workflow. Now it just works out of the box.

- `git stp` → `git status --porcelain`
- `git pushup` → `git push -u origin HEAD`
- `git co` → `git checkout`

Added inline comments showing the old alias names for reference, so if you're
used to seeing `stp` in the output, you know what's happening.

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
