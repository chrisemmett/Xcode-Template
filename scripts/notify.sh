#!/usr/bin/env bash
#
# Post a CI result to a chat webhook (for example an n8n flow that forwards to
# Telegram).
#
# Called by the last step of every workflow. Everything arrives through the
# step's env: block, never through ${{ }} inside run:, so nothing GitHub
# substitutes is ever parsed as shell.
#
#   NOTIFY_WEBHOOK_URL  where to POST; empty or unset means "don't notify"
#                       (set it as a repository or organisation VARIABLE)
#   KIND          build | testflight | ui-tests | screenshots (else shown as-is)
#   STATUS        ${{ job.status }}: success | failure | cancelled
#   REF_NAME      ${{ github.ref_name }}
#   REPO          ${{ github.repository }}
#   RUN_ID        ${{ github.run_id }}
#   JOB_STARTED   epoch seconds, written to $GITHUB_ENV by the job's first step
#   NO_BUILD      optional; "true" when the run took the nothing-to-build path
#   BUILD_NUMBER  optional; for a workflow_dispatch release (no testflight-<N> ref)
#   PLATFORMS     optional; what a TestFlight build ships to
#   DRY_RUN       optional; "1" prints the JSON payload instead of sending it
#
# The message is a few lines of plain text:
#
#   ✅ Build passed · pre-prod
#   Fix the kick arc (1a2b3c4)
#   ⏱ 14m 32s
#   https://github.com/<repo>/actions/runs/<id>
#
# and goes out as {"message": "...", "silent": true|false}. Only a passing
# ordinary build is silent; failures, cancellations and releases make a sound.
#
# A notification must never fail the job, so this always exits 0 (the step also
# has continue-on-error). Bash 3.2 compatible, no jq or python needed.

WEBHOOK_URL="${NOTIFY_WEBHOOK_URL:-}"

kind="${KIND:-build}"
status="${STATUS:-unknown}"
ref="${REF_NAME:-unknown ref}"

case "$status" in
  success)   icon="✅"; verb="passed" ;;
  failure)   icon="❌"; verb="failed" ;;
  cancelled) icon="⏹️"; verb="cancelled" ;;
  *)         icon="⚠️"; verb="$status" ;;
esac

silent=false
case "$kind" in
  testflight)
    number=""
    case "$ref" in testflight-*) number="${ref#testflight-}" ;; esac
    [ -n "$number" ] || number="${BUILD_NUMBER:-}"
    if [ -n "$number" ]; then what="TestFlight build $number"; else what="TestFlight build · $ref"; fi
    if [ "$status" = success ]; then
      title="$what uploaded${PLATFORMS:+ ($PLATFORMS)}"
    else
      title="$what $verb"
    fi
    ;;
  *)
    case "$kind" in
      build)       label="Build" ;;
      ui-tests)    label="UI tests" ;;
      screenshots) label="Screenshots" ;;
      *)           label="$kind" ;;
    esac
    title="$label $verb · $ref"
    [ "$kind" = build ] && [ "$status" = success ] && silent=true
    ;;
esac
[ "${NO_BUILD:-}" = true ] && title="$title (checks only, nothing to build)"

message="$icon $title"

commit="$(git log -1 --format='%s (%h)' 2>/dev/null || true)"
[ -n "$commit" ] && message="$message
$commit"

case "${JOB_STARTED:-}" in
  ''|*[!0-9]*) ;;
  *)
    elapsed=$(( $(date +%s) - JOB_STARTED ))
    [ "$elapsed" -lt 0 ] && elapsed=0
    h=$(( elapsed / 3600 )); m=$(( elapsed % 3600 / 60 )); s=$(( elapsed % 60 ))
    if [ "$h" -gt 0 ]; then took="$(printf '%dh %02dm %02ds' "$h" "$m" "$s")"
    elif [ "$m" -gt 0 ]; then took="$(printf '%dm %02ds' "$m" "$s")"
    else took="${s}s"; fi
    message="$message
⏱ $took"
    ;;
esac

if [ -n "${REPO:-}" ] && [ -n "${RUN_ID:-}" ]; then
  message="$message
${GITHUB_SERVER_URL:-https://github.com}/$REPO/actions/runs/$RUN_ID"
fi

# JSON string escaping: tabs become spaces, other control characters except
# newline are dropped, backslashes and quotes are escaped, and newlines are
# joined as \n. C locale so multi-byte UTF-8 (the emoji) passes through intact.
json_escape() {
  printf '%s\n' "$1" \
    | LC_ALL=C tr '\t' ' ' \
    | LC_ALL=C tr -d '\000-\010\013-\037' \
    | LC_ALL=C sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
    | LC_ALL=C awk 'NR > 1 { printf "\\n" } { printf "%s", $0 }'
}

payload="{\"message\": \"$(json_escape "$message")\", \"silent\": $silent}"

if [ "${DRY_RUN:-}" = 1 ]; then
  printf '%s\n' "$payload"
  exit 0
fi

if [ -z "$WEBHOOK_URL" ]; then
  echo "NOTIFY_WEBHOOK_URL is not set; not notifying."
  exit 0
fi

curl -sS --max-time 20 -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  --data-binary "$payload" >/dev/null \
  || echo "::warning::Notification failed (webhook unreachable?); ignored."
exit 0
