#!/usr/bin/env bash
#
# Fail if an LLD number is in both todo/ and done/.
#
# A shipped LLD is `git mv`'d from todo/ to done/. When it is copied instead,
# or the LLD lands on one branch while the code goes through another, both
# files survive and the stale todo/ copy keeps describing work that already
# shipped (one project once had thirteen of them sitting in todo/ for two months). This
# is the cheapest possible check for it, and it runs on the docs-only fast path
# too, because that is exactly the kind of change that causes it.
#
# LLD_DIR overrides the folder.

set -euo pipefail

LLD="${LLD_DIR:-design/Documentation/docs/03 - Low Level Design}"
if [ ! -d "$LLD" ]; then
  echo "No LLD folder at '$LLD'; nothing to check."
  exit 0
fi

dupes=0
for f in "$LLD"/todo/*.md; do
  [ -e "$f" ] || continue
  base="$(basename "$f")"
  num="${base%%-*}"
  case "$num" in ''|*[!0-9]*) continue ;; esac
  for m in "$LLD"/done/"$num"-*.md; do
    [ -e "$m" ] || continue
    [ "$dupes" -eq 0 ] && echo "LLD numbers present in BOTH todo/ and done/:" >&2
    dupes=$((dupes + 1))
    echo "  todo/$base" >&2
    echo "    superseded by done/$(basename "$m")" >&2
  done
done

if [ "$dupes" -gt 0 ]; then
  {
    echo ""
    echo "A shipped LLD is git mv'd from todo/ to done/, never copied. If the"
    echo "done/ copy shipped a narrower scope than the todo/ original, file the"
    echo "residual as a NEW numbered LLD and delete the stale todo/ file."
  } >&2
  exit 1
fi

# `|| true`: with no todo/*.md, ls exits non-zero, which pipefail would turn
# into a failed step.
open=$( (ls -1 "$LLD"/todo/*.md 2>/dev/null || true) | wc -l | tr -d ' ')
echo "LLD todo/done consistency OK: $open open."
