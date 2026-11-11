---
name: signing-certs
description: Manage {{DISPLAY_NAME}}'s code signing — the Apple Distribution certificate (shared with the team's other apps), the App Store provisioning profiles, the fastlane match storage repo, and the secrets that drive CI signing. Use when the user mentions a signing/cert/profile problem or a renewal, e.g. "certificate expired", "provisioning profile expired or invalid", "renew/rotate signing", "TestFlight signing broken", "match error", "Error cloning certificates repo", "could not read Username for github", "errSecInternalComponent", "reached the maximum number of certificates", "This request is forbidden for security reasons", "code signing is required", or any time a release fails at the vault / match / build_app / codesign step. Also for the first-time setup of a new app's profiles.
---

# {{DISPLAY_NAME}} code signing (fastlane match)

{{DISPLAY_NAME}} signs TestFlight and App Store builds with **fastlane match**.
One **Apple Distribution** certificate and an **App Store** provisioning profile
per bundle ID (and per platform) live **encrypted** in a private git repo, the
vault (`MATCH_GIT_URL`). Each CI run installs them into a throwaway keychain
(`setup_ci`), so signing never depends on a Mac's login keychain. The lanes are
in `fastlane/Fastfile` (`certificates`, `beta`), the config in
`fastlane/Matchfile`, and the one-time setup in `docs/release.md`.

**Always run match through the lanes** (`fastlane ios certificates`), not bare
`fastlane match`: the Matchfile names no bundle IDs; the Fastfile's `SIGNING`
table passes each platform's own.

## The certificate is shared

Apple allows only two or three Distribution certificates per team, so every app
on the team signs with the **same** certificate from the **same** vault; match
stores profiles by bundle ID, so each app's profiles sit side by side. The apps
sharing it: {{SIBLING_APPS}}. Keep this list current.

Consequence: **anything that revokes or replaces the Distribution certificate
breaks signing for every one of those apps** until each is repaired. Treat
every `nuke` as an all-apps operation and finish the repair checklist below
before calling it done.

## The moving parts and when they expire

| Thing | Where it lives | Expires? |
|---|---|---|
| Apple **Distribution certificate** (shared) | encrypted in the vault; installed on the runner per build | **~1 year** after creation |
| **App Store provisioning profiles**, one per bundle ID in `SIGNING` | the vault | **~1 year**, and invalid at once if the cert is revoked or regenerated, or a capability changes |
| `MATCH_PASSWORD` (decrypts the vault; same value for every app) | Actions secret | never, but if lost the vault can't be recovered (nuke and recreate: all apps) |
| `MATCH_GIT_URL` | Actions secret | never |
| `MATCH_GIT_BASIC_AUTHORIZATION` (base64 `user:token` that clones the vault) | Actions secret | **when the GitHub token expires** (rotate it in every repo that shares it) |
| App Store Connect API key (`ASC_KEY_*`, a `.p8`) | file on the runner + secrets; one key serves the team | doesn't expire; can be revoked |

**Golden rule: CI never renews.** The `beta` lane runs match readonly, so a
run can only consume certificates. **A human renews, on a Mac, read-write;
that pushes to the vault and the next CI build picks it up.**

**Create and renew with an Apple ID, not the API key.** The team's API key is
App Manager, and Apple refuses to let that role create profiles ("This request
is forbidden for security reasons"). The lanes use the key only when
`ASC_KEY_ID` is set, so unset it and set `FASTLANE_USER` (below).

## Renewing an expired (or about-to-expire) certificate or profiles

Symptoms: a release fails at `build_app` or codesign with "certificate has
expired" or "no valid signing identity", or the developer portal shows them
expired. On a Mac, from a normal clone (never the runner's `_work` checkout):

```bash
# 0. Once per machine:
brew bundle                                            # xcodegen, fastlane, ...
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

# 1. The vault and an Apple ID login:
cd <clone> && git switch pre-prod && git pull
export MATCH_GIT_URL="{{MATCH_GIT_URL}}"
unset ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH
export FASTLANE_USER="<the team's Apple ID>"

# 2a. Profiles only (cert still valid; profiles expired or a capability changed):
fastlane ios certificates force:true                   # and `fastlane tvos ...` per platform

# 2b. The certificate itself expired. Replace it (re-issues profiles too):
fastlane match nuke distribution                       # revokes ALL distribution certs: see WARNING
fastlane ios certificates
# ...then the repair checklist for every other app.
```

match asks for `MATCH_PASSWORD` and the Apple ID's 2FA. A routine renewal
changes **no secrets**. Re-run the release afterwards (`release-to-testflight`).

> ⚠️ **`nuke distribution` revokes every Apple Distribution certificate on the
> team**, including the one every app listed above signs with. Confirm with the user
> before you nuke, and name every app when you do.

### Repair checklist after a certificate replacement

- [ ] This app: `fastlane ios certificates` (each platform).
- [ ] Every other app in the list above: from its own clone, re-issue its
      profiles against the new certificate (its `certificates` lanes, or
      `fastlane match appstore` if it predates them).
- [ ] Prove it: ship one build of each app, or at least run the readonly health
      check below in each repo, rather than finding out at the next release.

Tell the user which boxes are still open: the other apps' repairs happen in
their own repos, which this session can't reach unless they're attached.

## Rotating the vault token (`MATCH_GIT_BASIC_AUTHORIZATION`)

Symptoms: the "Check access to the match vault" step says the vault rejected
the token, or match fails with `could not read Username for 'https://github.com'`.

```bash
# A classic token with `repo` scope, or a fine-grained one with Contents: Read on the vault.
# Encode WITHOUT a trailing newline (printf, not echo), and test before saving:
AUTH=$(printf '%s' '<github-user>:<new-token>' | base64 | tr -d '\n')
git -c http.extraheader="Authorization: Basic $AUTH" ls-remote "$MATCH_GIT_URL"   # silent success = good
echo "$AUTH"                                                                     # copy this one line
```

Update the secret at https://github.com/{{REPO_SLUG}}/settings/secrets/actions,
and in every other repo sharing the token, then re-run the release.

## Troubleshooting map

| Error in the release run | Cause | Fix |
|---|---|---|
| `... secret is not set` (validate step) | a secret is missing | Add it: repo → Settings → Secrets and variables → Actions |
| vault check: "not base64", "starts with 'Basic'", "decodes to text with a newline" | the secret was stored wrongly | Re-make it with the `printf` recipe above |
| vault check: "The vault rejected ..." / `could not read Username` | token wrong, expired or without access | Rotate the token (above) |
| `Could not resolve host` | typo in `MATCH_GIT_URL` | Fix the secret |
| `match returned no ios profile for <id>` | that profile was never created in the vault | `fastlane ios certificates` by hand on a Mac (docs/release.md) |
| `build_app` fails in seconds, profile not found | a profile name was built by convention but match stored a suffixed one | Read names from `MATCH_PROVISIONING_PROFILE_MAPPING` (the Fastfile does); never hardcode them |
| `errSecInternalComponent` during codesign | signing hit the locked **login** keychain | `setup_ci` must run before `match` and `build_app` |
| `This request is forbidden for security reasons` | creating profiles with the App Manager API key | Use an Apple ID: unset `ASC_KEY_*`, set `FASTLANE_USER` |
| `Could not create another Distribution certificate, reached the maximum number` | Apple's cap, shared by every app on the team | Reuse the vault's certificate (check `MATCH_PASSWORD` and the team); nuke only as a last resort |
| `Signing for "<bundle>" requires a development team` | an SPM resource bundle has no team | `DEVELOPMENT_TEAM` in `build_app`'s xcargs (the Fastfile passes it) |
| `An App ID with Identifier '<id>' is not available` | no App Store Connect record | Create the app in App Store Connect; `upload_to_testflight` doesn't |
| profile lacks an entitlement after a capability change | profiles predate the capability | Enable it on the App ID, then `fastlane ios certificates force:true` |

## Health check (before something silently expires)

```bash
cd <clone> && export MATCH_GIT_URL="{{MATCH_GIT_URL}}"
CI=1 fastlane ios certificates          # CI=1 makes the lane readonly
```

Or read the expiry dates at https://developer.apple.com/account/resources.
Renew a week or two early, on whichever app's schedule comes first, then run
the repair checklist.

## Don't

- Don't make CI match read-write. CI must never mint certificates.
- Don't hardcode provisioning-profile names; read them from match's mapping.
- Don't commit certificates, the `.p8` or `MATCH_PASSWORD`.
- Don't `nuke` without naming every app it breaks, and don't report a renewal done until the repair checklist is.
- Don't renew from the runner's `~/actions-runner/_work/...` checkout.
