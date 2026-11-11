# GitHub rulesets

Import each file at the repository's Settings → Rules → Rulesets → New ruleset → Import,
after `main` and `pre-prod` have been pushed. They are FQ's rulesets, exported, with only
FQ's ruleset id and source repository removed.

| File | Branches | Rules |
|---|---|---|
| `protect-main-and-pre-prod.json` | `main`, `pre-prod` | No deletion or force-push; changes only by PR (merge or squash, 0 approvals); the `build` check from GitHub Actions must pass. |
| `main-only-from-pre-prod.json` | `main` | The `source-is-pre-prod` check from `main-source-guard.yml` must pass, because rulesets can't restrict a PR's source branch. |

Notes:

- Bypass: repository admins, **for pull requests only**. An admin can merge a PR whose
  checks haven't passed, but can't push to either branch directly. Anything that must
  commit to a protected branch, like the TestFlight build-number bump, goes through a
  short-lived branch and a PR (the release skill does this). `main-only-from-pre-prod`
  has no bypass, so even an admin can only merge `pre-prod` into `main`.
- `build` and `source-is-pre-prod` are job ids in `build.yml` and `main-source-guard.yml`.
  Don't give either job a `name:`, or the check reports under the display name and the
  ruleset waits on the job id forever. `integration_id` 15368 is GitHub Actions itself
  (the same in every repository), so only Actions can satisfy them.
- **GitHub Free can't enforce rulesets on a private repository** (Home Movies'
  situation): they import, but aren't enforced. Either make the
  repository public, move to GitHub Pro, or merge only green PRs from `pre-prod` by habit.
- Approvals are 0 for a solo developer; raise `required_approving_review_count` for a team.
