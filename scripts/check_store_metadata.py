#!/usr/bin/env python3
"""Check the App Store metadata under fastlane/metadata against App Store Connect's limits.

`make check` runs it on every push, so CI fails on text that wouldn't fit long before anyone tries
to upload it. The `metadata` lane runs it with `--release` first, which also refuses any field
still marked TODO, so a placeholder never reaches App Store Connect.

Two layouts are understood, and found by looking:

  flat (one platform)            per platform (an app on iOS and tvOS, say)
  fastlane/metadata/             fastlane/metadata/
    copyright.txt                  ios/   copyright.txt, primary_category.txt, en-GB/, ...
    primary_category.txt           tvos/  the same
    en-GB/ name.txt, ...
    review_information/notes.txt

In the per-platform layout the name, subtitle, privacy URL, copyright and category belong to the
one app record every platform shares, so they must agree across the platform folders; the
description, keywords, promotional text, release notes and other URLs belong to each platform's
App Store version and may differ.

With no fastlane/metadata at all it passes, so a new project isn't failed before it has a listing.
"""

import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
METADATA = ROOT / "fastlane" / "metadata"
PLATFORM_DIRS = ("ios", "tvos", "macos", "visionos")
LOCALE = re.compile(r"^[a-z]{2,3}(-[A-Za-z]{2,4})?(-[A-Z]{2})?$")

# App Store Connect's limits, in characters.
LIMITS = {
    "name.txt": 30,
    "subtitle.txt": 30,
    "keywords.txt": 100,
    "promotional_text.txt": 170,
    "description.txt": 4000,
    "release_notes.txt": 4000,
}
REVIEW_NOTES_LIMIT = 4000
REQUIRED = ("name.txt", "description.txt", "keywords.txt", "support_url.txt", "privacy_url.txt")
SINGLE_LINE = ("name.txt", "subtitle.txt", "keywords.txt", "support_url.txt", "marketing_url.txt", "privacy_url.txt")
URLS = ("support_url.txt", "marketing_url.txt", "privacy_url.txt")
APP_INFO_LOCALISED = ("name.txt", "subtitle.txt", "privacy_url.txt")
APP_INFO_ROOT = ("copyright.txt", "primary_category.txt")
# App Store Connect's category IDs, as deliver takes them.
CATEGORIES = {
    "BOOKS", "BUSINESS", "DEVELOPER_TOOLS", "EDUCATION", "ENTERTAINMENT", "FINANCE", "FOOD_AND_DRINK",
    "GAMES", "GRAPHICS_AND_DESIGN", "HEALTH_AND_FITNESS", "LIFESTYLE", "MAGAZINES_AND_NEWSPAPERS",
    "MEDICAL", "MUSIC", "NAVIGATION", "NEWS", "PHOTO_AND_VIDEO", "PRODUCTIVITY", "REFERENCE",
    "SHOPPING", "SOCIAL_NETWORKING", "SPORTS", "STICKERS", "TRAVEL", "UTILITIES", "WEATHER",
}
PLACEHOLDER = "TODO"


def read(path):
    return path.read_text(encoding="utf-8").strip() if path.exists() else None


def platforms():
    """The platform folders, or [None] for the flat layout, or [] when there is no metadata."""
    if not METADATA.is_dir():
        return []
    found = [name for name in PLATFORM_DIRS if (METADATA / name).is_dir()]
    return found or [None]


def base(platform):
    return METADATA / platform if platform else METADATA


def label(platform, *parts):
    return "/".join(p for p in (platform, *parts) if p)


def locales(platform):
    return sorted(p.name for p in base(platform).iterdir() if p.is_dir() and LOCALE.match(p.name))


def check_field(where, name, text, release, problems):
    if text is None:
        if name in REQUIRED:
            problems.append(f"{where}/{name}: missing")
        return
    if PLACEHOLDER in text:
        if release:
            problems.append(f"{where}/{name}: still a placeholder ({PLACEHOLDER}); fill it in before uploading")
        return
    if not text and name in REQUIRED:
        problems.append(f"{where}/{name}: empty")
    limit = LIMITS.get(name)
    if limit is not None and len(text) > limit:
        problems.append(f"{where}/{name}: {len(text)} characters, over App Store Connect's {limit}")
    if name in SINGLE_LINE and "\n" in text:
        problems.append(f"{where}/{name}: must be one line")
    if name in URLS and text and not text.startswith("https://"):
        problems.append(f"{where}/{name}: must be an https:// address")
    if name == "keywords.txt":
        raw = text.split(",")
        words = [word.strip() for word in raw]
        if any(not word for word in words):
            problems.append(f"{where}/{name}: an empty keyword (doubled or trailing comma)")
        if len({word.lower() for word in words}) != len(words):
            problems.append(f"{where}/{name}: a keyword is repeated")
        if any(word != r for word, r in zip(words, raw)):
            problems.append(f"{where}/{name}: spaces around commas count against the 100 characters")


def check_platform(platform, release, problems):
    root = base(platform)
    for name in APP_INFO_ROOT:
        text = read(root / name)
        if not text:
            problems.append(f"{label(platform, name)}: missing")
        elif name == "primary_category.txt" and text not in CATEGORIES:
            problems.append(f"{label(platform, name)}: '{text}' is not an App Store category ID")
    found = locales(platform)
    if not found:
        problems.append(f"{label(platform, '<locale>')}: no locale folder (for example en-GB/)")
    for locale in found:
        folder = root / locale
        names = set(LIMITS) | set(REQUIRED) | set(URLS) | {path.name for path in folder.glob("*.txt")}
        for name in sorted(names):
            check_field(label(platform, locale), name, read(folder / name), release, problems)
    notes = read(root / "review_information" / "notes.txt")
    where = label(platform, "review_information/notes.txt")
    if not notes:
        problems.append(f"{where}: missing")
    elif len(notes) > REVIEW_NOTES_LIMIT:
        problems.append(f"{where}: {len(notes)} characters, over {REVIEW_NOTES_LIMIT}")
    elif release and PLACEHOLDER in notes:
        problems.append(f"{where}: still a placeholder ({PLACEHOLDER})")


def check_shared(chosen, problems):
    first, *others = chosen
    for other in others:
        for name in APP_INFO_ROOT:
            if read(base(first) / name) != read(base(other) / name):
                problems.append(f"{name}: differs between {first} and {other}, but the app record has one")
        for locale in sorted(set(locales(first)) & set(locales(other))):
            for name in APP_INFO_LOCALISED:
                if read(base(first) / locale / name) != read(base(other) / locale / name):
                    problems.append(f"{locale}/{name}: differs between {first} and {other}, but the app record has one")


def check(chosen, release):
    problems = []
    for platform in chosen:
        check_platform(platform, release, problems)
    if len(chosen) > 1:
        check_shared(chosen, problems)
    return problems


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--release", action="store_true", help="also refuse fields still marked TODO")
    parser.add_argument("--platform", help="check one platform folder (the shared fields are then not compared)")
    args = parser.parse_args(argv)
    available = platforms()
    if not available:
        print("No fastlane/metadata; nothing to check.")
        return 0
    if args.platform:
        if args.platform not in available:
            print(f"error: fastlane/metadata/{args.platform} doesn't exist (found: {available})")
            return 1
        chosen = [args.platform]
    else:
        chosen = available
    problems = check(chosen, args.release)
    for problem in problems:
        print(f"error: fastlane/metadata: {problem}")
    if problems:
        return 1
    shown = ", ".join(p or "app" for p in chosen)
    print(f"App Store metadata OK: {shown}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
