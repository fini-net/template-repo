# our own repo compliance check
[group('Testing/Compliance')]
compliance_check:
    #!/usr/bin/env bash
    set -euo pipefail # strict mode without tracing

    echo "{{BLUE}}Chicks' repo compliance check...{{NORMAL}}"

    if [[ -e README.md ]]; then
        echo "{{GREEN}}You have a README.md, thank you.{{NORMAL}}"
    else
        echo "{{RED}}You do NOT have a README.md, hmmmm, why is this repo here?{{NORMAL}}"
    fi

    if [[ -e LICENSE ]]; then
        echo "{{GREEN}}[gh] You have a license, good for you.{{NORMAL}}"
    else
        echo "{{RED}}[gh] You do NOT have a license, are you feeling ok?{{NORMAL}}"
    fi

    if [[ -e .github/CODE_OF_CONDUCT.md ]]; then
        echo "{{GREEN}}[gh] You have a Code of Conduct, respect.{{NORMAL}}"
    else
        echo "{{RED}}[gh] You do NOT have a Code of Conduct.  So anything goes around here?{{NORMAL}}"
    fi

    if [[ -e .github/CONTRIBUTING.md ]]; then
        echo "{{GREEN}}[gh] You have a Contributing Guide, how giving.{{NORMAL}}"
    else
        echo "{{RED}}[gh] You do NOT have a Contributing Guide.  Hopefully they'll figure it out on their own.{{NORMAL}}"
    fi

    if [[ -e .github/SECURITY.md ]]; then
        echo "{{GREEN}}[gh] You have a Security Guide, very comforting.{{NORMAL}}"
    else
        echo "{{RED}}[gh] You do NOT have a Security Guide.  Don't call the cops.{{NORMAL}}"
    fi

    if [[ -e .github/pull_request_template.md ]]; then
        echo "{{GREEN}}[gh] You have a pull request template, not too pushy.{{NORMAL}}"
    else
        echo "{{RED}}[gh] You do NOT have a pull request template.  Prepare for anything.{{NORMAL}}"
    fi

    if [[ -d .github/ISSUE_TEMPLATE ]]; then
        echo "{{GREEN}}[gh] You have Issue Templates, life is good.{{NORMAL}}"
    else
        echo "{{RED}}[gh] You do NOT have Issue Templates.  I must take issue with that.{{NORMAL}}"
    fi

    if [[ $(gh repo view --json description | jq -r '.description' | wc -c) -gt 16 ]]; then
        echo "{{GREEN}}[gh] You have a repo description, more evidence that you are undescribable.{{NORMAL}}"
    else
        echo "{{RED}}[gh] You do NOT have a repo description, can you write a word or two please?{{NORMAL}}"
    fi

    # github also checks for something about the repo admins

    if [[ -e .github/CODEOWNERS ]]; then
        echo "{{GREEN}}You have a CODEOWNERS file, in DEED.{{NORMAL}}"
    else
        echo "{{RED}}You do NOT have a CODEOWNERS file.  Does anyone want to make a claim?{{NORMAL}}"
    fi

    if [[ -e .gitignore ]]; then
        echo "{{GREEN}}You have a .gitignore file, so there will be less debris in your future.{{NORMAL}}"
    else
        echo "{{RED}}You do NOT have a .gitignore file.  I expect you to keep ignoring my advice!{{NORMAL}}"
    fi

    if [[ -e .gitattributes ]]; then
        echo "{{GREEN}}You have a .gitattributes file, keeping metadata and line endings clean too.{{NORMAL}}"
    else
        echo "{{RED}}You do NOT have a .gitattributes file.  Did you hear what happens when binaries and text files get together?{{NORMAL}}"
    fi

    if [[ -e justfile ]]; then
        echo "{{GREEN}}You have a {{BLUE}}justfile{{GREEN}}, spreading justice and automation a little further.{{NORMAL}}"
    else
        echo "{{RED}}You do NOT have a justfile.  Feeling the FOMO yet?{{NORMAL}}"
        echo "{{RED}}And this should not be possible.  Tell me how you got here.{{NORMAL}}"
    fi

    if [[ -e .editorconfig ]]; then
        echo "{{GREEN}}You have an {{BLUE}}.editorconfig{{GREEN}}, keeping tabs and spaces segregated.{{NORMAL}}"
    else
        echo "{{RED}}You do NOT have an .editorconfig.  Will your world explode when the tabs and spaces get together?{{NORMAL}}"
    fi

    # Check for branch protection on main branch (repo-level or org-level rulesets)
    if gh api 'repos/{owner}/{repo}/rulesets' --jq '.[] | select(.enforcement == "active" and .target == "branch")' | grep -q .; then
        echo "{{GREEN}}[gh] You have branch protection enabled, keeping the main branch safe from accidents.{{NORMAL}}"
    else
        echo "{{RED}}[gh] You do NOT have branch protection enabled.  Living dangerously, are we?{{NORMAL}}"
    fi

    # --- OpenSSF Scorecard-aligned checks (https://github.com/ossf/scorecard) ---
    # Shell heuristics, not a faithful Scorecard reimplementation, and purely
    # informational like everything above.  Only File-Existence-style heuristics;
    # requires `file` for the Binary-Artifacts check.

    if command -v file >/dev/null 2>&1; then
        binaries=$(git ls-files -z | xargs -0 file -- 2>/dev/null | grep -E 'ELF|Mach-O|PE32|MS Windows|JPEG|PNG|GIF|Web/P|PDF' | cut -d: -f1 || true)
        large_blobs=$(git ls-files -z | xargs -0 wc -c 2>/dev/null | awk '$1 > 1000000 && $2 != "total" {found++} END {print found+0}')
        if [[ -z "$binaries" && "${large_blobs:-0}" -eq 0 ]]; then
            echo "{{GREEN}}[openssf] No binary artifacts in git, your repo is surgically clean.{{NORMAL}}"
        else
            echo "{{RED}}[openssf] Binary artifacts committed: $(echo "$binaries" | tr '\n' ' ') plus $large_blobs blob(s) over 1MB.  Git is not a dumpster.{{NORMAL}}"
        fi
    else
        echo "{{BLUE}}[openssf] 'file' command not found, skipping the Binary-Artifacts check.  No judgment.{{NORMAL}}"
    fi

    # CI-Tests: workflows that actually run tests
    test_cmds='npm test|npm run test|pytest|go test|cargo test|make test|bazel test|mvn test|gradle test|tox|rspec|jest|vitest|deno test|just [a-z0-9_-]*test'
    if [[ -d .github/workflows ]] && grep -lrE "$test_cmds" .github/workflows >/dev/null 2>&1; then
        echo "{{GREEN}}[openssf] CI runs tests on every push, machines grinding so humans can look away.{{NORMAL}}"
    else
        echo "{{RED}}[openssf] No workflow found that runs tests.  Testing is for people who plan to be around later.{{NORMAL}}"
    fi

    # Code-Review: ruleset on the default branch requiring pull request reviews
    # (overlaps the [gh] community-standards branch protection check above)
    rulesets=$(gh api 'repos/{owner}/{repo}/rulesets' --jq '.[] | select(.enforcement == "active" and .target == "branch") | .id' 2>/dev/null || true)
    code_review_ok=false
    for id in $rulesets; do
        if gh api "repos/{owner}/{repo}/rulesets/$id" --jq '.rules[] | select(.type == "pull_request") | .parameters.required_approving_review_count > 0 or .parameters.dismiss_stale_reviews_on_push or .parameters.require_code_owner_review' 2>/dev/null | grep -q true; then
            code_review_ok=true
            break
        fi
    done
    if [[ "$code_review_ok" == "true" ]]; then
        echo "{{GREEN}}[gh,openssf] Branch rulesets require pull request reviews, code never travels alone.{{NORMAL}}"
    else
        echo "{{RED}}[gh,openssf] No ruleset found requiring pull request reviews.  Somewhere, code walks the streets unsupervised.{{NORMAL}}"
    fi

    # Dangerous-Workflow: pull_request_target with secrets, or sudo in workflows
    prt_wfs=""
    sudo_wfs=""
    dangerous=""
    if [[ -d .github/workflows ]]; then
        prt_wfs=$(grep -l 'pull_request_target' .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null || true)
        if [[ -n "$prt_wfs" ]]; then
            dangerous=$(echo "$prt_wfs" | xargs grep -l 'secrets\.' 2>/dev/null || true)
        else
            dangerous=""
        fi
        sudo_wfs=$(grep -l 'sudo' .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null || true)
    fi
    if [[ -z "$dangerous" && -z "$sudo_wfs" ]]; then
        echo "{{GREEN}}[openssf] No dangerous workflow patterns, your automations mind their manners.{{NORMAL}}"
    else
        echo "{{RED}}[openssf] Dangerous workflow pattern(s) found: pull_request_target with secrets: ${dangerous:-none}; sudo: ${sudo_wfs:-none}.  Handle with gloves.{{NORMAL}}"
    fi

    # Dependency-Update-Tool: dependabot or renovate config
    if [[ -e .github/dependabot.yml || -e .github/renovate.json || -e .github/renovate.json5 || -e renovate.json || -e renovate.json5 ]]; then
        echo "{{GREEN}}[openssf] Automated dependency updates configured, your dependencies get fresh air and exercise.{{NORMAL}}"
    else
        echo "{{RED}}[openssf] No dependabot.yml or renovate config.  Your dependencies are on their own.{{NORMAL}}"
    fi

    # Maintained: some commit activity in the last 90 days
    last_commit=$(git log -1 --format=%ct 2>/dev/null || echo 0)
    if [[ "$last_commit" -gt $(( $(date +%s) - 90 * 86400 )) ]]; then
        echo "{{GREEN}}[openssf] Repo has recent activity, somebody actually lives here.{{NORMAL}}"
    else
        echo "{{RED}}[openssf] No commits in over 90 days, the cobwebs are collecting interest{{NORMAL}}"
    fi

    # Pinned-Dependencies: workflow 'uses:' lines pinned to a full SHA (or container digest)
    unpinned=""
    if [[ -d .github/workflows ]]; then
        # repo-local actions (uses: ./path) need no pin - exclude them
        unpinned=$(grep -hE '^\s*uses:' .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null | grep -v 'uses:\s*\.\/' | grep -vE '@([0-9a-fA-F]{40}|sha256:[0-9a-f]{64})' || true)
    fi
    if [[ -z "$unpinned" ]]; then
        echo "{{GREEN}}[openssf] All workflow actions are SHA-pinned, no tag-surfing for supply-chain pirates.{{NORMAL}}"
    else
        echo "{{RED}}[openssf] Unpinned actions found: $(echo "$unpinned" | tr -d ' ' | tr '\n' ';' ).  Pin them to a full SHA or the mermaid songs will come for you.{{NORMAL}}"
    fi

    # Packaging: workflows that publish or release artifacts
    if [[ -d .github/workflows ]] && grep -lrEi 'npm publish|gh release|docker push|twine upload|cargo publish|gem push|nuget push|mvn deploy' .github/workflows >/dev/null 2>&1; then
        echo "{{GREEN}}[openssf] Workflow publishes to a registry/release channel, your code gets out in the world (licensed, of course).{{NORMAL}}"
    else
        echo "{{RED}}[openssf] No publishing workflow detected.  Alpha geeks everywhere are disappointed.{{NORMAL}}"
    fi

    # SAST: static analysis workflow presence
    if [[ -d .github/workflows ]] && grep -lrEi 'codeql|sonarcloud|sonarqube|semgrep' .github/workflows >/dev/null 2>&1; then
        echo "{{GREEN}}[openssf] SAST workflow found, the machines are reading your code so the hackers don't have to.{{NORMAL}}"
    else
        echo "{{RED}}[openssf] No SAST workflow (CodeQL, SonarCloud, Semgrep, etc.) found.  Vulnerabilities left to their own devices.{{NORMAL}}"
    fi

    # Signed-Releases: release assets with cryptographic signatures
    signed_assets=$(gh api 'repos/{owner}/{repo}/releases?per_page=10' --jq '.[].assets[].name' 2>/dev/null | grep -Ei '\.(sig|asc|pem|intoto\.jsonl)$' || true)
    release_count=$(gh api 'repos/{owner}/{repo}/releases?per_page=10' --jq 'length' 2>/dev/null || echo 0)
    if [[ -n "$signed_assets" ]]; then
        echo "{{GREEN}}[openssf] Latest releases include signed assets, tamper-proofing for the paranoid and prudent.{{NORMAL}}"
    elif [[ "${release_count:-0}" -eq 0 ]]; then
        echo "{{BLUE}}[openssf] No releases found, skipping the signed-release check.  Nothing to sign yet.{{NORMAL}}"
    else
        echo "{{RED}}[openssf] Releases exist but none of the latest ones have signed assets (.sig, .asc, .pem, .intoto.jsonl).  Unsigned releases, eh?  Bold.{{NORMAL}}"
    fi

    # Token-Permissions: workflows declaring a top-level permissions block
    missing_perms=""
    if [[ -d .github/workflows ]]; then
        missing_perms=$(grep -LE '^\s*permissions:' .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null || true)
    fi
    if [[ -z "$missing_perms" ]]; then
        echo "{{GREEN}}[openssf] All workflows declare a top-level permissions block, least privilege is the best privilege.{{NORMAL}}"
    else
        echo "{{RED}}[openssf] Workflow(s) missing top-level 'permissions:' block: $(echo "$missing_perms" | tr '\n' ' ').  Grant them a trust fall, why don't you.{{NORMAL}}"
    fi
