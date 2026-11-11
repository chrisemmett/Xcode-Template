#!/usr/bin/env bash
#
# Print the UDID of an available simulator to test on.
#
#   scripts/pick_simulator.sh <iOS|tvOS|watchOS> [min-version] [name-regex]
#
#   min-version  the deployment target; runtimes below it are skipped, because
#                xcodebuild refuses a destination below the floor. Default 0.
#   name-regex   an awk regex matched against the device name. Defaults:
#                iOS "iPhone", tvOS "Apple TV", watchOS "Apple Watch".
#
# SIM_STRATEGY=lowest (default) takes the LOWEST installed runtime that meets
# the floor, so tests run on the oldest OS you support. SIM_STRATEGY=newest
# takes the newest runtime instead.
#
# Why not a fixed `name=iPhone 17` destination: an Xcode update renames the
# device line-up (Series 10 -> 11) and the runner keeps old runtimes beside new
# ones, so a pinned name breaks CI with "Unable to find a device matching the
# provided destination specifier" while the code is green, and a bare name can
# be ambiguous across runtimes. A UDID is neither.
#
# Bash 3.2 and BSD awk compatible (it runs on the macOS runner). awk reads all
# of simctl's output (no early exit), so a caller's pipefail can't trip on a
# SIGPIPE'd simctl.

set -euo pipefail

platform="${1:?usage: pick_simulator.sh <iOS|tvOS|watchOS> [min-version] [name-regex]}"
min="${2:-0}"
case "$platform" in
  iOS)     default_name="iPhone" ;;
  tvOS)    default_name="Apple TV" ;;
  watchOS) default_name="Apple Watch" ;;
  *) echo "pick_simulator.sh: unknown platform '$platform'" >&2; exit 2 ;;
esac
name="${3:-$default_name}"
strategy="${SIM_STRATEGY:-lowest}"

# SIMCTL_LIST lets the self-test feed canned output.
listing="${SIMCTL_LIST:-$(xcrun simctl list devices available)}"

udid="$(printf '%s\n' "$listing" | awk -v platform="$platform" -v min="$min" -v name="$name" -v strategy="$strategy" '
  function ver(v,  p) { split(v, p, "."); return p[1] * 10000 + p[2] * 100 + p[3] }
  BEGIN { header = "^-- " platform " [0-9.]+ --$"; floor = ver(min); best = -1 }
  $0 ~ header { cur = ver($3); next }
  /^-- / { cur = -1; next }
  cur >= floor && cur >= 0 {
    line = $0; sub(/^ +/, "", line)
    if (index(line, " (") == 0) next
    dev = substr(line, 1, index(line, " (") - 1)
    if (dev !~ ("^" name)) next
    if (!match($0, /\([0-9A-F]+-[0-9A-F]+-[0-9A-F]+-[0-9A-F]+-[0-9A-F]+\)/)) next
    id = substr($0, RSTART + 1, RLENGTH - 2)
    better = (best < 0) || (strategy == "newest" ? cur > best : cur < best)
    if (better) { best = cur; found = id }
  }
  END { print found }')"

if [ -z "$udid" ]; then
  echo "::error::No available $platform simulator matching '$name' on $platform $min or later." >&2
  exit 1
fi
echo "$udid"
