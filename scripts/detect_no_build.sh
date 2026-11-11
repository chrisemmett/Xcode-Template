#!/usr/bin/env bash
#
# Decide whether a push changes anything the build reads. Writes
# `no_build=true|false` to $GITHUB_OUTPUT (or stdout when run by hand).
#
# Environment: REF (github.ref), EVENT (github.event_name), REUSE_RUN (the URL
# from ci_reuse_build.py, if it found a green full build of the same files).
#
# The job always runs, so the required `build` check always reports: a skipped
# job would leave a PR at "Expected" forever. Only the Xcode work is skipped.
#
# The diff is against the MERGE-BASE with where the branch will merge, not the
# previous push and not the target's tip:
#   - previous push: a docs-only commit on top of a failing code commit would
#     turn the branch green.
#   - target's tip (`git diff origin/pre-prod HEAD`): includes, reversed,
#     everything that landed on pre-prod since the branch was cut, so an
#     up-to-date docs branch looks like a code change and vice versa.
#
#   dev branches  -> merge-base with origin/pre-prod
#   pre-prod      -> merge-base with origin/main (its check gates the release PR)
#   main, dispatch, anything unclassifiable -> the full build (fails safe)
#
# Bash 3.2 compatible.

set -euo pipefail

INTEGRATION_BRANCH="${INTEGRATION_BRANCH:-pre-prod}"
RELEASE_BRANCH="${RELEASE_BRANCH:-main}"

# Paths the build never reads (extended regexes, one per line). Everything else
# builds, including project.yml, Brewfile, .swiftlint.yml, .swiftformat, Config/
# and scripts/. Workflows are here on purpose: a CI-only change gets the quick
# run, and a broken step shows on the next push that builds.
NO_BUILD_PATTERNS='\.md$
^docs/
^design/
^\.claude/
^LICENSE$
^\.github/workflows/
^fastlane/
^Gemfile(\.lock)?$
^\.xcode-version$'

out="${GITHUB_OUTPUT:-/dev/stdout}"

if [ -n "${REUSE_RUN:-}" ]; then
  echo "no_build=true" >> "$out"
  echo "::notice::These files (build number aside) already passed the full build in $REUSE_RUN; skipping the Xcode work."
  exit 0
fi

base=""
if [ "${EVENT:-}" = "push" ]; then
  case "${REF:-}" in
    "refs/heads/$RELEASE_BRANCH") base="" ;;
    "refs/heads/$INTEGRATION_BRANCH") base="origin/$RELEASE_BRANCH" ;;
    refs/heads/*) base="origin/$INTEGRATION_BRANCH" ;;
  esac
fi

no_build=false
if [ -n "$base" ] && git rev-parse --verify --quiet "$base" >/dev/null; then
  merge_base="$(git merge-base "$base" HEAD)"
  changed="$(git diff --no-renames --name-only "$merge_base" HEAD)"
  echo "Changed since the merge-base with $base (${merge_base:0:12}):"
  printf '%s\n' "$changed" | sed 's/^/  /'
  if [ -n "$changed" ]; then
    patterns_file="$(mktemp)"
    printf '%s\n' "$NO_BUILD_PATTERNS" > "$patterns_file"
    build_files="$(printf '%s\n' "$changed" | grep -Ev -f "$patterns_file" || true)"
    rm -f "$patterns_file"
    if [ -z "$build_files" ]; then
      no_build=true
    else
      echo "Files that build:"
      printf '%s\n' "$build_files" | sed 's/^/  /'
    fi
  fi
fi

echo "no_build=$no_build" >> "$out"
if [ "$no_build" = true ]; then
  echo "::notice::Only docs, CI and release files changed; skipping lint, tests and the Xcode build."
else
  echo "Full build."
fi
