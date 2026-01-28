# microsoft copilot justfile

# check out the RELEASE_NOTES.md for the detailed history of this file
# the README.md in this directory also might be useful to you

# Interactive Copilot suggestion picker
[group('Copilot')]
copilot_pick: _on_a_pull_request
    #!/usr/bin/env bash
    set -euo pipefail

    # Check if gum is installed
    if ! command -v gum &>/dev/null; then
        echo "{{RED}}gum is not installed{{NORMAL}}"
        echo "{{YELLOW}}Install with: brew install gum (macOS){{NORMAL}}"
        echo "{{YELLOW}}Or see: https://github.com/charmbracelet/gum{{NORMAL}}"
        exit 1
    fi

    # Check if jq is installed
    if ! command -v jq &>/dev/null; then
        echo "{{RED}}jq is not installed{{NORMAL}}"
        echo "{{YELLOW}}jq is required by gh CLI and should be installed{{NORMAL}}"
        echo "{{YELLOW}}Install with: brew install jq (macOS){{NORMAL}}"
        exit 1
    fi

    echo "🐈‍⬛😾 Fetching Copilot suggestions..."

    # Get PR metadata
    PR_META=$(gh pr view --json number,headRepository,headRepositoryOwner)
    PR_REPO_NAME=$(echo "$PR_META" | jq -r '.headRepository.name')
    PR_REPO_OWNER=$(echo "$PR_META" | jq -r '.headRepositoryOwner.login')
    PR_NUMBER=$(echo "$PR_META" | jq '.number')

    # Fetch Copilot comments
    copilot_comments=$(mktemp /tmp/justfile.XXXXXX)

    # Note: GraphQL limits - fetches last 20 reviews and first 100 comments per review
    # For most PRs this is sufficient, but very active PRs might have truncated results
    # shellcheck disable=SC2016
    gh api graphql \
        -F owner="$PR_REPO_OWNER" -F name="$PR_REPO_NAME" -F pr="$PR_NUMBER" \
        --jq '[ .data.repository.pullRequest.reviews.nodes.[] | select(.author.login=="copilot-pull-request-reviewer") | .comments.nodes.[] ]' \
        -f query='
        query($name: String!, $owner: String!, $pr: Int!) {
            repository(owner: $owner, name: $name) {
                pullRequest(number: $pr) {
                    reviews(last: 20) {
                        nodes {
                            author {
                                resourcePath
                                login
                            }
                            comments(first: 100) {
                                nodes {
                                    body
                                    path
                                    originalLine
                                }
                            }
                        }
                    }
                }
            }
        }
        ' > "$copilot_comments"

    # Check if we have comments
    COMMENT_COUNT=$(jq 'length' "$copilot_comments")

    if [[ "$COMMENT_COUNT" -eq 0 ]]; then
        echo "{{BLUE}}No Copilot suggestions found{{NORMAL}}"
        exit 0
    fi

    echo "{{GREEN}}Found $COMMENT_COUNT Copilot suggestions{{NORMAL}}"
    echo ""

    # Format suggestions for gum display
    suggestions_display=$(mktemp /tmp/justfile.XXXXXX)
    trap 'rm -f "$copilot_comments" "$suggestions_display"' EXIT

    # Create display format: "file:line - preview"
    jq -r '.[] | "\(.path):\(.originalLine) - \(.body | split("\n")[0] | .[0:80])"' \
        "$copilot_comments" > "$suggestions_display"

    # Interactive selection with gum
    selected=$(gum choose \
        --header="Select a Copilot suggestion to view (or Ctrl+C to exit):" \
        --height=15 \
        < "$suggestions_display" || true)

    if [[ -z "$selected" ]]; then
        echo "{{BLUE}}Selection cancelled{{NORMAL}}"
        exit 0
    fi

    # Extract line number from selection to match back to original comment
    line_num=$(echo "$selected" | cut -d':' -f2 | cut -d' ' -f1)

    # Validate line number is numeric
    if ! [[ "$line_num" =~ ^[0-9]+$ ]]; then
        echo "{{RED}}Error: Could not extract line number from selection{{NORMAL}}"
        exit 1
    fi

    echo ""
    jq -r --arg line "$line_num" '.[] | select(.originalLine == ($line | tonumber)) |
        "{{GREEN}}File:{{NORMAL}} \(.path)\n{{GREEN}}Line:{{NORMAL}} \(.originalLine)\n\n\(.body)"' \
        "$copilot_comments"

    rm -f "$copilot_comments" "$suggestions_display"

# Request a new Copilot review on current PR
[group('Copilot')]
copilot_refresh: _on_a_pull_request
    #!/usr/bin/env bash
    set -euo pipefail

    # Check if jq is installed
    if ! command -v jq &>/dev/null; then
        echo "{{RED}}jq is not installed{{NORMAL}}"
        echo "{{YELLOW}}jq is required by gh CLI and should be installed{{NORMAL}}"
        echo "{{YELLOW}}Install with: brew install jq (macOS){{NORMAL}}"
        exit 1
    fi

    # Get PR metadata
    PR_META=$(gh pr view --json number,headRepository,headRepositoryOwner)
    PR_REPO_NAME=$(echo "$PR_META" | jq -r '.headRepository.name')
    PR_REPO_OWNER=$(echo "$PR_META" | jq -r '.headRepositoryOwner.login')
    PR_NUMBER=$(echo "$PR_META" | jq -r '.number')
    REPO="${PR_REPO_OWNER}/${PR_REPO_NAME}"

    # Request Copilot review
    echo "🐈‍⬛ Requesting Copilot review on PR #${PR_NUMBER}..."

    if gh api --method POST "/repos/${REPO}/pulls/${PR_NUMBER}/requested_reviewers" \
        -f "reviewers[]=copilot-pull-request-reviewer[bot]" &>/dev/null; then
        echo "{{GREEN}}✓ Copilot review requested successfully{{NORMAL}}"
    else
        echo "{{RED}}✗ Failed to request Copilot review{{NORMAL}}"
        echo "{{YELLOW}}This may indicate:{{NORMAL}}"
        echo "  - Copilot is not enabled for this repository/organization"
        echo "  - You don't have permission to request reviewers"
        exit 1
    fi

    # Wait for review completion
    MAX_WAIT=45
    POLL_INTERVAL=3

    poll_for_review() {
        elapsed=0
        while (( elapsed < MAX_WAIT )); do
            # Check for Copilot review using GraphQL
            # shellcheck disable=SC2016
            copilot_review=$(gh api graphql \
                -F owner="$PR_REPO_OWNER" -F name="$PR_REPO_NAME" -F pr="$PR_NUMBER" \
                --jq '[ .data.repository.pullRequest.reviews.nodes.[] | select(.author.login=="copilot-pull-request-reviewer") | .comments.nodes.[] ] | length' \
                -f query='
                query($name: String!, $owner: String!, $pr: Int!) {
                    repository(owner: $owner, name: $name) {
                        pullRequest(number: $pr) {
                            reviews(last: 20) {
                                nodes {
                                    author {
                                        login
                                    }
                                    comments(first: 100) {
                                        nodes {
                                            body
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                ' 2>/dev/null || echo "0")

            if [[ "$copilot_review" != "0" ]] && [[ -n "$copilot_review" ]]; then
                echo "{{GREEN}}Review detected after ${elapsed}s{{NORMAL}}"
                return 0
            fi

            sleep $POLL_INTERVAL
            elapsed=$((elapsed + POLL_INTERVAL))

            # Only show dots if not using gum
            if [ "${USING_GUM:-0}" = "0" ]; then
                echo -n "."
            fi
        done

        echo ""
        echo "{{YELLOW}}Review not detected after ${MAX_WAIT}s - it may still be processing{{NORMAL}}"
        return 1
    }

    # Use gum spin if available, otherwise fall back to simple progress
    if command -v gum &> /dev/null; then
        USING_GUM=1 gum spin --spinner dot --title "Waiting for Copilot review..." -- bash -c "MAX_WAIT=$MAX_WAIT; POLL_INTERVAL=$POLL_INTERVAL; PR_REPO_OWNER='$PR_REPO_OWNER'; PR_REPO_NAME='$PR_REPO_NAME'; PR_NUMBER='$PR_NUMBER'; $(declare -f poll_for_review); poll_for_review"
        review_ready=$?
    else
        echo "{{BLUE}}Waiting for Copilot review...{{NORMAL}}"
        USING_GUM=0 poll_for_review
        review_ready=$?
    fi

    if [[ $review_ready -eq 0 ]]; then
        echo ""
        echo "{{GREEN}}Review complete!{{NORMAL}}"

        # Count suggestions using GraphQL
        # shellcheck disable=SC2016
        COPILOT_COUNT=$(gh api graphql \
            -F owner="$PR_REPO_OWNER" -F name="$PR_REPO_NAME" -F pr="$PR_NUMBER" \
            --jq '[ .data.repository.pullRequest.reviews.nodes.[] | select(.author.login=="copilot-pull-request-reviewer") | .comments.nodes.[] ] | length' \
            -f query='
            query($name: String!, $owner: String!, $pr: Int!) {
                repository(owner: $owner, name: $name) {
                    pullRequest(number: $pr) {
                        reviews(last: 20) {
                            nodes {
                                author {
                                    login
                                }
                                comments(first: 100) {
                                    nodes {
                                        body
                                        path
                                        originalLine
                                    }
                                }
                            }
                        }
                    }
                }
            }
            ')

        if [[ $COPILOT_COUNT -gt 0 ]]; then
            echo "🐈‍⬛ Found ${COPILOT_COUNT} Copilot suggestions"
            echo ""
            echo "To browse interactively:"
            echo "  {{GREEN}}just copilot_pick{{NORMAL}}"
        else
            echo "🐈‍⬛ No suggestions - looks good!"
        fi
    else
        echo "{{YELLOW}}Review may still be processing. Try:{{NORMAL}}"
        echo "  {{GREEN}}just copilot_pick{{NORMAL}} (to view suggestions when ready)"
    fi
