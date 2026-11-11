#!/usr/bin/env python3
"""Self-test of check_store_metadata.py against generated metadata in both layouts.

Run with `make test-scripts`, or `python3 -B -m unittest discover -s scripts -p 'test_*.py'`.
"""

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check_store_metadata as check  # noqa: E402

VALID = {
    "name.txt": "My App",
    "subtitle.txt": "Does a thing",
    "description.txt": "A longer description.",
    "keywords.txt": "one,two,three",
    "support_url.txt": "https://example.com/support",
    "privacy_url.txt": "https://example.com/privacy",
    "release_notes.txt": "Bug fixes.",
}


def write_platform(root, locales=("en-GB", "en-US")):
    root.mkdir(parents=True, exist_ok=True)
    (root / "copyright.txt").write_text("2026 Someone\n", encoding="utf-8")
    (root / "primary_category.txt").write_text("UTILITIES\n", encoding="utf-8")
    (root / "review_information").mkdir(exist_ok=True)
    (root / "review_information" / "notes.txt").write_text("Notes for review.\n", encoding="utf-8")
    for locale in locales:
        (root / locale).mkdir(exist_ok=True)
        for name, text in VALID.items():
            (root / locale / name).write_text(text + "\n", encoding="utf-8")


class Base(unittest.TestCase):
    layout = "flat"

    def setUp(self):
        self.original = check.METADATA
        self.directory = tempfile.TemporaryDirectory()
        self.metadata = Path(self.directory.name) / "metadata"
        if self.layout == "flat":
            write_platform(self.metadata)
        else:
            write_platform(self.metadata / "ios")
            write_platform(self.metadata / "tvos")
        check.METADATA = self.metadata

    def tearDown(self):
        check.METADATA = self.original
        self.directory.cleanup()

    def write(self, relative, text):
        path = self.metadata / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def problems(self, release=False):
        return check.check(check.platforms(), release)


class FlatLayoutTests(Base):
    def test_valid_metadata_passes(self):
        self.assertEqual(check.platforms(), [None])
        self.assertEqual(self.problems(release=True), [])

    def test_placeholders_pass_on_every_push_but_not_for_release(self):
        self.write("en-US/support_url.txt", "TODO: support page\n")
        self.assertEqual(self.problems(), [])
        release = self.problems(release=True)
        self.assertEqual(len(release), 1)
        self.assertIn("en-US/support_url.txt: still a placeholder", release[0])

    def test_limits(self):
        for name, limit in {"subtitle.txt": 30, "keywords.txt": 100, "promotional_text.txt": 170,
                            "description.txt": 4000}.items():
            with self.subTest(name=name):
                self.write(f"en-GB/{name}", "a" * limit)
                self.assertFalse([p for p in self.problems() if f"en-GB/{name}" in p])
                self.write(f"en-GB/{name}", "a" * (limit + 1))
                self.assertTrue([p for p in self.problems() if f"en-GB/{name}: {limit + 1} characters" in p])

    def test_keywords(self):
        self.write("en-US/keywords.txt", "music, film")
        self.assertTrue(any("spaces around commas" in p for p in self.problems()))
        self.write("en-US/keywords.txt", "music,,film")
        self.assertTrue(any("empty keyword" in p for p in self.problems()))
        self.write("en-US/keywords.txt", "music,Music")
        self.assertTrue(any("repeated" in p for p in self.problems()))

    def test_urls_must_be_https(self):
        self.write("en-US/marketing_url.txt", "http://example.com")
        self.assertTrue(any("en-US/marketing_url.txt: must be an https://" in p for p in self.problems()))

    def test_one_line_fields(self):
        self.write("en-GB/name.txt", "My\nApp\n")
        self.assertIn("en-GB/name.txt: must be one line", self.problems())

    def test_missing_required_field_and_bad_category(self):
        (self.metadata / "en-GB/description.txt").unlink()
        self.write("primary_category.txt", "Utilities")
        problems = self.problems()
        self.assertIn("en-GB/description.txt: missing", problems)
        self.assertTrue(any("'Utilities' is not an App Store category ID" in p for p in problems))

    def test_review_notes_limit(self):
        self.write("review_information/notes.txt", "a" * 4001)
        self.assertTrue(any("notes.txt: 4001 characters" in p for p in self.problems()))

    def test_review_folder_is_not_a_locale(self):
        self.assertEqual(check.locales(None), ["en-GB", "en-US"])


class PerPlatformLayoutTests(Base):
    layout = "platforms"

    def test_valid_metadata_passes(self):
        self.assertEqual(check.platforms(), ["ios", "tvos"])
        self.assertEqual(self.problems(release=True), [])

    def test_shared_fields_must_agree(self):
        self.write("ios/en-GB/name.txt", "Other Name\n")
        self.assertTrue(any("en-GB/name.txt: differs between ios and tvos" in p for p in self.problems()))

    def test_per_version_fields_may_differ(self):
        self.write("tvos/en-GB/description.txt", "The Apple TV description.\n")
        self.assertEqual(self.problems(), [])

    def test_one_platform(self):
        self.assertEqual(check.main(["--platform", "ios"]), 0)
        self.assertEqual(check.main(["--platform", "macos"]), 1)


class NoMetadataTests(unittest.TestCase):
    def test_passes(self):
        original = check.METADATA
        check.METADATA = Path(tempfile.gettempdir()) / "definitely-not-here-metadata"
        try:
            self.assertEqual(check.platforms(), [])
            self.assertEqual(check.main([]), 0)
        finally:
            check.METADATA = original


if __name__ == "__main__":
    unittest.main()
