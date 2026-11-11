#!/usr/bin/env bash
#
# One-time setup for a repository made from this template. Run it once, from the
# repository root, right after "Use this template" (or after unzipping):
#
#   ./setup.sh
#
# It fills in every {{PLACEHOLDER}}, renames the {{APP_NAME}} folders, moves the
# workflows from .github/workflows-template/ to .github/workflows/ (they wait
# there so the template itself never runs CI), runs `make check`, and deletes
# itself. Commit the result.
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

cat <<EOF

================================================================
Set up. Next:

1. On a Mac:  make bootstrap && make test && make open
2. Commit and push to main, then create pre-prod from it:
     git add -A && git commit -m "Start $DISPLAY_NAME from the iOS app template"
     git push -u origin main && git push origin main:pre-prod
   From here on, work on branches cut from pre-prod, merged by PR.
3. docs/release.md: Apple identifiers and App Store Connect record, the vault
   profiles (fastlane ios certificates), the six repository secrets, the
   NOTIFY_WEBHOOK_URL variable, the rulesets in docs/github-rulesets/,
   and a self-hosted runner for this repository.
4. Fill in design/Documentation/docs/01 - Proposal/00-High_Level_Design.md
   and .claude/CLAUDE.md's project section.
5. In Claude Code: "release to TestFlight".
================================================================
EOF
