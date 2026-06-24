# testing.just - Test recipes for template-repo
#
# This module provides testing recipes for the repository

# test PR body update logic
[group('Testing/Automation')]
pr_body_test:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "{{BLUE}}Testing PR body update logic...{{NORMAL}}"

    if .just/lib/pr_body_test.sh; then
        echo "{{GREEN}}All PR body tests passed!{{NORMAL}}"
    else
        echo "{{RED}}Some PR body tests failed{{NORMAL}}"
        exit 1
    fi

# test cue-sync-from-github awk logic (missing/commented keys in [about])
[group('Testing/Automation')]
cue_sync_test:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "{{BLUE}}Testing cue-sync-from-github awk logic...{{NORMAL}}"

    if .just/lib/cue_sync_test.sh; then
        echo "{{GREEN}}All cue-sync tests passed!{{NORMAL}}"
    else
        echo "{{RED}}Some cue-sync tests failed{{NORMAL}}"
        exit 1
    fi
