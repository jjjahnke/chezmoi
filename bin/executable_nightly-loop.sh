#!/usr/bin/env bash
# Unattended dev loop: execute a written work order against a repo via
# claude-ds, gated by `make validate`, branch-only. Default: push + draft
# PR at the end. Env knobs (for the train runner):
#   LOOP_BASE   - ref to branch from (default origin/main)
#   LOOP_NO_PR  - if set, skip push/PR (the caller integrates the branch)
# Usage: nightly-loop.sh <repo-path> <work-order-file> [max-iterations]
set -euo pipefail
REPO="${1:?usage: nightly-loop.sh <repo> <work-order> [iters]}"
ORDER="${2:?usage: nightly-loop.sh <repo> <work-order> [iters]}"
ITERS="${3:-8}"
BASE="${LOOP_BASE:-origin/main}"

LOGDIR="$HOME/loop-logs"; mkdir -p "$LOGDIR"
exec > >(tee -a "$LOGDIR/$(date +%Y%m%d)-$(basename "$ORDER" .md).log") 2>&1

cd "$REPO"
git fetch origin
BRANCH="loop/$(date +%Y%m%d)-$(basename "$ORDER" .md)"
git checkout -B "$BRANCH" "$BASE"
# Status file is loop plumbing, never part of the deliverable.
grep -qxF "LOOP_STATUS.md" .git/info/exclude 2>/dev/null || echo "LOOP_STATUS.md" >> .git/info/exclude
rm -f LOOP_STATUS.md

for i in $(seq 1 "$ITERS"); do
  echo "=== loop iteration $i/$ITERS ==="
  claude-ds -p "Read $ORDER. Continue the work it describes from the
current state of this branch. Make the smallest next increment, run
'make validate', and commit ONLY if validation passes. Never commit
LOOP_STATUS.md. If the work order is complete, or you are blocked,
write STATUS: DONE or STATUS: BLOCKED plus the reason to
LOOP_STATUS.md and stop." \
    --permission-mode acceptEdits \
    --allowedTools "Edit,Write,Read,Glob,Grep,Bash(make validate),Bash(make test*),Bash(make lint*),Bash(git add*),Bash(git commit*),Bash(git status*),Bash(git diff*),Bash(git log*)" || true
  grep -q "STATUS:" LOOP_STATUS.md 2>/dev/null && break
done

if [ -z "${LOOP_NO_PR:-}" ]; then
  git push -u origin "$BRANCH"
  gh pr create --fill --draft || true
fi
