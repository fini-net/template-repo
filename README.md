# FINI template-repo

![GitHub Issues](https://img.shields.io/github/issues/fini-net/template-repo)
![GitHub Pull Requests](https://img.shields.io/github/issues-pr/fini-net/template-repo)
![GitHub License](https://img.shields.io/github/license/fini-net/template-repo)
![GitHub watchers](https://img.shields.io/github/watchers/fini-net/template-repo)

![template-repo banner](docs/template-repo-banner.png)

A good template for github repos with best practices adoption.

## Template Features

### GitHub Community Standards

- ✅ [All github community standards are checked off](https://github.com/fini-net/template-repo/community)
  - ✅ This [README](README) with badges and banner
  - ✅ [Contributor Covenant](https://www.contributor-covenant.org)-based Code of Conduct
  - ✅ [Contributing Guide](.github/CONTRIBUTING.md) includes a step-by-step guide to our [command line development process](.github/CONTRIBUTING.md#development-process)
  - ✅ [GPL2](LICENSE) license
  - ✅ [Security Policy](.github/SECURITY.md)
  - ✅ [Issue Templates](.github/ISSUE_TEMPLATE/)
  - ✅ [PR Template](.github/pull_request_template.md)
- ✅ [gitattributes](.gitattributes) based on [gitattributes](https://github.com/gitattributes/gitattributes)
- ✅ [gitignore](.gitignore) with comments
- ✅ [CODEOWNERS](.github/CODEOWNERS) that is self-documented

### Modular Justfile Architecture

The [justfile](justfile) imports 11 modules from the [.just/](.just/) directory for a clean, maintainable workflow:

- ✅ [gh-process.just](.just/gh-process.just) - Complete PR lifecycle automation with smart check polling and AI review integration
- ✅ [compliance.just](.just/compliance.just) - Repository health checks validating all GitHub community standards and branch protection
- ✅ [shellcheck.just](.just/shellcheck.just) - Bash script linting that extracts and validates all scripts in just recipes
- ✅ [cue-verify.just](.just/cue-verify.just) - Three-stage validation of [.repo.toml](.repo.toml) structure, flags, and GitHub sync
- ✅ [claude.just](.just/claude.just) - Claude Code permission management with canonical sorting and structure validation
- ✅ [copilot.just](.just/copilot.just) - Interactive Copilot suggestion picker, review refresh, and backup/rollback for applied suggestions
- ✅ [repo-toml.just](.just/repo-toml.just) - Metadata extraction that generates shell variables from repository configuration
- ✅ [template-sync.just](.just/template-sync.just) - Safe template updates preserving local customizations via multi-version checksums
- ✅ [testing.just](.just/testing.just) - Automated test recipes for PR body logic and template sync functionality
- ✅ [clean-template.just](.just/clean-template.just) - Strips template documentation and files for new repos
- ✅ [pr-hook.just](.just/pr-hook.just) - Optional pre-PR hooks for project-specific automation

### Repository Metadata System

- ✅ [.repo.toml](.repo.toml) - Centralized configuration with description, topics, URLs, and feature flags
- ✅ [Cue schema validation](docs/repo-toml.cue) - Three-stage verification checks structure, validates flags against actual files, and syncs GitHub metadata
- ✅ Automatic shell variable generation - The `repo_toml_generate` recipe exports TOML data as sourceable bash variables
- ✅ GitHub metadata synchronization - `cue-sync-from-github` pulls description and topics from GitHub API

### GitHub Actions

Thirteen workflows handle automation and quality, all hardened with [StepSecurity Harden-Runner](https://github.com/step-security/harden-runner) to prevent supply chain attacks:

- ✅ [Auto-assign](.github/workflows/auto-assign.yml) - Automatically assigns issues and PRs to maintainers
- ✅ [Checkov](.github/workflows/checkov.yml) - Security scanning for GitHub Actions workflows with SARIF output
- ✅ [Markdownlint](.github/workflows/markdownlint.yml) - Enforces markdown standards across all docs
- ✅ [Actionlint](.github/workflows/actionlint.yml) - Lints GitHub Actions workflow files
- ✅ [Zizmor](.github/workflows/zizmor.yml) - Static security analysis for GitHub Actions workflows
- ✅ [Claude mention integration](.github/workflows/claude.yml) - Mentions Claude AI when appropriate
- ✅ [Claude Code review](.github/workflows/claude-code-review.yml) - AI-powered code review automation
- ✅ [Cue verification](.github/workflows/cue-verify.yml) - Validates `.repo.toml` format and flags
- ✅ [Dependency Review](.github/workflows/dependency-review.yml) - Scans PRs for vulnerable dependency versions
- ✅ [OpenSSF Scorecard](.github/workflows/scorecards.yml) - Automated security posture assessment with badge
- ✅ [Checksums Verification](.github/workflows/checksums-verify.yml) - Verifies CHECKSUMS.json matches all tracked files
- ✅ [PR Body Tests](.github/workflows/pr-body-tests.yml) - Tests PR body update logic on every PR
- ✅ [Template Sync Tests](.github/workflows/template-sync.yml) - Tests template synchronization system

### AI-Enhanced Development

- ✅ Conditional AI review display - After PR checks complete, shows review comments based on `.repo.toml` flags
- ✅ GitHub Copilot review integration - Enable/disable with `copilot-review` flag
  - Interactive suggestion picker (`just copilot_pick`) with diff preview and one-key apply
  - Review refresh (`just copilot_refresh`) with gum spin progress and completion detection
  - Backup and rollback (`just copilot_rollback`) for safely reverting applied Copilot suggestions
- ✅ Claude Code review integration - Enable/disable with `claude-review` flag
- ✅ Smart polling system - Waits up to 30 seconds for checks to start, then polls every 5 seconds for faster feedback

### Automated Testing

- ✅ [PR body update tests](.just/lib/pr_body_test.sh) - Validates PR description generation logic with fixture-based test cases
- ✅ [Template sync tests](.just/lib/template_sync_test.sh) - Tests safe template update system with fixture scenarios
- ✅ [Shared utility library](.just/lib/common.sh) - Cross-platform checksum computation used by template sync

### Additional Features

- ✅ [Priority labels](https://github.com/fini-net/template-repo/labels) - Extra issue labels for better organization
- ✅ [Prerequisites installation](.just/lib/install-prerequisites.sh) - Script to install required tools
- ✅ [Pre-commit hooks](.pre-commit-config.yaml) - Enforces code quality and formatting before commits
- ✅ Release automation - `just release <version>` creates GitHub releases with auto-generated notes and age monitoring

## Usage

1. To use this template, you can create a new repository by clicking on "Use this
  template" button.
1. Remember to replace any `chicks-net`, `fini-net`, and `template-repo` references
  with the right values for your project.  (Github templates do not offer
  variable substitution, but we still have to call them templates for some reason.)
1. Ditch the "Template Status", "Usage", and "Kudos" sections in the `README.md`.
  `just clean_template` will give you a clean `/README.md`, and remove other files that are not required.

[Here is a nice checklist](https://github.com/jlcanovas/gh-best-practices-template/blob/main/guidelines.md)
of things to consider with a new repo.

## Keeping Your Derived Repo Up-to-Date

Pull updates to `.just/` modules from template-repo:

```bash
just update_from_template
```

Only unmodified files are updated. Local customizations are preserved.

Preview changes:

```bash
just checksums_verify              # Check which files would update
just checksums_diff .just/gh-process.just  # See specific changes
```

The update system uses multi-version checksum tracking to safely identify which files match known template versions. Files with local modifications are skipped and reported.

## Contributing

- [Code of Conduct](.github/CODE_OF_CONDUCT.md)
- [Contributing Guide](.github/CONTRIBUTING.md) includes a step-by-step guide to our
  [development process](.github/CONTRIBUTING.md#development-process).

## Support & Security

- [Getting Support](.github/SUPPORT.md)
- [Security Policy](.github/SECURITY.md)

## License

I went with the [GPL2 license](LICENSE), but the MIT license is also worth considering.

## Other good template repos on github

- Jose Gracia Berenguer did a great job with their
  [project-template](https://github.com/Josee9988/project-template)
  repo.  This looks like a student project, but it is one of the best
  templates I've found on github.
- [Cookiecutter Data Science](https://github.com/drivendataorg/cookiecutter-data-science)
  is cool, but it isn't actually a template repo.
- [gh-best-practices-template](https://github.com/jlcanovas/gh-best-practices-template)
  is doing great at checking off all of the boxes.  They've including funding and citations
  which I haven't tried yet.  I'm not a fan of how all of the Markdown files are in the
  root directory.  I definitely prefer stuffing those under `/.github` for a cleaner
  root directory.

## Thanks

- I've really enjoyed building projects with [just](https://just.systems/man/en/).
- The [GitHub CLI](https://cli.github.com/) makes browser-free workflows not only
  possible, but fun.
