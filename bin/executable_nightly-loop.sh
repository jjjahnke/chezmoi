#!/usr/bin/env bash
# Unattended overnight dev loop: executes a written work order against a
# repo via claude-ds, gated by `make validate`, branch-only, ends in a
# draft PR for morning review. Never merges, never deploys (the tool
# allowlist below cannot run `make deploy-*`).
# Usage: nightly-loop.sh <repo-path> <work-order-file> [max-iterations]
set -euo pipefail
REPO="${1:?usage: nightly-loop.sh <repo> <work-order> [iters]}"
ORDER="${2:?usage: nightly-loop.sh <repo> <work-order> [iters]}"
ITERS="${3:-8}"
cd "$REPO"
git fetch origin
BRANCH="loop/$(date +%Y%m%d)-$(basename "$ORDER" .md)"
git checkout -b "$BRANCH" origin/main
rm -f LOOP_STATUS.md
for i in $(seq 1 "$ITERS"); do
  echo "=== loop iteration $i/$ITERS ==="
  claude-ds -p "Read $ORDER. Continue the work it describes from the
current state of this branch. Make the smallest next increment, run
'make validate', and commit ONLY if validation passes. If the work order
is complete, or you are blocked, write STATUS: DONE or STATUS: BLOCKED
plus the reason to LOOP_STATUS.md and stop." \
    --permission-mode acceptEdits \
    --allowedTools "Edit,Write,Read,Glob,Grep,Bash(make validate),Bash(make test*),Bash(make lint*),Bash(git add*),Bash(git commit*),Bash(git status*),Bash(git diff*),Bash(git log*)" || true
  grep -q "STATUS:" LOOP_STATUS.md 2>/dev/null && break
done
git push -u origin "$BRANCH"
gh pr create --fill --draft || true
