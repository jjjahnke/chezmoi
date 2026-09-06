#!/usr/bin/env bash
# Unattended dev loop: execute a written work order against a repo.
# The HARNESS owns the gate: after each bounded agent turn it runs
# `make validate` itself, commits the working tree only on green, and on
# red resumes the SAME session with the compacted failure tail. Fresh
# session per increment (re-reads the order), warm session per fix.
# Branch-only. Default: push + draft PR at the end.
# Env knobs (for the train runner):
#   LOOP_BASE   - ref to branch from (default origin/main)
#   LOOP_NO_PR  - if set, skip push/PR (the caller integrates the branch)
#   LOOP_ENGINE - the claude CLI that grinds the loop (default claude-ds = DeepSeek; claude-kimi = Kimi K2.7).
#                 Set LOOP_ENGINE=claude to run on frontier Claude instead.
# Usage: nightly-loop.sh <repo-path> <work-order-file> [max-iterations]
set -euo pipefail
REPO="${1:?usage: nightly-loop.sh <repo> <work-order> [iters]}"
ORDER="${2:?usage: nightly-loop.sh <repo> <work-order> [iters]}"
ITERS="${3:-8}"
BASE="${LOOP_BASE:-origin/main}"
ENGINE="${LOOP_ENGINE:-claude-ds}"

# No git add/commit: the harness commits. The agent may self-check with
# make validate, but the authoritative gate run is the harness's.
ALLOWED="Edit,Write,Read,Glob,Grep,Bash(make validate),Bash(make test*),Bash(make lint*),Bash(git status*),Bash(git diff*),Bash(git log*)"

LOGDIR="$HOME/loop-logs"; mkdir -p "$LOGDIR"
exec > >(tee -a "$LOGDIR/$(date +%Y%m%d)-$(basename "$ORDER" .md).log") 2>&1

cd "$REPO"
git fetch origin
BRANCH="loop/$(date +%Y%m%d)-$(basename "$ORDER" .md)"
git checkout -B "$BRANCH" "$BASE"
# Status/summary files are loop plumbing, never part of the deliverable.
for f in LOOP_STATUS.md LOOP_MSG.md; do
  grep -qxF "$f" .git/info/exclude 2>/dev/null || echo "$f" >> .git/info/exclude
done
rm -f LOOP_STATUS.md LOOP_MSG.md

GATE_OUT=$(mktemp); trap 'rm -f "$GATE_OUT"' EXIT
gate() { make validate >"$GATE_OUT" 2>&1; }

# Green gate from iteration 0: the loop inherits a working baseline or
# does not run at all.
if gate; then
  echo "=== gate: baseline PASS ==="
else
  echo "=== gate: baseline FAIL - fix the baseline before looping ==="
  tail -n 40 "$GATE_OUT"; exit 1
fi

BUILD_PROMPT="Read $ORDER. Continue the work it describes from the current
state of this branch. Make the smallest next increment. Do NOT commit:
the harness runs the authoritative 'make validate' after your turn and
commits your changes only on green (you may run make validate yourself
to self-check). Write a one-line summary of the increment to
LOOP_MSG.md. The harness commits ALL working-tree changes on green, so
delete any scratch or debug files before ending your turn. If the work
order is complete, or you are blocked, write STATUS: DONE or
STATUS: BLOCKED plus the reason to LOOP_STATUS.md and stop. Never
commit LOOP_MSG.md or LOOP_STATUS.md."

SID=""; RESUME_CTX=""
for i in $(seq 1 "$ITERS"); do
  echo "=== loop iteration $i/$ITERS ==="
  if [ -n "$RESUME_CTX" ]; then
    "$ENGINE" -p --resume "$SID" "$RESUME_CTX" \
      --permission-mode acceptEdits --allowedTools "$ALLOWED" || true
  else
    SID=$(uuidgen | tr 'A-Z' 'a-z')
    "$ENGINE" -p --session-id "$SID" "$BUILD_PROMPT" \
      --permission-mode acceptEdits --allowedTools "$ALLOWED" || true
  fi

  STATUS=$(head -1 LOOP_STATUS.md 2>/dev/null || true)
  if gate; then
    echo "=== gate: PASS (iteration $i) ==="
    if [ -n "$(git status --porcelain)" ]; then
      MSG=$(head -1 LOOP_MSG.md 2>/dev/null || true)
      git add -A
      git commit -m "${MSG:-loop: increment (iteration $i)}"
    fi
    RESUME_CTX=""
    case "$STATUS" in *DONE*|*BLOCKED*) break ;; esac
  else
    echo "=== gate: FAIL (iteration $i) ==="
    tail -n 20 "$GATE_OUT"
    case "$STATUS" in *BLOCKED*) break ;; esac
    PREFIX=""
    case "$STATUS" in
      *DONE*) PREFIX="You wrote STATUS: DONE, but the authoritative gate
still fails, so the order is not complete. "; rm -f LOOP_STATUS.md ;;
    esac
    RESUME_CTX="${PREFIX}The harness ran 'make validate' after your turn
and it FAILED. Fix the failure with the smallest change, update
LOOP_MSG.md, and stop; the harness re-runs the gate after your turn.
Failure output (tail):
$(tail -n 60 "$GATE_OUT")"
  fi
done

if [ -n "$(git status --porcelain)" ]; then
  echo "=== WARNING: uncommitted changes remain (gate red at loop end); left in working tree ==="
fi

if [ -z "${LOOP_NO_PR:-}" ]; then
  if [ "$(git rev-list --count "$BASE"..HEAD)" -gt 0 ]; then
    git push -u origin "$BRANCH"
    gh pr create --fill --draft || true
  else
    echo "=== no commits produced; skipping push/PR ==="
  fi
fi
