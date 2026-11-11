---
name: release-to-testflight
description: Ship {{DISPLAY_NAME}} to TestFlight. Use when the user says "release to TestFlight", "ship a TestFlight build", "cut a TestFlight build", "deploy to TestFlight", "push a new TestFlight build", or anything that means uploading a new beta build to App Store Connect. Bumps the build number (on a `release/build-<N>` branch and PR when the source is the protected `pre-prod`), commits, then pushes a `testflight-<N>` tag (or branch, if the sandbox blocks tag pushes) that triggers `.github/workflows/release.yml`. Also covers the `appstore-<version>` tag after an App Store release.
---

# Release {{DISPLAY_NAME}} to TestFlight

A TestFlight upload is triggered by pushing a `testflight-<N>` git ref.
`.github/workflows/release.yml` fires on tags **and** branches matching that
glob, checks that `N` equals `CURRENT_PROJECT_VERSION` in `project.yml`, then
runs `fastlane ios beta` (one step per platform), which generates the project,
signs with fastlane match and uploads.

The canonical ref is a tag. The Claude Code cloud sandbox's git proxy refuses
pushes under `refs/tags/`, so there the skill pushes a `testflight-<N>` branch
instead: same workflow, same verify step. (`workflow_dispatch` with a
`build_number` input exists too, but its button only appears once the workflow
is on the default branch; it is the last resort.)

## 0. Preconditions

```
ls project.yml .github/workflows/release.yml fastlane/Fastfile
grep -nE 'testflight-\*' .github/workflows/release.yml
```

If a file is missing or the workflow has no `testflight-*` trigger, stop: the
pipeline isn't set up (run `./setup.sh` once, which moves the workflows into place). Don't improvise an
upload. If a run later fails at the validate, vault or match steps, hand over
to the `signing-certs` skill.

## Procedure

Run the steps in order. If any step fails or gives an unexpected result, stop
and report it. Don't recover silently.

### 1. Choose the source branch

The default is the **current branch** (`.claude/CLAUDE.md`, TestFlight). A dev
branch carrying unmerged work is a normal, common source: it is how work in
progress reaches real devices. When you release from one, say in the final
report that the build carries that branch's unmerged, possibly CI-unverified
code.

**Never release from `main`.** It reflects the App Store. If the current branch
is `main`, or the user asks for a build "from main", release from `pre-prod`
and say so. Ask with `AskUserQuestion` only when the choice is genuinely
ambiguous (the user refers to work that isn't on the current branch).

`pre-prod` and `main` are protected by a ruleset: changes arrive only through
PRs, and a direct push is rejected (`GH013: Repository rule violations`), even
from an admin. So the skill uses two names:

- **`<source>`**: the branch the release is built from. Steps 2 to 4 read it.
- **`<branch>`**: where the bump is committed and pushed (steps 5 to 10). For a
  dev branch it is the dev branch itself. For `pre-prod` it is a short-lived
  `release/build-<N>` branch (step 4b), merged back by a PR (step 10b).

`<branch>` is never `pre-prod` or `main`. If it would be, stop.

### 2. Sync the working tree

```
git switch <source>
git pull --ff-only origin <source>
git status --short
```

Stop if the tree is dirty or the pull isn't a fast-forward. Report what you
found and ask how to proceed.

### 3. Read the current build number and the highest shipped

```
grep -nE '^    CURRENT_PROJECT_VERSION:' project.yml
git ls-remote origin 'refs/tags/testflight-*' 'refs/heads/testflight-*' \
  | sed -E 's#.*/testflight-([0-9]+).*#\1#' | sort -n | tail -1
```

The grep must match exactly one line: the project-base value at a 4-space
indent, which every target inherits. Zero or several lines mean a per-target
override has crept in or the layout changed: stop.

The `ls-remote` gives the highest build already pushed. It can be ahead of
`project.yml` when an earlier `release/build-<N>` PR hasn't merged yet. Also
look for open PRs from `release/build-*` (`mcp__github__list_pull_requests`, if
available); if one is open, say so: its bump hasn't reached `<source>`.

### 4. Choose the next build number

`N = max(current, highest shipped) + 1`. Don't ask; state it in the report. If
the user names a number, use theirs. Build numbers may skip (builds are
uploaded outside your view), so a gap is not a problem.

### 4b. Cut the release branch (source `pre-prod` only)

Skip for a dev branch. From the synced `pre-prod`:

```
git ls-remote --heads origin release/build-<N> testflight-<N>
git switch -c release/build-<N>
```

If `ls-remote` prints anything, an earlier attempt at `<N>` exists: stop and
ask whether to reuse it or pick a higher number.

### 5. Bump `project.yml`

`Edit` the project-base line, with the `MARKETING_VERSION` line above it as
context so the edit lands on the 4-space-indented value:

```
    MARKETING_VERSION: "<unchanged>"
    CURRENT_PROJECT_VERSION: "<N>"
```

### 6. The Xcode project

The `.xcodeproj` is generated and not committed, so `project.yml` is the only
file to change; the lanes regenerate the project on the runner. If `xcodegen`
is on `PATH` you may run `make generate` to check `project.yml` still parses,
but commit nothing it produces.

(Older repos that DO commit the project: if `git ls-files '*.xcodeproj/project.pbxproj'`
prints a path, run `xcodegen generate` and commit the pbxproj too. Without
xcodegen, `Edit` with `replace_all` on `CURRENT_PROJECT_VERSION = <old>;` in the
pbxproj and confirm by grep that exactly the project-base Debug and Release
lines changed.)

### 7. Commit

```
git add project.yml
git commit -m "Bump build to <N> for TestFlight release"
```

Stage only the bump. Don't amend, bundle unrelated changes or skip hooks.

### 8. Push `<branch>`

```
git push -u origin <branch>
```

Check first that `<branch>` is neither `pre-prod` nor `main`. Retry network
errors up to 4 times with backoff (2s, 4s, 8s, 16s). If a ruleset rejects the
push (`GH013`, "protected branch", "Changes must be made through a pull
request"), don't retry and don't go on to the tag: stop and report.

### 9. Create and push the tag

```
git tag -a testflight-<N> -m "TestFlight build <N>"
git push origin testflight-<N>
```

If the tag already exists, stop and ask. Never force-push a tag without
confirmation.

**If the push fails with HTTP 403 or "remote end hung up"**, the sandbox proxy
is refusing `refs/tags/`. It is policy, not a transient error: don't retry,
don't force-push, go to 9b.

### 9b. Fallback: push a `testflight-<N>` branch

```
git switch -c testflight-<N>
git push -u origin testflight-<N>
git switch <branch>
```

If the local branch exists from an earlier attempt, `git branch -D testflight-<N>`
and retry (the commit you want is on `<branch>`). Retry network errors as
above. If the branch push also gets 403, go to 9c.

Leave the `testflight-<N>` branch on origin: it marks which commit shipped as
build N, and the proxy may refuse deleting it.

### 9c. Last resort: manual dispatch

Only when both pushes were blocked. Capture `git rev-parse HEAD`, the branch,
and N, then give the user both options verbatim:

> Both tag and branch pushes under `testflight-*` were blocked by the sandbox
> proxy. Build `<N>` is committed on `<branch>` at `<SHA>` and pushed. Pick one:
>
> **A. Dispatch from the Actions UI** (works once release.yml is on the default branch)
>    1. Open https://github.com/{{REPO_SLUG}}/actions/workflows/release.yml
>    2. **Run workflow**, ref `<branch>`, build number `<N>`.
>
> **B. Push the tag from your machine**
>    ```
>    git fetch origin <branch>
>    git tag -a testflight-<N> <SHA> -m "TestFlight build <N>"
>    git push origin testflight-<N>
>    ```

Then skip step 10 (nothing fired), but still do 10b when the source was `pre-prod`.

### 10. Confirm the workflow fired

Report:
- the ref (tag or branch) and the SHA it points at;
- that it triggered `.github/workflows/release.yml`, with the link
  https://github.com/{{REPO_SLUG}}/actions/workflows/release.yml;
- for a dev branch, that the build carries its unmerged code;
- for `pre-prod`, the bump PR from 10b.

Surfacing the run through `mcp__github__` tools is optional; the link is enough.

### 10b. Open the PR back into `pre-prod` (source `pre-prod` only)

Open a PR from `release/build-<N>` into `pre-prod` (never into `main`), titled
"Bump build to <N> for TestFlight release", as a regular PR. Otherwise
`pre-prod` keeps the old number and the next release reads a stale one (step 3
catches that, but the PR fixes it). Don't merge it yourself unless asked; it
merges once its build is green. Build reuse makes that build quick: the bump
changes nothing but the build number.

## 11. After an App Store release: cut `appstore-<version>`

**Not part of a TestFlight upload.** It happens when `pre-prod` has been
promoted into `main` and that build is released to the App Store. It lives here
because this is the document read while shipping. Rollback recovers from the
tag, so a release without one has no recovery point.

```bash
git switch main && git pull --ff-only origin main
version="$(awk -F'"' '/^    MARKETING_VERSION:/ {print $2; exit}' project.yml)"
git tag -a "appstore-$version" -m "App Store release $version" <sha-that-shipped>
git push origin "appstore-$version"
```

Use `MARKETING_VERSION`, not the build number. One tag per App Store release.

**The sandbox cannot push this tag, and there is no branch fallback**: rollback
reads tags, and a branch named `appstore-1.2` would look like a recovery point
that isn't one. In the sandbox, give the user these commands to run on their
machine, and don't report the release as complete without saying so.

## Hard rules

- Don't edit `.github/workflows/release.yml` as part of a release; the triggers are permanent.
- Don't add a per-target `CURRENT_PROJECT_VERSION`: an extension or watch app out of step with its host is rejected by App Store Connect.
- Don't push to `main` or `pre-prod`, release from `main`, or open a PR from `release/build-<N>` into `main`.
- Don't reuse an existing `testflight-<N>` tag or branch unless the user says so.
- Don't "fix" a 403 on a push by force-pushing, rewriting commits or renaming the ref. Go to 9b.
- Don't commit a generated `.xcodeproj`.
- If you stop partway, say exactly which step you reached so the user can resume by hand.
