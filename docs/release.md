# Releasing to TestFlight and the App Store

Pushing a `testflight-<N>` tag or branch runs `.github/workflows/release.yml` on
the self-hosted Mac runner. It checks the runner's Xcode against `.xcode-version`
(exactly), checks that `N` matches `CURRENT_PROJECT_VERSION` in `project.yml`,
checks every secret and the vault credentials, then runs `fastlane ios beta`:
generate the project, fetch the signing assets with fastlane match into a
throwaway keychain, pin the shipping targets to those profiles, archive and
upload. In Claude Code, "release to TestFlight" (the `release-to-testflight`
skill) bumps the number and pushes the ref.

## The runner Mac

`build.yml`, `release.yml` and `ui-tests.yml` run on `[self-hosted, macOS]`, the Mac
that already builds the other apps. Only `main-source-guard.yml` runs on GitHub's
hosted Ubuntu. Once per app, on that Mac:

1. **Register a runner for this repository.** A runner on a personal GitHub account
   serves one repository, so each app needs its own runner instance, even on the
   same Mac. At https://github.com/{{REPO_SLUG}}/settings/actions/runners/new pick
   macOS and follow GitHub's commands in a new folder of its own, for example
   `~/actions-runners/{{APP_NAME}}`. Never reuse another app's folder. Keep the default
   labels: `self-hosted` and `macOS` are what the workflows ask for.
2. **Run it as a service**, as your user (not root), so it survives reboots and
   logouts, from that folder:

   ```bash
   ./svc.sh install && ./svc.sh start
   ```

   Every app's runner is its own service, so two apps' builds can run at once and
   share the Mac's CPU. Jobs pushed before the runner exists wait in the queue and
   start once it's online, but GitHub fails them after 24 hours.
3. **Check the tools, once per Mac.** The Mac already has these if it builds the
   other apps:
   - Homebrew, in `/opt/homebrew` (Apple silicon) or `/usr/local`. The workflows add
     it to the service's PATH, and each run's `brew bundle --no-upgrade` installs any
     missing `Brewfile` tool (fastlane, xcodegen, SwiftLint, SwiftFormat). There's
     nothing to install for this app.
   - Xcode at `/Applications/Xcode.app`, the path every workflow's `DEVELOPER_DIR`
     pins (the service ignores `xcode-select`), at the version in `.xcode-version`.
     A different major version fails every build; a minor version warns on builds
     and fails a release. Open it once and accept the licence, and install the iOS
     simulator runtime for the deployment target.
   - The App Store Connect key, `AuthKey_<ID>.p8`, in a folder the service's user can
     read (`chmod 600`). The `ASC_KEY_PATH` secret points at it. All your apps can
     share one key.
4. **Confirm it works.** The runner shows as Idle in
   https://github.com/{{REPO_SLUG}}/settings/actions/runners, and the next push runs
   `build` on it.

Signing needs nothing on the Mac: each release builds a throwaway keychain from the
match vault and deletes it afterwards. There's no `pull_request` trigger, so a fork's
PR never runs code on this machine.

## One-time setup

On a Mac signed in to the team's Apple Developer account.

1. **Identifiers.** Register every bundle ID in the Fastfile's `SIGNING` table
   at https://developer.apple.com/account/resources/identifiers, with the
   capabilities the targets' entitlements in `project.yml` need.
2. **App Store Connect app.** Create the app record for `{{BUNDLE_ID}}` (add
   each platform to the one record for a universal purchase).
   `upload_to_testflight` does not create it.
3. **Profiles in the vault.** From a clone of this repository:

   ```bash
   brew bundle                                   # xcodegen, fastlane, the lint tools
   export MATCH_GIT_URL="{{MATCH_GIT_URL}}"
   export MATCH_PASSWORD="…"                     # the vault's passphrase, shared by every app
   unset ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH   # an App Manager key can't create profiles
   export FASTLANE_USER="<the team's Apple ID>"
   fastlane ios certificates                     # creates this app's profiles
   ```

   Run it without `CI` set, so match may write. It reuses the shared
   Distribution certificate already in the vault and adds only this app's
   profiles. If match wants to create a certificate, stop and check
   `MATCH_PASSWORD` and the team: a new one takes one of the team's two or three
   slots and splits the apps across certificates.
4. **Repository secrets** at https://github.com/{{REPO_SLUG}}/settings/secrets/actions
   (the same values as the team's other apps):

   | Secret | Value |
   |---|---|
   | `ASC_KEY_ID` | The App Store Connect API key's ID (App Store Connect → Users and Access → Integrations) |
   | `ASC_ISSUER_ID` | The issuer ID above the keys list |
   | `ASC_KEY_PATH` | The `.p8`'s absolute path on the runner, e.g. `/Users/<you>/.fastlane/AuthKey_XXXXXXXXXX.p8` (`chmod 600`) |
   | `MATCH_GIT_URL` | `{{MATCH_GIT_URL}}` |
   | `MATCH_PASSWORD` | The vault's passphrase |
   | `MATCH_GIT_BASIC_AUTHORIZATION` | `printf '%s' 'user:token' \| base64 \| tr -d '\n'` for a token that can read the vault |

5. **Repository variable** (optional) `NOTIFY_WEBHOOK_URL`: where the workflows
   post their result. Unset means no notifications.
6. **Rulesets.** Once `main` and `pre-prod` are pushed, import both
   `docs/github-rulesets/*.json` (Settings → Rules → Rulesets → New → Import).
   Rulesets need a public repository or a paid plan; on GitHub Free with a
   private repository they aren't enforced, so merge only green PRs, and only
   `pre-prod` into `main` (`docs/github-rulesets/README.md`).

## Each release

1. Change `MARKETING_VERSION` in `project.yml` when the version changes.
2. Bump `CURRENT_PROJECT_VERSION` (the project-base value every target
   inherits) and commit it, on a `release/build-<N>` branch when releasing from
   `pre-prod`.
3. Push `testflight-<N>` as a tag, or as a branch where tag pushes are blocked.
4. Watch https://github.com/{{REPO_SLUG}}/actions/workflows/release.yml.

Steps 2 and 3 are what the `release-to-testflight` skill does.

## App Store metadata

The App Store text lives in `fastlane/metadata` and goes up with
`fastlane ios metadata` (add `screenshots:true` to include
`fastlane/screenshots`). Text only by default; never a binary, never a
submission: choosing the build and submitting stay in App Store Connect.

`make check` runs `scripts/check_store_metadata.py` on every push, so CI fails
on text that wouldn't fit (name and subtitle 30 characters, keywords 100,
promotional text 170, description, release notes and review notes 4000, https
URLs, keywords without spaces or repeats, a valid category). The lane runs it
with `--release` first, which also refuses anything still marked `TODO`.

App Review's contact comes from the environment so nobody's phone number is
committed: `REVIEW_FIRST_NAME`, `REVIEW_LAST_NAME`, `REVIEW_EMAIL`,
`REVIEW_PHONE` (with the country code). The age rating, App Privacy answers,
pricing and availability are set in App Store Connect by hand.

## After an App Store release

Tag the commit that shipped, from your own machine (the cloud sandbox can't push tags):

```bash
git switch main && git pull --ff-only
version="$(awk -F'"' '/^    MARKETING_VERSION:/ {print $2; exit}' project.yml)"
git tag -a "appstore-$version" -m "App Store release $version" <sha> && git push origin "appstore-$version"
```
