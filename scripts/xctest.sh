#!/usr/bin/env bash
#
# Run `xcodebuild test` on a freshly booted simulator, with a bounded retry that
# re-runs ONLY known simulator-launch flakes.
#
#   scripts/xctest.sh <iOS|tvOS|watchOS> <scheme> [extra xcodebuild args...]
#
# Environment:
#   MIN_OS          deployment target (the Makefile reads it from project.yml)
#   SIM_NAME        device-name regex for pick_simulator.sh (optional)
#   SIM_UDID        use this simulator instead of picking one (optional)
#   SIM_ERASE=1     erase the device first (UI tests: a clean device means
#                   default settings). Erases ONLY this device, never `erase all`.
#   RESULT_BUNDLE   where to write the .xcresult (default build/<scheme>.xcresult)
#   XCODEBUILD      the xcodebuild command line (the Makefile passes its own)
#   MAX_ATTEMPTS    default 3
#
# The retries are for failures that happen before any test runs, so they can't
# hide a real test failure or a compile error, which print something else and
# exit non-zero on the first attempt:
#   - "Application failed preflight checks" (FBSOpenApplicationErrorDomain 6):
#     a CoreSimulator left wedged by an earlier job on the self-hosted runner.
#   - "before establishing connection": the test host was killed while a cold
#     simulator was still finishing its boot (seen on watchOS). Booting with
#     `simctl bootstatus -b`, which waits for the boot to FINISH rather than for
#     the device to say "Booted", closes most of that window; the retry covers
#     the rest.

set -uo pipefail

platform="${1:?usage: xctest.sh <iOS|tvOS|watchOS> <scheme> [xcodebuild args...]}"
scheme="${2:?usage: xctest.sh <iOS|tvOS|watchOS> <scheme> [xcodebuild args...]}"
shift 2

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
xcodebuild_cmd="${XCODEBUILD:-xcodebuild}"
result="${RESULT_BUNDLE:-build/$scheme.xcresult}"
max_attempts="${MAX_ATTEMPTS:-3}"

udid="${SIM_UDID:-}"
if [ -z "$udid" ]; then
  udid="$("$here/pick_simulator.sh" "$platform" "${MIN_OS:-0}" "${SIM_NAME:-}")" || exit 1
fi
echo "Testing $scheme on $platform simulator $udid"

boot() {
  # -b boots the device if needed, then blocks until the boot has finished.
  xcrun simctl bootstatus "$udid" -b >/dev/null
}

if [ "${SIM_ERASE:-0}" = 1 ]; then
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  xcrun simctl erase "$udid" || echo "::warning::Could not erase $udid; running on a device that was NOT erased."
fi
boot

attempt=1
while :; do
  log="$(mktemp)"
  rm -rf "$result"
  # shellcheck disable=SC2086  # XCODEBUILD is a command line on purpose.
  if $xcodebuild_cmd test \
      -scheme "$scheme" \
      -destination "id=$udid" \
      -resultBundlePath "$result" \
      -skipPackagePluginValidation \
      "$@" 2>&1 | tee "$log"; then
    rm -f "$log"
    exit 0
  fi
  if [ "$attempt" -lt "$max_attempts" ] && \
     grep -qE "Application failed preflight checks|before establishing connection" "$log"; then
    echo "::warning::Simulator launch flake on attempt $attempt/$max_attempts; rebooting $udid and retrying."
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    sleep 5
    boot
    attempt=$((attempt + 1))
    continue
  fi
  exit 1
done
