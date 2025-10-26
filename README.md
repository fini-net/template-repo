# FINI template-repo

![GitHub Issues](https://img.shields.io/github/issues/fini-net/template-repo)
![GitHub Pull Requests](https://img.shields.io/github/issues-pr/fini-net/template-repo)
![GitHub License](https://img.shields.io/github/license/fini-net/template-repo)
![GitHub watchers](https://img.shields.io/github/watchers/fini-net/template-repo)

A good template for github repos with best practices adoption.

## Template Features

- ✅ [All github community standards are checked off](https://github.com/fini-net/template-repo/community)
  - ✅ This [README](README) with badges
  - ✅ [Contributor Covenant](https://www.contributor-covenant.org)-based Code of Conduct
  - ✅ [Contributing Guide](.github/CONTRIBUTING.md) includes a step-by-step guide to our
    [command line development process](.github/CONTRIBUTING.md#development-process).
  - ✅ [GPL2](LICENSE) license
  - ✅ [Security Policy](.github/SECURITY.md)
  - ✅ [Issue Templates](.github/ISSUE_TEMPLATE/)
  - ✅ [PR Template](.github/pull_request_template.md)
- ✅ [gitattributes](.gitattributes) based on [gitattributes](https://github.com/gitattributes/gitattributes)
- ✅ [gitignore](.gitignore) with comments
- ✅ [CODEOWNERS](.github/CODEOWNERS) that is self-documented
- ✅ [justfile](justfile) with
  [command line workflow for pull requests](.github/CONTRIBUTING.md#development-process)
- ✅ [Github Actions](.github/workflows) are already setup for:
  - ✅ [Auto-assign](https://github.com/pozil/auto-assign-issue) helps avoid toil.
  - ✅ [Checkov](https://github.com/bridgecrewio/checkov) will help keep our github actions secure
  - ✅ [Markdownlint](https://github.com/DavidAnson/markdownlint-cli2-action) keeps your READMEs standards-compliant
- ✅ [A few extra labels for issues](https://github.com/fini-net/template-repo/labels)

## Usage

1. To use this template, you can create a new repository by clicking on "Use this
  template" button.
1. Remember to replace any `chicks-net`, `fini-net`, and `template-repo` references
  with the right values for your project.  (Github templates do not offer
  variable substitution, but we still have to call them templates for some reason.)
1. Ditch the "Template Status", "Usage", and "Kudos" sections in the `README.md`.
  `just clean-readme` will give you a clean README, but there are other files to fix.

[Here is a nice checklist](https://github.com/jlcanovas/gh-best-practices-template/blob/main/guidelines.md)
of things to consider with a new repo.

## Contributing

- [Code of Conduct](.github/CODE_OF_CONDUCT.md)
- [Contributing Guide](.github/CONTRIBUTING.md) includes a step-by-step guide to our
  [development process](.github/CONTRIBUTING.md#development-process).

## Support & Security

- [Getting Support](.github/SUPPORT.md)
- [Security Policy](.github/SECURITY.md)

## License

I went with the [GPL2 license](LICENSE), but the MIT license is also worth considering.

## Other good template repos on github

- Jose Gracia Berenguer did a great job with their
  [project-template](https://github.com/Josee9988/project-template)
  repo.  This looks like a student project, but it is one of the best
  templates I've found on github.
- [Cookiecutter Data Science](https://github.com/drivendataorg/cookiecutter-data-science)
  is cool, but it isn't actually a template repo.
- [gh-best-practices-template](https://github.com/jlcanovas/gh-best-practices-template)
  is doing great at checking off all of the boxes.  They've including funding and citations
  which I haven't tried yet.  I'm not a fan of how all of the Markdown files are in the
  root directory.  I definitely prefer stuffing those under `/.github` for a cleaner
  root directory.

## Thanks

- I've really enjoyed building projects with [just](https://just.systems/man/en/).
- The [GitHub CLI](https://cli.github.com/) makes browser-free workflows not only
  possible, but fun.
