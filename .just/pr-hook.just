# .just/pr-hook.just

# called from pr recipe in .just/gh-process.just

# run this before creating a PR
_pr-hook:
    exit 1 # TODO: remove in next PR after verification
    echo "{{BLUE}}placeholder{{NORMAL}}"
