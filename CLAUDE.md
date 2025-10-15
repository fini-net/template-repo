# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is a GitHub repository template that implements best practices for open source projects. It's designed to be cloned and customized for new repositories. The template includes GitHub community standards compliance, automated workflows, and a command-line driven development process.

## Development Workflow

This repo uses `just` (command runner) for all development tasks. The workflow is entirely command-line based using `just` and the GitHub CLI (`gh`).

### Standard development cycle

1. `just branch <name>` - Create a new feature branch (format: `$USER/YYYY-MM-DD-<name>`)
2. Make changes and commit (last commit message becomes PR title)
3. `just pr` - Create PR, push changes, and watch checks (waits 10s for GitHub API)
4. `just merge` - Squash merge PR, delete branch, return to main, and pull latest
5. `just sync` - Return to main branch and pull latest (escape hatch)

### Additional commands

- `just` or `just list` - Show all available recipes
- `just prweb` - Open current PR in browser
- `just release <version>` - Create a GitHub release with auto-generated notes
- `just clean_readme` - Generate a clean README from template (strips template documentation)
- `just compliance_check` - Run custom repo compliance checks
- `just utcdate` - Print UTC date in ISO format (used in branch names)

### Git aliases used

The justfile assumes these git aliases exist:

- `git stp` - Show status (likely `status --short` or similar)
- `git pushup` - Push and set upstream tracking
- `git co` - Checkout

## Architecture

### Modular justfile structure

The main `justfile` imports two modules:

- `.just/compliance.just` - Custom compliance checks for repo health
- `.just/gh-process.just` - Git/GitHub workflow automation

### GitHub Actions

Four workflows run on PRs and pushes to main:

- **markdownlint** - Enforces markdown standards using `markdownlint-cli2`
- **checkov** - Security scanning for GitHub Actions
- **actionlint** - Lints GitHub Actions workflow files
- **auto-assign** - Automatically assigns issues

### Markdown linting

Configuration in `.markdownlint.yml`:

- MD013 (line length) is disabled
- MD041 (first line h1) is disabled
- MD042 (no empty links) is disabled
- MD004 (list style) enforces dashes
- MD010 (tabs) ignores code blocks

Run locally: `markdownlint-cli2 **/*.md`

## Template customization

When using this template for a new project, search and replace:

- `fini-net` → your GitHub org
- `template-repo` → your repo name
- `chicks-net` → your references

Run `just clean_readme` to strip template documentation from README.
