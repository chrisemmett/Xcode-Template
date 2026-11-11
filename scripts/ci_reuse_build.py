#!/usr/bin/env python3
"""Find a green full build of the same files, so CI needn't build them again.

Usage (in .github/workflows/build.yml): scripts/ci_reuse_build.py

A PR from a branch that is up to date with pre-prod merges into a commit whose tree is the branch
head's tree, which the branch's own push has just built and tested. Building the merge commit again
takes the Mac mini another full build and proves nothing new. The same goes for a TestFlight
build-number bump (`release/build-N`, then its merge): it changes only `CURRENT_PROJECT_VERSION` in
project.yml, which no lint rule, test or compile depends on, and release.yml archives that commit
anyway.

So this looks at the parents of HEAD that differ from it in nothing, or only in that line, and asks
the Actions API whether this workflow ran the full build on one of them and passed. A fast-path run
(docs and CI files only, or a reuse like this one) doesn't count, as it built nothing, but a parent
whose run was a reuse leads on to its own parents: every commit asked about is compared with HEAD
itself, up to MAX_COMMITS of them.

It fails safe: anything it can't establish (no matching parent, no token, an API error, a run still
going) means no reuse, and the caller does the full build. It writes `reuse_run=<url>` to
$GITHUB_OUTPUT only when it found one.

Environment: GITHUB_REPOSITORY, GITHUB_TOKEN (actions: read), GITHUB_API_URL, GITHUB_OUTPUT.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

WORKFLOW_PATH = ".github/workflows/build.yml"
JOB_NAME = "build"
# The marker step at the end of the full build in build.yml, skipped on the fast path. Its success
# in a green job means every step before it passed too, as none of them continues on error. A
# dedicated marker (rather than the last real step) means adding a step never breaks reuse. The
# self-test checks that build.yml still has it.
FULL_BUILD_STEP = "Full build passed"
# The one change that counts as no change: the build number, as the release-to-testflight skill bumps it.
BUMP_FILE = "project.yml"
# How many ancestors with the same files to ask about before giving up and building.
MAX_COMMITS = 6
BUMP_LINE = re.compile(r'^\s*CURRENT_PROJECT_VERSION:\s*"?\d+"?\s*$')


def git(*args: str) -> str:
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout.strip()


def only_build_number(diff: str) -> bool:
    """Whether a `git diff -U0` changes nothing but CURRENT_PROJECT_VERSION in project.yml.

    An empty diff (the same tree) counts too.
    """
    for line in diff.splitlines():
        if line.startswith(("diff --git ", "index ", "@@ ")):
            continue
        if line.startswith(("--- ", "+++ ")):
            if line[4:] not in (f"a/{BUMP_FILE}", f"b/{BUMP_FILE}"):
                return False
            continue
        if line.startswith(("+", "-")):
            if not BUMP_LINE.match(line[1:]):
                return False
            continue
        # Anything else (a mode change, a new or deleted file, a binary file) is a real change.
        return False
    return True


def reusable_parents(parents: list[tuple[str, str]]) -> list[str]:
    """The parents, as (sha, diff to HEAD), whose diff changes nothing that builds.

    Same-tree parents come first, then the merged-in side (the second parent) before the first.
    """
    matching = [(sha, diff) for sha, diff in reversed(parents) if only_build_number(diff)]
    return [sha for sha, diff in sorted(matching, key=lambda item: item[1] != "")]


def full_build_passed(jobs: dict) -> bool:
    """Whether a run's jobs (the API's `jobs` listing) include a green full build."""
    for job in jobs.get("jobs", []):
        if job.get("name") != JOB_NAME or job.get("conclusion") != "success":
            continue
        for step in job.get("steps", []):
            if step.get("name") == FULL_BUILD_STEP and step.get("conclusion") == "success":
                return True
    return False


def build_runs(runs: dict) -> list[dict]:
    """This workflow's completed, successful push runs from an `actions/runs` listing, newest first."""
    matching = [
        run for run in runs.get("workflow_runs", [])
        if run.get("path", "").split("@")[0] == WORKFLOW_PATH
        and run.get("event") == "push"
        and run.get("status") == "completed"
        and run.get("conclusion") == "success"
    ]
    return sorted(matching, key=lambda run: run.get("created_at", ""), reverse=True)


def api(path: str) -> dict:
    base = os.environ.get("GITHUB_API_URL", "https://api.github.com")
    request = urllib.request.Request(base + path, headers={
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {os.environ['GITHUB_TOKEN']}",
        "X-GitHub-Api-Version": "2022-11-28",
    })
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.load(response)


def find_reusable_run() -> str | None:
    repo = os.environ.get("GITHUB_REPOSITORY")
    if not repo or not os.environ.get("GITHUB_TOKEN"):
        print("No repository or token; no reuse.")
        return None
    # Breadth first through ancestors with these files, each compared with HEAD itself: a parent
    # whose run only reused an earlier build (as most pre-prod heads' will) leads on to that build.
    queue, seen, looked_at = ["HEAD"], {"HEAD"}, 0
    while queue and looked_at < MAX_COMMITS:
        commit = queue.pop(0)
        parent_shas = git("rev-list", "--parents", "-n", "1", commit).split()[1:]
        parents = [(sha, git("diff", "-U0", "--no-renames", "--no-color", sha, "HEAD"))
                   for sha in parent_shas if sha not in seen]
        for sha in reusable_parents(parents):
            seen.add(sha)
            looked_at += 1
            runs = build_runs(api(f"/repos/{repo}/actions/runs?head_sha={sha}&event=push&per_page=20"))
            for run in runs:
                if full_build_passed(api(f"/repos/{repo}/actions/runs/{run['id']}/jobs?per_page=50")):
                    print(f"{sha[:12]} has these files (build number aside) and passed the full build: {run['html_url']}")
                    return run["html_url"]
            print(f"{sha[:12]} has these files but no green full build of it; trying its parents.")
            queue.append(sha)
    print("No green full build of these files found; building them.")
    return None


def main() -> int:
    try:
        url = find_reusable_run()
    except (OSError, subprocess.CalledProcessError, urllib.error.URLError, ValueError, KeyError) as error:
        print(f"::warning::Couldn't look for an earlier build of this tree ({error}); building it.")
        url = None
    output = os.environ.get("GITHUB_OUTPUT")
    if url and output:
        with open(output, "a", encoding="utf-8") as handle:
            handle.write(f"reuse_run={url}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
