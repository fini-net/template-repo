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

# test template sync logic
[group('Testing/Automation')]
template_sync_test:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "{{BLUE}}Testing template sync logic...{{NORMAL}}"

    if .just/lib/template_sync_test.sh; then
        echo "{{GREEN}}All template sync tests passed!{{NORMAL}}"
    else
        echo "{{RED}}Some template sync tests failed{{NORMAL}}"
        exit 1
    fi
