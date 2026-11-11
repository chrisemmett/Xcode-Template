#!/usr/bin/env python3
"""Self-test of the CI shell scripts against canned input, so a broken script fails `make check`
on the fast path instead of breaking the next full build.

Run with `make test-scripts`, or `python3 -B -m unittest discover -s scripts -p 'test_*.py'`.
Needs bash and git; runs on macOS and Linux.
"""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent

SIMCTL = """\
== Devices ==
-- iOS 26.5 --
    iPhone 17 (11111111-1111-1111-1111-111111111111) (Shutdown)
-- iOS 27.0 --
    iPad (A16) (22222222-2222-2222-2222-222222222222) (Shutdown)
    iPhone 17 Pro (33333333-3333-3333-3333-333333333333) (Shutdown)
-- iOS 27.1 --
    iPhone 18 (44444444-4444-4444-4444-444444444444) (Booted)
-- tvOS 27.0 --
    Apple TV 4K (3rd generation) (55555555-5555-5555-5555-555555555555) (Shutdown)
-- watchOS 26.0 --
    Apple Watch Series 10 (46mm) (66666666-6666-6666-6666-666666666666) (Shutdown)
-- watchOS 27.0 --
    Apple Watch Series 11 (46mm) (77777777-7777-7777-7777-777777777777) (Shutdown)
"""


def run(script, *args, env=None, cwd=None):
    return subprocess.run(["bash", str(SCRIPTS / script), *args], capture_output=True, text=True,
                          env={**os.environ, **(env or {})}, cwd=cwd)


class PickSimulatorTests(unittest.TestCase):
    def pick(self, *args, **env):
        result = run("pick_simulator.sh", *args, env={"SIMCTL_LIST": SIMCTL, **env})
        return result.stdout.strip() if result.returncode == 0 else None

    def test_lowest_runtime_meeting_the_floor(self):
        self.assertEqual(self.pick("iOS", "27.0"), "33333333-3333-3333-3333-333333333333")

    def test_hex_looking_model_names_are_not_udids(self):
        # "iPad (A16)" sits first under iOS 27.0; the iPhone filter and the UDID shape both skip it.
        self.assertEqual(self.pick("iOS", "27.0", "iPad"), "22222222-2222-2222-2222-222222222222")

    def test_newest_strategy(self):
        self.assertEqual(self.pick("iOS", "27.0", SIM_STRATEGY="newest"), "44444444-4444-4444-4444-444444444444")

    def test_watch_below_the_floor_is_skipped(self):
        self.assertEqual(self.pick("watchOS", "27.0"), "77777777-7777-7777-7777-777777777777")

    def test_tvos(self):
        self.assertEqual(self.pick("tvOS", "27.0"), "55555555-5555-5555-5555-555555555555")

    def test_nothing_meets_the_floor(self):
        self.assertIsNone(self.pick("iOS", "28.0"))


class XcodePinTests(unittest.TestCase):
    def check(self, mode, pinned, actual):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, ".xcode-version").write_text(pinned + "\n", encoding="utf-8")
            return run("check_xcode_pin.sh", mode, env={"XCODE_VERSION_OVERRIDE": actual}, cwd=directory)

    def test_major_mode(self):
        self.assertEqual(self.check("major", "27.1", "27.1").returncode, 0)
        drift = self.check("major", "27.1", "27.2")
        self.assertEqual(drift.returncode, 0)
        self.assertIn("::warning::", drift.stdout)
        self.assertEqual(self.check("major", "27.1", "28.0").returncode, 1)

    def test_exact_mode(self):
        self.assertEqual(self.check("exact", "27.1", "27.1").returncode, 0)
        self.assertEqual(self.check("exact", "27.1", "27.1.1").returncode, 0)
        self.assertEqual(self.check("exact", "27.1", "27.10").returncode, 1)
        self.assertEqual(self.check("exact", "27.1.1", "27.1").returncode, 1)
        self.assertEqual(self.check("exact", "27.1", "27.2").returncode, 1)


class DetectNoBuildTests(unittest.TestCase):
    """A real repository: main, pre-prod ahead of it with code, and branches off pre-prod."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.env = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.invalid",
                    "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.invalid"}
        self.git("init", "-q", "-b", "main")
        self.commit("App/a.swift", "let a = 1\n")
        self.git("checkout", "-q", "-b", "pre-prod")
        self.commit("App/b.swift", "let b = 1\n")
        # The workflow sees remote-tracking refs; fake them.
        self.git("update-ref", "refs/remotes/origin/main", "main")
        self.git("update-ref", "refs/remotes/origin/pre-prod", "pre-prod")

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.dir, check=True, capture_output=True, text=True,
                              env={**os.environ, **self.env}).stdout.strip()

    def commit(self, path, text):
        target = self.dir / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")
        self.git("add", "-A")
        self.git("commit", "-q", "-m", path)

    def detect(self, ref, event="push", reuse=""):
        out = self.dir / "out.txt"
        out.write_text("", encoding="utf-8")
        result = run("detect_no_build.sh", cwd=self.dir,
                     env={"REF": ref, "EVENT": event, "REUSE_RUN": reuse, "GITHUB_OUTPUT": str(out)})
        self.assertEqual(result.returncode, 0, result.stderr)
        return out.read_text(encoding="utf-8").strip()

    def test_docs_only_branch(self):
        self.git("checkout", "-q", "-b", "docs")
        self.commit("docs/HLD.md", "# HLD\n")
        self.commit(".claude/skills/x/SKILL.md", "x\n")
        self.assertEqual(self.detect("refs/heads/docs"), "no_build=true")

    def test_code_then_docs_still_builds(self):
        self.git("checkout", "-q", "-b", "feature")
        self.commit("App/c.swift", "let c = 1\n")
        self.commit("README.md", "readme\n")
        self.assertEqual(self.detect("refs/heads/feature"), "no_build=false")

    def test_docs_branch_stays_docs_after_pre_prod_moves_on(self):
        # The two-dot diff against origin/pre-prod's tip would see App/d.swift (reversed) and build.
        self.git("checkout", "-q", "-b", "docs")
        self.commit("docs/HLD.md", "# HLD\n")
        self.git("checkout", "-q", "pre-prod")
        self.commit("App/d.swift", "let d = 1\n")
        self.git("update-ref", "refs/remotes/origin/pre-prod", "pre-prod")
        self.git("checkout", "-q", "docs")
        self.assertEqual(self.detect("refs/heads/docs"), "no_build=true")

    def test_project_yml_builds(self):
        self.git("checkout", "-q", "-b", "bump")
        self.commit("project.yml", "name: X\n")
        self.assertEqual(self.detect("refs/heads/bump"), "no_build=false")

    def test_pre_prod_compares_with_main(self):
        self.git("checkout", "-q", "pre-prod")
        self.assertEqual(self.detect("refs/heads/pre-prod"), "no_build=false")

    def test_main_and_dispatch_always_build(self):
        self.git("checkout", "-q", "main")
        self.commit("README.md", "readme\n")
        self.assertEqual(self.detect("refs/heads/main"), "no_build=false")
        self.assertEqual(self.detect("refs/heads/pre-prod", event="workflow_dispatch"), "no_build=false")

    def test_reuse_takes_the_fast_path(self):
        self.assertEqual(self.detect("refs/heads/anything", reuse="https://example.invalid/run/1"), "no_build=true")


class NotifyTests(unittest.TestCase):
    def payload(self, **env):
        base = {"DRY_RUN": "1", "REPO": "o/r", "RUN_ID": "9", "REF_NAME": "feature", "STATUS": "success"}
        result = run("notify.sh", env={**base, **env})
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_passing_build_is_silent(self):
        body = self.payload(KIND="build")
        self.assertTrue(body["silent"])
        self.assertTrue(body["message"].startswith("✅ Build passed · feature"))
        self.assertIn("https://github.com/o/r/actions/runs/9", body["message"])

    def test_failure_and_release_make_a_sound(self):
        self.assertFalse(self.payload(KIND="build", STATUS="failure")["silent"])
        release = self.payload(KIND="testflight", REF_NAME="testflight-42", PLATFORMS="iPhone and iPad")
        self.assertFalse(release["silent"])
        self.assertIn("TestFlight build 42 uploaded (iPhone and iPad)", release["message"])

    def test_awkward_ref_names_stay_valid_json(self):
        body = self.payload(REF_NAME='we"ird\\ref\tname')
        self.assertIn('we"ird\\ref name', body["message"])

    def test_no_webhook_is_not_an_error(self):
        result = run("notify.sh", env={"NOTIFY_WEBHOOK_URL": "", "STATUS": "success"})
        self.assertEqual(result.returncode, 0)
        self.assertIn("not notifying", result.stdout)


class LldTodoDoneTests(unittest.TestCase):
    def check(self, todo, done):
        with tempfile.TemporaryDirectory() as directory:
            lld = Path(directory, "lld")
            (lld / "todo").mkdir(parents=True)
            (lld / "done").mkdir()
            for name in todo:
                (lld / "todo" / name).write_text("x", encoding="utf-8")
            for name in done:
                (lld / "done" / name).write_text("x", encoding="utf-8")
            return run("check_lld_todo_done.sh", env={"LLD_DIR": str(lld)})

    def test_clean(self):
        self.assertEqual(self.check(["002-b.md"], ["001-a.md"]).returncode, 0)

    def test_empty_todo(self):
        self.assertEqual(self.check([], ["001-a.md"]).returncode, 0)

    def test_duplicate_number(self):
        result = self.check(["001-a.md"], ["001-a-shipped.md"])
        self.assertEqual(result.returncode, 1)
        self.assertIn("todo/001-a.md", result.stderr)


if __name__ == "__main__":
    unittest.main()
