#!/usr/bin/env python3
"""Self-test of ci_reuse_build.py against canned Actions API answers.

Run with `make test-scripts`, or `python3 -B -m unittest discover -s scripts -p 'test_*.py'`.
"""

import os
import re
import subprocess
import sys
import tempfile
import unittest
import unittest.mock
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import ci_reuse_build as reuse  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent


def job(conclusion="success", last_step="success", name="build"):
    return {"name": name, "conclusion": conclusion, "steps": [
        {"name": "Checks", "conclusion": "success"},
        {"name": reuse.FULL_BUILD_STEP, "conclusion": last_step},
    ]}


def run(run_id, conclusion="success", status="completed", event="push", path=reuse.WORKFLOW_PATH,
        created="2026-11-11T08:56:33Z"):
    return {"id": run_id, "conclusion": conclusion, "status": status, "event": event, "path": path,
            "created_at": created, "html_url": f"https://example.invalid/runs/{run_id}"}


BUMP = """\
diff --git a/project.yml b/project.yml
index 83ac6b2..b86ccbf 100644
--- a/project.yml
+++ b/project.yml
@@ -20 +20 @@ settings:
-    CURRENT_PROJECT_VERSION: "59"
+    CURRENT_PROJECT_VERSION: "60"
"""


class OnlyBuildNumberTests(unittest.TestCase):
    def test_same_tree(self):
        self.assertTrue(reuse.only_build_number(""))

    def test_build_number_bump(self):
        self.assertTrue(reuse.only_build_number(BUMP))

    def test_other_line_in_project_yml(self):
        self.assertFalse(reuse.only_build_number(BUMP + "@@ -30 +30 @@\n-    SWIFT_VERSION: 5\n+    SWIFT_VERSION: 6\n"))

    def test_marketing_version_is_a_change(self):
        diff = BUMP.replace("CURRENT_PROJECT_VERSION", "MARKETING_VERSION").replace('"59"', '"1.0"').replace('"60"', '"1.1"')
        self.assertFalse(reuse.only_build_number(diff))

    def test_same_line_in_another_file(self):
        self.assertFalse(reuse.only_build_number(BUMP.replace("project.yml", "Config/Other.yml")))

    def test_new_file(self):
        diff = "diff --git a/x.swift b/x.swift\nnew file mode 100644\nindex 0000000..1111111\n--- /dev/null\n+++ b/x.swift\n@@ -0,0 +1 @@\n+let x = 1\n"
        self.assertFalse(reuse.only_build_number(diff))


class ReusableParentsTests(unittest.TestCase):
    def test_merge_of_an_up_to_date_branch_offers_the_branch_head_first(self):
        self.assertEqual(reuse.reusable_parents([("base", BUMP), ("branch", "")]), ["branch", "base"])

    def test_build_number_bump_offers_its_parent(self):
        self.assertEqual(reuse.reusable_parents([("parent", BUMP)]), ["parent"])

    def test_code_change_offers_nothing(self):
        code = "diff --git a/a.swift b/a.swift\n--- a/a.swift\n+++ b/a.swift\n@@ -1 +1 @@\n-let a = 1\n+let a = 2\n"
        self.assertEqual(reuse.reusable_parents([("parent", code)]), [])


class FullBuildPassedTests(unittest.TestCase):
    def test_green_full_build(self):
        self.assertTrue(reuse.full_build_passed({"jobs": [job()]}))

    def test_fast_path_run_built_nothing(self):
        self.assertFalse(reuse.full_build_passed({"jobs": [job(last_step="skipped")]}))

    def test_failed_job(self):
        self.assertFalse(reuse.full_build_passed({"jobs": [job(conclusion="failure")]}))

    def test_other_job_names_ignored(self):
        self.assertFalse(reuse.full_build_passed({"jobs": [job(name="release")]}))


class BuildRunsTests(unittest.TestCase):
    def test_keeps_only_green_completed_pushes_of_this_workflow_newest_first(self):
        runs = {"workflow_runs": [
            run(1, created="2026-11-11T08:00:00Z"),
            run(2, created="2026-11-11T09:00:00Z"),
            run(3, conclusion="cancelled"),
            run(4, status="in_progress", conclusion=None),
            run(5, event="workflow_dispatch"),
            run(6, path=".github/workflows/release.yml"),
            run(7, path=f"{reuse.WORKFLOW_PATH}@refs/heads/x", created="2026-11-11T07:00:00Z"),
        ]}
        self.assertEqual([r["id"] for r in reuse.build_runs(runs)], [2, 1, 7])


class ChainTests(unittest.TestCase):
    """A real repository: code built in full, a merge that reused it, a bump and the bump's merge."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.cwd = os.getcwd()
        self.addCleanup(os.chdir, self.cwd)
        os.chdir(self.tmp.name)
        env = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.invalid",
               "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.invalid"}
        self.git_env = {**os.environ, **env}
        self.sh("git init -q -b pre-prod")
        self.base = self.commit('    CURRENT_PROJECT_VERSION: "59"\n', "let a = 1\n", "base")
        self.sh("git checkout -q -b feature")
        self.code = self.commit('    CURRENT_PROJECT_VERSION: "59"\n', "let a = 2\n", "code")
        self.sh("git checkout -q pre-prod")
        self.sh("git merge -q --no-ff -m merge feature")
        self.merge = self.sh("git rev-parse HEAD")
        self.sh("git checkout -q -b release")
        self.bump = self.commit('    CURRENT_PROJECT_VERSION: "60"\n', "let a = 2\n", "bump")
        self.sh("git checkout -q pre-prod")
        self.sh("git merge -q --no-ff -m bump-merge release")
        self.bump_merge = self.sh("git rev-parse HEAD")
        os.environ.update(GITHUB_REPOSITORY="o/r", GITHUB_TOKEN="x")
        self.addCleanup(os.environ.pop, "GITHUB_TOKEN")
        self.addCleanup(os.environ.pop, "GITHUB_REPOSITORY")

    def sh(self, command):
        return subprocess.run(command.split(), check=True, capture_output=True, text=True,
                              env=self.git_env).stdout.strip()

    def commit(self, project, code, message):
        Path("project.yml").write_text("settings:\n" + project, encoding="utf-8")
        Path("a.swift").write_text(code, encoding="utf-8")
        self.sh("git add -A")
        subprocess.run(["git", "commit", "-q", "-m", message], check=True, env=self.git_env)
        return self.sh("git rev-parse HEAD")

    def lookup(self, head, fully_built):
        self.sh(f"git checkout -q --detach {head}")
        asked = []

        def api(path):
            if "/jobs" in path:
                sha = path.split("/runs/")[1].split("/")[0]
                return {"jobs": [job(last_step="success" if sha in fully_built else "skipped")]}
            sha = path.split("head_sha=")[1].split("&")[0]
            asked.append(sha)
            return {"workflow_runs": [run(sha)]}

        original = reuse.api
        reuse.api = api
        try:
            with open(os.devnull, "w") as quiet, unittest.mock.patch("sys.stdout", quiet):
                return reuse.find_reusable_run(), asked
        finally:
            reuse.api = original

    def test_bump_reaches_the_full_build_behind_a_reused_merge(self):
        url, asked = self.lookup(self.bump, {self.code})
        self.assertEqual(url, f"https://example.invalid/runs/{self.code}")
        self.assertEqual(asked, [self.merge, self.code])

    def test_bump_merge_reaches_it_too(self):
        url, _ = self.lookup(self.bump_merge, {self.code})
        self.assertEqual(url, f"https://example.invalid/runs/{self.code}")

    def test_code_change_builds(self):
        url, asked = self.lookup(self.code, {self.base})
        self.assertIsNone(url)
        self.assertEqual(asked, [])

    def test_no_full_build_anywhere_builds(self):
        url, _ = self.lookup(self.bump_merge, set())
        self.assertIsNone(url)


class WorkflowAgreementTests(unittest.TestCase):
    def test_the_full_build_step_and_job_exist_in_the_workflow(self):
        path = ROOT / reuse.WORKFLOW_PATH
        if not path.exists():  # the repo template, before setup.sh moves the workflows into place
            path = ROOT / ".github" / "workflows-template" / path.name
        workflow = path.read_text(encoding="utf-8")
        self.assertIn(f"- name: {reuse.FULL_BUILD_STEP}\n", workflow)
        self.assertRegex(workflow, re.compile(rf"^  {reuse.JOB_NAME}:$", re.MULTILINE))


if __name__ == "__main__":
    unittest.main()
