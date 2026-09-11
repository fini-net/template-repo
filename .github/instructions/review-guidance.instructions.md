---
applyTo: ".just/**,.github/workflows/**"
---

# Review guidance for this repo

This repo is a GitHub repository template. The `.just/` directory ships to
derived repos via template sync, so review feedback about `.just/*` files
lands in two contexts: here (the template) and in derived repos.

## Known-correct idioms

Do not flag these as bugs; they are intentional and verified.

### Single-quoted `unset 'arr[arith]'`

```bash
unset 'footer_content[${#footer_content[@]}-1]'
```

Bash evaluates an `unset` subscript as arithmetic at unset time, even when
the subscript is single-quoted. `${#footer_content[@]}` therefore resolves
correctly when `unset` runs. The single quotes prevent this line's own
word expansion from mangling the subscript first. This idiom is safe under
`set -e` and is exercised by the `15_trailing_blanks` fixture in
`.just/lib/pr_body_test.sh`.

## Template-shipped files

- `.just/*` files may reference test runners or recipes that exist only in
  template-repo (e.g. `.just/lib/cue_sync_test.sh`); `just clean_template`
  removes them from derived repos. A comment mentioning such a file is not
  a broken reference in this repo.
- Do not suggest "fixing" comments that explain why a program lives in a
  shared file (see `.just/lib/cue_sync.awk` and `.just/cue-verify.just`).
