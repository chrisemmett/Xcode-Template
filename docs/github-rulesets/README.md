# GitHub rulesets

Import each file at the repository's Settings → Rules → Rulesets → New ruleset → Import.

| File | Branch | Rules |
|---|---|---|
| `pre-prod.json` | `pre-prod` | No direct pushes, force-pushes or deletion; changes only by PR; the `build` check must pass. |
| `main.json` | `main` | The same, plus the `source-is-pre-prod` check from `main-source-guard.yml`, because rulesets can't restrict a PR's source branch. |

Notes:

- `build` is the job id in `build.yml`. Don't give that job a `name:`, or the check reports under the display name and the ruleset waits on `build` forever.
- No bypass actors, matching FQ's and Home Movies' rulesets, where even the admin's direct push is rejected. Anything that must commit to a protected branch, like the TestFlight build-number bump, goes through a short-lived branch and a PR (the release skill does this).
- **GitHub Free with a private repository can't enforce required status checks** (Home Movies' situation). Drop the `required_status_checks` rule there, keep the rest, and merge only PRs whose build is green.
- Approvals are 0 for a solo developer; raise `required_approving_review_count` for a team.
