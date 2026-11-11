#!/usr/bin/env bash
#
# One-time setup for a repository made from this template. Run it once, on the
# GitHub runner Mac, from the repository root, right after "Use this template"
# (or after unzipping). It asks you to confirm the machine before anything else:
#
#   ./setup.sh
#
# It fills in every {{PLACEHOLDER}}, renames the {{APP_NAME}} folders, moves the
# workflows from .github/workflows-template/ to .github/workflows/ (they wait
# there so the template itself never runs CI), runs `make check`, deletes
# itself, commits the result on main, creates the pre-prod branch from that
# commit, and offers to push both (--yes pushes without asking).
#
# Every answer can come from the environment instead of a prompt:
#   APP_NAME=MyApp BUNDLE_ID=com.example.myapp TEAM_ID=ABCDE12345 \
#   REPO_SLUG=me/MyApp MATCH_GIT_URL=https://github.com/me/match-certs.git ./setup.sh --yes
#
# Bash 3.2 compatible (macOS's /bin/bash). Needs perl and python3 (macOS has both).

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
ROOT="$(pwd)"
YES=0
[ "${1:-}" = "--yes" ] && YES=1

if [ ! -d .github/workflows-template ] && [ -d .github/workflows ]; then
  echo "This repository looks set up already (.github/workflows exists). Nothing to do." >&2
  exit 1
fi

# Meant for the GitHub runner Mac (the machine registered as this repository's
# self-hosted runner), not a laptop. --yes skips the question.
if [ "$YES" != 1 ]; then
  echo "setup.sh turns this folder ($ROOT) into a new app, then commits and pushes it."
  echo "It's meant to run on the GitHub runner Mac. This machine is: $(hostname -s 2>/dev/null || hostname)"
  read -r -p "Is this the GitHub runner Mac? [y/N]: " go
  case "${go:-n}" in
    y|Y|yes) echo "" ;;
    *) echo "Stopped; nothing changed. Run ./setup.sh on the GitHub runner Mac."; exit 1 ;;
  esac
fi

ask() { # ask VAR "Label" "default": keeps $VAR if set in the environment
  local var="$1" label="$2" default="${3-}" input=""
  if [ -n "${!var:-}" ]; then return; fi
  if [ "$YES" = 1 ]; then
    if [ -z "$default" ]; then echo "Error: $var is required with --yes." >&2; exit 1; fi
    printf -v "$var" '%s' "$default"; return
  fi
  if [ -n "$default" ]; then
    read -r -p "$label [$default]: " input; input="${input:-$default}"
  else
    while [ -z "$input" ]; do read -r -p "$label: " input; done
  fi
  printf -v "$var" '%s' "$input"
}

if [ ! -d .git ]; then
  echo "No git repository here; creating one on branch main."
  git init -q -b main
fi

remote="$(git remote get-url origin 2>/dev/null || true)"
slug_default="$(printf '%s' "$remote" | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##')"
xcode_default="$(xcodebuild -version 2>/dev/null | head -1 | awk '{print $2}' || true)"

echo "New iOS app setup"
echo ""
ask APP_NAME              "App / Xcode target / scheme name (letters, digits, - or _)" "$(basename "$ROOT")"
case "$APP_NAME" in
  [A-Za-z]*) ;;
  *) echo "Error: the app name must start with a letter." >&2; exit 1 ;;
esac
if printf '%s' "$APP_NAME" | grep -q '[^A-Za-z0-9_-]'; then
  echo "Error: the app name may only hold letters, digits, - and _ (it names folders, the scheme and the target)." >&2
  exit 1
fi
ask DISPLAY_NAME          "Display name (home screen)" "$APP_NAME"
ask BUNDLE_ID             "Bundle ID (e.g. com.example.myapp)" ""
ask TEAM_ID               "10-character Apple Developer team ID" ""
ask REPO_SLUG             "GitHub repository (owner/name)" "${slug_default:-owner/$APP_NAME}"
ask MATCH_GIT_URL         "fastlane match vault URL (https://github.com/<owner>/<vault>.git)" ""
ask SIBLING_APPS          "Other apps signing with the same certificate (comma-separated, or 'none yet')" "none yet"
ask IOS_DEPLOYMENT_TARGET "iOS deployment target" "18.0"
ask XCODE_VERSION         "Xcode version to pin" "${xcode_default:-26.0}"
ask COPYRIGHT_HOLDER      "Copyright holder (App Store listing)" "$(git config user.name || echo "TODO")"

MODULE_NAME="$(printf '%s' "$APP_NAME" | sed -E 's/[^A-Za-z0-9_]/_/g')"
BUNDLE_ID_PREFIX="${BUNDLE_ID%.*}"
export APP_NAME DISPLAY_NAME BUNDLE_ID BUNDLE_ID_PREFIX TEAM_ID REPO_SLUG MATCH_GIT_URL SIBLING_APPS \
       IOS_DEPLOYMENT_TARGET XCODE_VERSION COPYRIGHT_HOLDER MODULE_NAME

case "$TEAM_ID" in [A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9]) ;;
  *) echo "Warning: '$TEAM_ID' doesn't look like a 10-character team ID." >&2 ;; esac
case "$BUNDLE_ID" in *.*) ;; *) echo "Warning: '$BUNDLE_ID' doesn't look like a reverse-DNS bundle ID." >&2 ;; esac

echo ""
echo "  app $APP_NAME (module $MODULE_NAME), \"$DISPLAY_NAME\", $BUNDLE_ID, team $TEAM_ID, iOS $IOS_DEPLOYMENT_TARGET, Xcode $XCODE_VERSION"
if [ "$YES" != 1 ]; then
  read -r -p "Set up the repository with these? [Y/n]: " go
  case "${go:-y}" in y|Y|yes) ;; *) echo "Aborted; nothing changed."; exit 1 ;; esac
fi

# 1. Placeholders in file contents.
files="$(grep -rIl --exclude-dir=.git --exclude=setup.sh '{{[A-Z_]*}}' . || true)"
printf '%s\n' "$files" | while IFS= read -r f; do
  [ -n "$f" ] || continue
  perl -pi -e '
    for my $k (qw(APP_NAME DISPLAY_NAME BUNDLE_ID_PREFIX BUNDLE_ID TEAM_ID REPO_SLUG MATCH_GIT_URL
                  SIBLING_APPS IOS_DEPLOYMENT_TARGET XCODE_VERSION COPYRIGHT_HOLDER MODULE_NAME)) {
      my $v = $ENV{$k}; s/\{\{$k\}\}/$v/g;
    }' "$f"
done

# 2. Placeholders in paths, deepest first so parents are renamed last.
find . -depth -name '*{{*' -not -path './.git/*' | while IFS= read -r path; do
  dir="$(dirname "$path")"; base="$(basename "$path")"
  new="${base//\{\{APP_NAME\}\}/$APP_NAME}"
  new="${new//\{\{MODULE_NAME\}\}/$MODULE_NAME}"
  mv "$path" "$dir/$new"
done

# 3. Turn CI on.
mv .github/workflows-template .github/workflows
chmod +x scripts/*.sh scripts/*.py

# 4. The README's "start here" section is about this script.
perl -0pi -e 's/<!-- template:start -->.*?<!-- template:end -->\n*//s' README.md

left="$(grep -rIl --exclude-dir=.git --exclude=setup.sh '{{[A-Z_]*}}' . || true)"
if [ -n "$left" ]; then
  echo "Warning: placeholders left in:" >&2
  printf '  %s\n' $left >&2
fi

echo ""
echo "Running make check..."
if make check >/tmp/setup-make-check.log 2>&1; then
  echo "make check passed."
else
  echo "make check FAILED; see /tmp/setup-make-check.log" >&2
fi

rm -f setup.sh

# 5. Commit on main and branch pre-prod from it: every later change comes off
#    pre-prod and returns by PR, and only pre-prod merges into main.
branch="$(git symbolic-ref --short -q HEAD || true)"
if [ "$branch" != main ]; then
  echo "Warning: on branch '${branch:-detached HEAD}', not main; committing here anyway." >&2
fi
committed=0
git add -A
if git commit -q -m "Start $DISPLAY_NAME from the iOS app template"; then
  committed=1
  echo "Committed the setup on ${branch:-HEAD}."
else
  echo "Warning: couldn't commit (is git's user.name/user.email set?). Commit by hand, then:" >&2
  echo "  git branch pre-prod" >&2
fi

pushed=0
if [ "$committed" = 1 ]; then
  if git show-ref --verify -q refs/heads/pre-prod; then
    echo "Branch pre-prod already exists; left as it is."
  else
    git branch pre-prod
    echo "Created branch pre-prod from ${branch:-HEAD}."
  fi
  if git remote get-url origin >/dev/null 2>&1 && [ "$branch" = main ]; then
    push=y
    if [ "$YES" != 1 ]; then
      read -r -p "Push main and pre-prod to origin now? [Y/n]: " push
    fi
    case "${push:-y}" in
      y|Y|yes)
        if git push -u origin main && git push -u origin pre-prod; then
          pushed=1
        else
          echo "Warning: the push failed; push by hand (step 2 below)." >&2
        fi ;;
    esac
  fi
fi

if [ "$pushed" = 1 ]; then
  step2="2. main and pre-prod are pushed. From here on, work on branches cut from
   pre-prod, merged by PR; only pre-prod merges into main."
elif [ "$committed" = 1 ]; then
  step2="2. Push main and pre-prod (setup committed the result and created pre-prod):
     git push -u origin main && git push -u origin pre-prod
   From here on, work on branches cut from pre-prod, merged by PR."
else
  step2="2. Commit, create pre-prod and push both:
     git add -A && git commit -m \"Start $DISPLAY_NAME from the iOS app template\"
     git branch pre-prod
     git push -u origin main && git push -u origin pre-prod
   From here on, work on branches cut from pre-prod, merged by PR."
fi

cat <<EOF

================================================================
Set up. Next:

1. On each Mac you build on:  make bootstrap && make test && make open
   (make bootstrap lists the Homebrew packages, fastlane included, and asks first)
$step2
3. docs/release.md: Apple identifiers and App Store Connect record, the vault
   profiles (fastlane ios certificates), the six repository secrets, the
   NOTIFY_WEBHOOK_URL variable, the rulesets in docs/github-rulesets/
   (import them now that both branches exist), and this repository's own
   runner on this Mac ("The runner Mac" section).
4. Fill in design/Documentation/docs/01 - Proposal/00-High_Level_Design.md
   and .claude/CLAUDE.md's project section.
5. In Claude Code: "release to TestFlight".
================================================================
EOF
