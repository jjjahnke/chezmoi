#!/usr/bin/env bash
# Integration-train queue for SAME-SURFACE work orders: each order
# branches from the train (seeing its predecessors' work, so sibling
# conflicts cannot exist) and merges back on STATUS: DONE. BLOCKED or
# failed orders don't merge. Queue end = ONE PR train->main for a
# single review.
# Usage: loop-train.sh <repo> <train-name> <order1.md> [order2.md ...]
set -euo pipefail
source "$HOME/.zprofile" 2>/dev/null || true
REPO="${1:?usage: loop-train.sh <repo> <train-name> <orders...>}"
NAME="${2:?train name required}"; shift 2
TRAIN="loop-train/$(date +%Y%m%d)-$NAME"
SUMMARY=""

cd "$REPO"
git fetch origin
git checkout -B "$TRAIN" origin/main
git push -u origin "$TRAIN"

for ORDER in "$@"; do
  ON=$(basename "$ORDER" .md)
  echo "=== train: running $ON ==="
  git checkout "$TRAIN" && git reset --hard "origin/$TRAIN" && git clean -fd
  LOOP_BASE="origin/$TRAIN" LOOP_NO_PR=1 "$HOME/bin/nightly-loop.sh" "$REPO" "$ORDER" 3 || true
  STATUS=$(head -1 LOOP_STATUS.md 2>/dev/null || echo "STATUS: UNKNOWN")
  SUMMARY="$SUMMARY
### $ON — $STATUS
$(cat LOOP_STATUS.md 2>/dev/null || echo '(no status)')
"
  if echo "$STATUS" | grep -q "STATUS: DONE"; then
    BRANCH="loop/$(date +%Y%m%d)-$ON"
    git checkout "$TRAIN"
    git merge --no-ff "$BRANCH" -m "train: merge $ON" && git push
    echo "=== train: $ON merged ==="
  else
    echo "=== train: $ON NOT merged ($STATUS) — see log ==="
  fi
done

git checkout "$TRAIN"
gh pr create --base main --head "$TRAIN" --title "loop-train: $NAME" \
  --body "Integration train of $(date +%Y-%m-%d). Per-order outcomes:
$SUMMARY" || true
echo "=== train complete: review the single PR above ==="
