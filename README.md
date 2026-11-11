<!-- template:start -->
# iOS app template

Everything to start an iPhone and iPad app the way FQ, Ball-Kick-Game and Home
Movies are run: XcodeGen, a Foundation-only core package, CI on a self-hosted
Mac, TestFlight through fastlane match, design-driven development with LLDs,
and Claude Code skills that release and fix signing for you.

## Start here

1. On GitHub: push this folder to a repository and tick **Settings → Template
   repository**, then **Use this template** for each new app. (Or just unzip it
   into a new folder.)
2. **On the GitHub runner Mac** (the machine registered as the repository's
   self-hosted runner), in a clone of the new repository, once:

   ```sh
   ./setup.sh
   ```

   It first asks you to confirm you're on the runner Mac, and stops without
   changing anything unless you answer `y`.

   It asks for the app name, bundle ID, team ID, GitHub slug, match vault URL,
   deployment target and Xcode version, fills in every `{{PLACEHOLDER}}`, renames
   the `{{APP_NAME}}` folders, turns CI on (the workflows wait in
   `.github/workflows-template/` until then, so the template never runs CI),
   runs `make check`, deletes itself and this section, commits the result on
   `main`, creates `pre-prod` from it, and offers to push both.
3. Follow the checklist it prints. `docs/release.md` has the detail.

This section and `setup.sh` disappear after setup; everything below is the new
app's README.
<!-- template:end -->
# {{DISPLAY_NAME}}

An iPhone and iPad app. Swift 6, SwiftUI, iOS {{IOS_DEPLOYMENT_TARGET}}+.

## Getting started

On a Mac with the Xcode in `.xcode-version`:

```sh
make bootstrap    # Brewfile tools incl. fastlane (lists them, asks first), Config/Local.xcconfig, generate the project
make open         # generate and open {{APP_NAME}}.xcodeproj
make test         # core package + app unit tests
make help         # everything else
```

The `.xcodeproj` is generated from `project.yml` and isn't committed: change
targets, settings, Info.plist keys and entitlements in `project.yml`, never in
Xcode's inspectors (`docs/xcodegen-regen-defenses.md`).

## Layout

| Path | What |
|---|---|
| `{{APP_NAME}}/` | The app: SwiftUI views, assets, privacy manifest |
| `Packages/{{MODULE_NAME}}Core/` | Foundation-only domain logic; `make test-core` runs it with `swift test` anywhere |
| `{{APP_NAME}}Tests/`, `{{APP_NAME}}UITests/` | App unit tests (merge gate), UI tests (nightly) |
| `project.yml`, `Config/` | XcodeGen spec and xcconfigs |
| `design/Documentation/docs/` | HLD, LLDs (`todo/`, `done/`), architecture, reviews |
| `scripts/` | CI logic, each piece self-tested (`make test-scripts`) |
| `fastlane/` | TestFlight, signing (match) and App Store metadata lanes |
| `.github/workflows/` | `build` (every push), `release` (`testflight-<N>`), `ui-tests` (nightly), `main-source-guard` |
| `.claude/` | Project guide, release and signing skills, design-docs and review agents, iPhone Duo skills |
| `docs/` | Release setup, rulesets to import, the XcodeGen notes |

## How work flows

- Design first: non-trivial work starts as an LLD in
  `design/Documentation/docs/03 - Low Level Design/todo/` (copy `LLD-TEMPLATE.md`),
  and is `git mv`'d to `done/` when it ships.
- Branches come off `pre-prod` and merge back by PR once the `build` check is
  green. `main` is what's on the App Store; only `pre-prod` merges into it.
- TestFlight: say "release to TestFlight" in Claude Code, or bump
  `CURRENT_PROJECT_VERSION` and push a `testflight-<N>` tag (`docs/release.md`).

## CI

Every push runs `build.yml` on the self-hosted Mac: the Xcode pin and cheap
checks always; lint, project generation, core and app tests unless the change is
docs or CI only, or the same files already passed. Nothing is signed except in
`release.yml`, and only refs pushed to this repository run on the runner.
