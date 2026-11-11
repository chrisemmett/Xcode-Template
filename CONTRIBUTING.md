# Contributing to the iOS app template

Thanks for your interest. This repository is a GitHub template: a starting
point that `setup.sh` turns into a new app's repository. Contributions should
improve the template for every app made from it.

This file describes contributing to the template itself. `setup.sh` deletes it,
along with the template's `LICENSE`, so apps made from the template start
without them.

## Before you start

- **Bugs and small fixes** (a broken script, a wrong path in the docs, a typo):
  open a pull request directly.
- **Larger changes** (a new workflow, a new tool in the Brewfile, a change to the
  branching model or the release pipeline): open an issue first to describe the
  problem. The template has opinions (XcodeGen, a self-hosted runner,
  `pre-prod` → `main`, design-driven development), and a change that fights
  them is unlikely to be merged, however well it is written.
- **Problems in an app you made from the template** belong in that app's
  repository, unless the cause is in the template.

## Security

Please **don't open a public issue** for a security problem, such as a way for
untrusted code to reach the self-hosted runner or the signing secrets. Report
it privately from the repository's **Security** tab → **Report a
vulnerability**.

## Ground rules for changes

- **Stay app-neutral.** Use the placeholders `setup.sh` fills in
  (`{{APP_NAME}}`, `{{DISPLAY_NAME}}`, `{{MODULE_NAME}}`, `{{BUNDLE_ID}}`,
  `{{TEAM_ID}}`, `{{REPO_SLUG}}` and the others it lists) rather than a real
  app's names. If you add a new placeholder, teach `setup.sh` to ask for it and
  fill it in.
- **Never commit secrets or identities:** no team IDs, certificates, provisioning
  profiles, API keys, match passwords or private repository URLs, even in
  examples.
- **Keep the CI safe on a self-hosted runner.** The workflows deliberately have
  no `pull_request` trigger, so a fork's code never runs on the Mac that holds
  the signing key. Don't add one, or anything else that runs code from outside
  the repository on the runner. Workflow changes get the closest review.
- **Workflows live in `.github/workflows-template/`** so the template itself
  never runs CI. `setup.sh` moves them into place.
- **Required check names are job ids.** `build` and `source-is-pre-prod` are
  what the rulesets in `docs/github-rulesets/` wait for, so don't rename those
  jobs or give them a `name:`.
- **Edit `project.yml`, never a generated Xcode project.** The `.xcodeproj` is
  not committed (`docs/xcodegen-regen-defenses.md`).
- **Credit what you borrow.** Third-party material included in the template
  needs its licence recorded, as in `.claude/THIRD_PARTY_LICENSES.md`.
- **Keep the docs in step.** If a change alters how something works, update the
  README, `docs/` and `.claude/CLAUDE.md` in the same pull request.

## Checking your change

Run the cheap checks, which work on macOS or Linux with Python 3:

```sh
make check
```

They cover the LLD todo/done check, the App Store metadata limits and the CI
scripts' own tests. If you change a script in `scripts/`, add or update its
test there too.

For changes to the Xcode project, the app, the workflows or `setup.sh`, also
try them end to end: make a throwaway copy of the template, run `./setup.sh` in
it on a Mac, then `make bootstrap` and `make test`. Say in the pull request what
you ran, and on which Xcode.

## Pull requests

1. Fork the repository and create a branch from `main`.
2. Keep each pull request to one change, with a clear description of what it
   changes and why.
3. Open the pull request against `main`. `main` is protected: changes reach it
   only through a pull request, and the maintainer merges.

Expect questions or requests for changes. This is maintained in spare time, so
a reply may take a few days.

## Licence

The template is released under the [MIT License](LICENSE). By contributing, you
agree that your contribution is licensed under the same terms.
