# Security policy

This policy covers the iOS app template itself: its scripts, workflows,
fastlane lanes and Claude Code configuration. `setup.sh` removes this file,
so an app made from the template starts without it and should choose its own
policy.

## Reporting a vulnerability

**Please don't report security problems in public issues, pull requests or
discussions.**

Report them privately through GitHub instead: open the repository's
**Security** tab and choose **Report a vulnerability**. Only the maintainer can
see the report.

Please include what the problem is, how it could be exploited, the steps to
reproduce it, and the commit you looked at.

## What happens next

The template is maintained by one person in spare time, so these are aims
rather than guarantees:

- an acknowledgement within a week;
- a fix, or a plan for one, as soon as it can be worked out;
- a fix on `main` before the details are made public, with a GitHub security
  advisory crediting you unless you would rather not be named.

Please keep the details private until a fix is available or we've agreed a
date to publish.

## Supported versions

Only `main` is supported. Apps already made from the template don't receive
changes automatically: an advisory will say what to change in them.

## Scope

The template's CI runs on a **self-hosted Mac that holds the App Store signing
key**, so the most serious problems are ones that let someone else's code or
input reach that machine or its secrets. In scope, for example:

- a way for a fork, pull request, issue, comment or other outside input to run
  code on the self-hosted runner (the workflows deliberately have no
  `pull_request` trigger);
- workflow script injection, for example from branch names, tag names or
  commit messages;
- secrets (match password, App Store Connect key, certificates repository
  access) exposed in logs, artifacts, caches or files left on the runner;
- `setup.sh`, the `scripts/` or the fastlane lanes doing something unsafe,
  such as running untrusted input or weakening file permissions;
- rulesets in `docs/github-rulesets/` that don't protect what the docs say
  they do;
- Claude Code settings, skills or agents in `.claude/` that grant broader
  permissions than they need or could be steered into leaking secrets.

Out of scope:

- vulnerabilities in an app made from the template, unless the cause is in the
  template (report those to that app's owner);
- vulnerabilities in GitHub Actions, Xcode, fastlane, Homebrew or other tools
  the template uses (report those upstream), unless the template uses them
  unsafely;
- the risks inherent in choosing a self-hosted runner, which the docs already
  describe.

If you're unsure whether something counts, report it anyway.

## Research

Good-faith research is welcome. Don't run anything against someone else's
runner, repository or App Store account, and give a reasonable time to fix a
problem before disclosing it.
