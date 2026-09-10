# project justfile

# Pass recipe arguments as positional shell parameters ($1, $2, ...)
# instead of {{...}} text substitution, so bash quoting — not just's
# templater — owns argument handling (injection-safe; see #347)
set positional-arguments := true

import? '.just/compliance.just'
import? '.just/gh-process.just'
import? '.just/pr-hook.just'
import? '.just/shellcheck.just'
import? '.just/cue-verify.just'
import? '.just/claude.just'
import? '.just/copilot.just'
import? '.just/repo-toml.just'
import? '.just/testing.just'
import? '.just/template-sync.just'
import? '.just/clean-template.just'

# list recipes (default works without naming it)
[group('Utility')]
list:
    just --list
    @echo "{{GREEN}}Your justfile is waiting for more scripts and snippets{{NORMAL}}"
