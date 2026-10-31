# .just/clean-template.just

# clean debris out of template
[group('Utility')]
clean_template: _clean_readme _clean_repo_toml _remove_template_files

# generate a clean README
[group('Utility')]
[no-cd]
_clean_readme: _on_a_branch
    #!/usr/bin/env bash
    set -euo pipefail # strict mode without tracing

    # Shared org/repo extraction (#420). The previous inline sed produced
    # an empty org for HTTPS remotes, which silently broke the README
    # badges; the helper handles SSH and HTTPS alike.
    source .just/lib/repo_urls.sh
    if ! GITHUB_ORG_REPO=$(origin_org_repo); then
        echo "{{RED}}Error: cannot determine org/repo from the git origin remote{{NORMAL}}"
        exit 1
    fi
    GITHUB_ORG=$(echo "$GITHUB_ORG_REPO" | cut -d' ' -f1)
    GITHUB_REPO=$(echo "$GITHUB_ORG_REPO" | cut -d' ' -f2)
    echo "org={{BLUE}}$GITHUB_ORG{{NORMAL}}"

    echo "repo={{BLUE}}$GITHUB_REPO{{NORMAL}}"

    cat > README.md << END_OF_HEREDOC
    # ${GITHUB_REPO}

    ![GitHub Issues](https://img.shields.io/github/issues/${GITHUB_ORG}/${GITHUB_REPO})
    ![GitHub Pull Requests](https://img.shields.io/github/issues-pr/${GITHUB_ORG}/${GITHUB_REPO})
    ![GitHub License](https://img.shields.io/github/license/${GITHUB_ORG}/${GITHUB_REPO})
    ![GitHub watchers](https://img.shields.io/github/watchers/${GITHUB_ORG}/${GITHUB_REPO})

    A good starting place for something. (TODO)

    ## Contributing

    - [Code of Conduct](.github/CODE_OF_CONDUCT.md)
    - [Contributing Guide](.github/CONTRIBUTING.md) includes a step-by-step guide to our
        [development process](.github/CONTRIBUTING.md#development-process).

    ## Support & Security

    - [Getting Support](.github/SUPPORT.md)
    - [Security Policy](.github/SECURITY.md)
    END_OF_HEREDOC

# repoint .repo.toml [urls] at this repo (from the git origin remote) and
# sync its description/topics from GitHub. Must run before
# _remove_template_files, which deletes this file; clean_template's
# dependency order enforces that. Derived repos used to keep the
# template's URLs here, which made cue-sync-from-github fetch the
# template's metadata - silently, since cue-verify read the same stale
# URL. See #420.
[group('Utility')]
[no-cd]
_clean_repo_toml: _on_a_branch
    #!/usr/bin/env bash
    set -euo pipefail # strict mode without tracing

    source .just/lib/repo_urls.sh
    if ! GITHUB_ORG_REPO=$(origin_org_repo); then
        echo "{{RED}}Error: cannot determine org/repo from the git origin remote{{NORMAL}}"
        exit 1
    fi
    GITHUB_ORG=$(echo "$GITHUB_ORG_REPO" | cut -d' ' -f1)
    GITHUB_REPO=$(echo "$GITHUB_ORG_REPO" | cut -d' ' -f2)
    echo "org={{BLUE}}$GITHUB_ORG{{NORMAL}} repo={{BLUE}}$GITHUB_REPO{{NORMAL}}"

    if [[ ! -f .repo.toml ]]; then
        echo "{{YELLOW}}.repo.toml not found - skipping URL repoint{{NORMAL}}"
    else
        echo "{{BLUE}}Repointing .repo.toml [urls] at this repo...{{NORMAL}}"
        EXPECTED_WEB_URL="https://github.com/$GITHUB_ORG/$GITHUB_REPO"
        repointed_repo_toml .repo.toml "$GITHUB_ORG" "$GITHUB_REPO" > .repo.toml.tmp
        if ! grep -qF "web_url = \"$EXPECTED_WEB_URL\"" .repo.toml.tmp; then
            rm -f .repo.toml.tmp
            echo "{{RED}}Error: failed to repoint [urls] in .repo.toml{{NORMAL}}"
            exit 1
        fi
        mv .repo.toml.tmp .repo.toml

        cue vet .repo.toml docs/repo-toml.cue
    fi

    # A fresh repo has zero GitHub topics, but the CUE schema requires at
    # least one, so the sync below would fail cue vet and roll back. Seed
    # a placeholder topic so the first sync can pass; replace it with
    # real topics on GitHub and re-run 'just cue-sync-from-github'.
    if GH_DATA=$(gh api "repos/$GITHUB_ORG/$GITHUB_REPO" 2>/dev/null); then
        TOPIC_COUNT=$(echo "$GH_DATA" | jq -r '.topics | length')
        if [[ "$TOPIC_COUNT" -eq 0 ]]; then
            echo "{{YELLOW}}No GitHub topics - adding 'placeholder' topic{{NORMAL}}"
            if gh api -X PUT "repos/$GITHUB_ORG/$GITHUB_REPO/topics" -f 'names[]=placeholder' >/dev/null; then
                echo "{{YELLOW}}  Replace it with real topics on GitHub, then run 'just cue-sync-from-github'{{NORMAL}}"
            else
                echo "{{YELLOW}}Warning: could not add placeholder topic (gh api failed){{NORMAL}}"
            fi
        fi
    else
        echo "{{YELLOW}}Warning: cannot read GitHub topics - skipping placeholder topic step{{NORMAL}}"
    fi

    # Fill description and topics from this repo's real GitHub metadata.
    # Best-effort: a brand-new repo may have no GitHub description yet,
    # which the schema requires, so a failed sync warns instead of
    # failing the whole cleanup.
    echo "{{BLUE}}Syncing description and topics from GitHub...{{NORMAL}}"
    if ! just cue-sync-from-github; then
        echo "{{YELLOW}}Warning: metadata sync did not complete.{{NORMAL}}"
        echo "{{YELLOW}}  A brand-new repo usually needs a GitHub description first.{{NORMAL}}"
        echo "{{YELLOW}}  Set one on GitHub, then run: just cue-sync-from-github{{NORMAL}}"
    fi

# remove template-specific files
# NOTE: Files removed here must also be listed in CLEANED_FILES in .just/lib/generate_checksums.sh
[group('Utility')]
[no-cd]
_remove_template_files: _on_a_branch
    #!/usr/bin/env bash
    set -euo pipefail # strict mode without tracing

    echo "{{YELLOW}}Removing template-specific files...{{NORMAL}}"

    # Remove banner PNG if it exists
    if [[ -f "docs/template-repo-banner.png" ]]; then
        echo "Removing docs/template-repo-banner.png"
        rm -f "docs/template-repo-banner.png"
        # Remove docs directory if empty
        if [[ -d "docs" && -z "$(ls -A docs)" ]]; then
            echo "Removing empty docs directory"
            rmdir docs
        fi
    fi

    # Remove testing infrastructure
    if [[ -f ".just/testing.just" ]]; then
        echo "Removing .just/testing.just"
        rm -f ".just/testing.just"
    fi

    if [[ -d ".just/test" ]]; then
        echo "Removing .just/test directory"
        rm -rf ".just/test"
    fi

    if [[ -f ".github/workflows/pr-body-tests.yml" ]]; then
        echo "Removing .github/workflows/pr-body-tests.yml"
        rm -f ".github/workflows/pr-body-tests.yml"
    fi

    if [[ -f ".github/workflows/checksums-verify.yml" ]]; then
        echo "Removing .github/workflows/checksums-verify.yml"
        rm -f ".github/workflows/checksums-verify.yml"
    fi

    if [[ -f ".github/workflows/cue-sync-tests.yml" ]]; then
        echo "Removing .github/workflows/cue-sync-tests.yml"
        rm -f ".github/workflows/cue-sync-tests.yml"
    fi

    if [[ -f ".github/workflows/template-sync.yml" ]]; then
        echo "Removing .github/workflows/template-sync.yml"
        rm -f ".github/workflows/template-sync.yml"
    fi

    if [[ -f ".github/workflows/wait-for-copilot-tests.yml" ]]; then
        echo "Removing .github/workflows/wait-for-copilot-tests.yml"
        rm -f ".github/workflows/wait-for-copilot-tests.yml"
    fi

    # Remove test scripts
    if [[ -f ".just/lib/pr_body_test.sh" ]]; then
        echo "Removing .just/lib/pr_body_test.sh"
        rm -f ".just/lib/pr_body_test.sh"
    fi

    if [[ -f ".just/lib/template_sync_test.sh" ]]; then
        echo "Removing .just/lib/template_sync_test.sh"
        rm -f ".just/lib/template_sync_test.sh"
    fi

    if [[ -f ".just/lib/cue_sync_test.sh" ]]; then
        echo "Removing .just/lib/cue_sync_test.sh"
        rm -f ".just/lib/cue_sync_test.sh"
    fi

    if [[ -f ".just/lib/wait_for_copilot_test.sh" ]]; then
        echo "Removing .just/lib/wait_for_copilot_test.sh"
        rm -f ".just/lib/wait_for_copilot_test.sh"
    fi

    # Remove this cleanup script after use
    if [[ -f ".just/clean-template.just" ]]; then
        echo "Removing .just/clean-template.just"
        rm -f ".just/clean-template.just"
    fi

    if [[ -f "justfile" ]]; then
        if grep -q "import.*clean-template.just" justfile; then
            echo "Removing clean-template.just import from justfile"
            sed -i.tmp '/import.*clean-template.just/d' justfile
            rm -f justfile.tmp
        fi
    fi

    # Remove testing import from main justfile
    if [[ -f "justfile" ]]; then
        if grep -q "import.*testing.just" justfile; then
            echo "Removing testing.just import from justfile"
            sed -i.tmp '/import.*testing.just/d' justfile
            rm -f justfile.tmp
        fi
    fi

    echo "{{GREEN}}Template cleanup completed!{{NORMAL}}"
