# File Format Self-checks

# use Cue to verify /.repo.toml validity
[group('Compliance')]
cue-verify:
    cue vet .repo.toml docs/repo-toml.cue
    @echo "{{ GREEN }}Cue-verify passed.{{ NORMAL }}"
