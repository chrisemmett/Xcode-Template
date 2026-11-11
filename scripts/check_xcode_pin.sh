#!/usr/bin/env bash
#
# Check the runner's Xcode against the pin in .xcode-version.
#
#   scripts/check_xcode_pin.sh major   # build.yml: fail on a MAJOR mismatch, warn on drift
#   scripts/check_xcode_pin.sh exact   # release.yml: fail on any mismatch at the pin's precision
#
# Why two modes. A runner's Xcode moving 26 -> 27 changes the SDK the app is
# built against, and it happens unannounced, so the merge gate fails on it.
# Minor and patch drift happen without anyone deciding anything; failing the
# gate on them would train everyone to bump the pin reflexively, which is how a
# pin becomes a formality. A release is different: it produces the binary the
# pin describes, and the Xcode decides behaviour users get, so the release path
# fails on any mismatch. A pin of "27.1" accepts 27.1 and 27.1.x; a pin of
# "27.1.1" accepts only that. Fix a failure by deciding which Xcode should ship
# (update the runner or the pin), never by editing this script.
#
# XCODE_VERSION_OVERRIDE lets the self-test fake the runner's version.

set -euo pipefail

mode="${1:-major}"
if [ ! -f .xcode-version ]; then
  echo "::warning::No .xcode-version pin in this repository; skipping the check."
  exit 0
fi
pinned="$(tr -d '[:space:]' < .xcode-version)"
actual="${XCODE_VERSION_OVERRIDE:-$(xcodebuild -version | head -1 | awk '{print $2}')}"
echo "pinned=$pinned actual=$actual"

case "$mode" in
  exact)
    case "$actual" in
      "$pinned"|"$pinned".*)
        echo "Xcode $actual matches .xcode-version $pinned." ;;
      *)
        echo "::error::Xcode $actual does not match .xcode-version $pinned. A release must be built with the pinned Xcode: update the runner or bump .xcode-version deliberately, then re-run." >&2
        exit 1 ;;
    esac
    ;;
  major)
    if [ "$pinned" = "$actual" ]; then
      echo "Xcode matches .xcode-version."
    elif [ "${pinned%%.*}" != "${actual%%.*}" ]; then
      echo "::error::Xcode major version mismatch: .xcode-version pins $pinned, runner has $actual. If the upgrade was deliberate, update .xcode-version in the same commit as whatever the new SDK changed." >&2
      exit 1
    else
      echo "::warning::Xcode drift: .xcode-version pins $pinned, runner has $actual. Update the pin when convenient."
    fi
    ;;
  *)
    echo "usage: check_xcode_pin.sh [major|exact]" >&2
    exit 2
    ;;
esac
