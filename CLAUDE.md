# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is a GitHub repository template that implements best practices for open source projects. It's designed to be cloned and customized for new repositories. The template includes GitHub community standards compliance, automated workflows, and a command-line driven development process.

## Development Workflow

This repo uses `just` (command runner) for all development tasks. The workflow is entirely command-line based using `just` and the GitHub CLI (`gh`).

### Standard development cycle

1. `just branch <name>` - Create a new feature branch (format: `$USER/YYYY-MM-DD-<name>`)
2. Make changes and commit (last commit message becomes PR title)
3. `just pr` - Create PR, push changes, and watch checks (waits 8s for GitHub API)
4. `just merge` - Squash merge PR, delete branch, return to main, and pull latest
5. `just sync` - Return to main branch and pull latest (escape hatch)

### Additional commands

- `just` or `just list` - Show all available recipes
- `just prweb` - Open current PR in browser
- `just release <version>` - Create a GitHub release with auto-generated notes
- `just clean_readme` - Generate a clean README from template (strips template documentation)
- `just compliance_check` - Run custom repo compliance checks
- `just shellcheck` - Run shellcheck on all bash scripts in just recipes
- `just utcdate` - Print UTC date in ISO format (used in branch names)

## Architecture

### Modular justfile structure

The main `justfile` imports four modules:

- `.just/compliance.just` - Custom compliance checks for repo health (validates all GitHub community standards)
- `.just/gh-process.just` - Git/GitHub workflow automation (core PR lifecycle)
- `.just/pr-hook.just` - Optional pre-PR hooks for project-specific automation (e.g., Hugo rebuilds)
- `.just/shellcheck.just` - Shellcheck linting for bash scripts in just recipes

### Git/GitHub workflow details

The `.just/gh-process.just` module implements the entire PR lifecycle:

- **Branch creation** - Dated branches with `$USER/YYYY-MM-DD-<name>` format
- **PR creation** - First commit message becomes PR title, all commits listed in body
- **Sanity checks** - Prevents empty PRs, enforces branch strategy via hidden recipes (`_on_a_branch`, `_has_commits`, `_main_branch`)
- **AI integration** - After PR checks complete, displays GitHub Copilot and Claude Code review comments in terminal
- **Merge automation** - Squash merge, delete remote branch, return to main, pull latest

### Shellcheck integration

The `.just/shellcheck.just` module extracts and validates bash scripts:

- **Script extraction** - Uses awk to identify recipes with bash shebangs (`#!/usr/bin/env bash` or `#!/bin/bash`)
- **Automatic detection** - Scans all justfiles in repo (main `justfile` and `.just/*.just`)
- **Temporary file handling** - Creates temporary files for each script and runs shellcheck with `-x -s bash` flags
- **Detailed reporting** - Shows which file and recipe each issue is in, with colored output
- **Exit code** - Returns 1 if issues found, 0 if all scripts pass

### GitHub Actions

Six workflows run on PRs and pushes to main:

- **markdownlint** - Enforces markdown standards using `markdownlint-cli2`
- **checkov** - Security scanning for GitHub Actions (continues on error, outputs SARIF)
- **actionlint** - Lints GitHub Actions workflow files
- **auto-assign** - Automatically assigns issues/PRs to `chicks-net`
- **claude-code-review** - Claude AI review automation
- **claude** - Additional Claude integration

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
- `chicks-net` → your references (especially in `.github/workflows/auto-assign.yml`)

Run `just clean_readme` to strip template documentation from README.

## Important implementation notes

- All git commands in `.just/gh-process.just` use standard git (no aliases required)
- The `pr` recipe runs optional pre-PR hooks if `.just/pr-hook.just` exists
- PR checks poll every 5 seconds for faster feedback
- Release notes for workflow changes are tracked in `.just/RELEASE_NOTES.md`
- The `.just` directory contains modular just recipes that can be copied to other projects for updates
- just catches errors from commands when the recipe isn't a "#!" form that runs another scripting engine
- just colors come from built-in constants <https://just.systems/man/en/constants.html>
