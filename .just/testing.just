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

# test repo_urls.sh extraction, mismatch classification, and [urls]
# repointing - including the #420 sync-refusal guard, driven through the
# real cue-sync-from-github recipe in a shimmed workspace
[group('Testing/Automation')]
repo_urls_test:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "{{BLUE}}Testing repo_urls extraction and sync guards...{{NORMAL}}"

    if .just/lib/repo_urls_test.sh; then
        echo "{{GREEN}}All repo_urls tests passed!{{NORMAL}}"
    else
        echo "{{RED}}Some repo_urls tests failed{{NORMAL}}"
        exit 1
    fi

# test the shared Copilot-wait state machine (mocked gh/sleep, fixtures)
[group('Testing/Automation')]
wait_for_copilot_test:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "{{BLUE}}Testing wait_for_copilot state machine...{{NORMAL}}"

    if .just/lib/wait_for_copilot_test.sh; then
        echo "{{GREEN}}All wait_for_copilot tests passed!{{NORMAL}}"
    else
        echo "{{RED}}Some wait_for_copilot tests failed{{NORMAL}}"
        exit 1
    fi

# recipe-mode workspaces drive the real _ensure_cache_ignored recipe
# (#375: .cache/ gitignore protection before recording) and source
# assertions pin the #374 pr/_pr_inner guard split

# test the _ensure_cache_ignored recording guard and the #374 pr guard split
[group('Testing/Automation')]
asciinema_cache_test:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "{{BLUE}}Testing asciinema cache guards...{{NORMAL}}"

    if .just/lib/asciinema_cache_test.sh; then
        echo "{{GREEN}}All asciinema cache tests passed!{{NORMAL}}"
    else
        echo "{{RED}}Some asciinema cache tests failed{{NORMAL}}"
        exit 1
    fi

# recipe-mode workspaces drive the real shellcheck recipe with a failing
# cue shim (#372: stub sandboxing - the real .just/repo-toml.sh path must
# stay untouched) and the real repo_toml_check against stub-marked files

# test the #372 repo-toml stub sandboxing and repo_toml_check sentinel
[group('Testing/Automation')]
repo_toml_stub_test:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "{{BLUE}}Testing repo_toml stub sandboxing...{{NORMAL}}"

    if .just/lib/repo_toml_stub_test.sh; then
        echo "{{GREEN}}All repo_toml stub tests passed!{{NORMAL}}"
    else
        echo "{{RED}}Some repo_toml stub tests failed{{NORMAL}}"
        exit 1
    fi
