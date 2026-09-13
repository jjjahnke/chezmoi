#!/usr/bin/env bash
# Unattended dev loop: execute a written work order against a repo.
# The HARNESS owns the gate: after each bounded agent turn it runs
# `make validate` itself, commits the working tree only on green, and on
# red resumes the SAME session with the compacted failure tail. Fresh
# session per increment (re-reads the order), warm session per fix.
# Branch-only. Default: push + draft PR at the end.
#
# Terminal states (exit code): every run ends in exactly one, printed as
# "=== LOOP_RESULT: <state>" and, when the harness decided it, written to
# LOOP_STATUS.md so the train runner and the PR body can read it.
#   done       0   agent wrote STATUS: DONE and the gate is green
#   blocked    2   agent wrote STATUS: BLOCKED (a well-argued one is a success)
#   decide     3   agent wrote STATUS: DECIDE: it can continue but a human must choose
#   exhausted  4   iterations or the token ceiling ran out before DONE
#   error      5   the harness or engine failed (gate timeout, engine crash)
#   cancelled  130 SIGINT/SIGTERM
#   (1 = usage or preflight failure: red baseline, missing order)
# Env knobs (for the train runner):
#   LOOP_BASE         - ref to branch from (default origin/main)
#   LOOP_NO_PR        - if set, skip push/PR (the caller integrates the branch)
#   LOOP_ENGINE       - the claude CLI that grinds the loop (default claude-ds = DeepSeek; claude-kimi = Kimi K2.7).
#                       Set LOOP_ENGINE=claude to run on frontier Claude instead.
#   LOOP_MAX_TOKENS   - per-run token ceiling across all turns (default 5000000), counting
#                       input, cache writes and output. Cache READS are reported, not counted.
#   LOOP_GATE_TIMEOUT - seconds before a gate is killed (default 3600)
#
# The record of a run: ~/loop-logs/<date>-<order>.log holds each turn's last
# message, its tokens and session id, and every gate verdict. The work itself
# (every read, edit, test run and dead end) is the session transcript, copied
# after each turn to ~/loop-logs/<date>-<order>/<session>.jsonl.
# Usage: nightly-loop.sh <repo-path> <work-order-file> [max-iterations]
set -euo pipefail
REPO="${1:?usage: nightly-loop.sh <repo> <work-order> [iters]}"
ORDER="${2:?usage: nightly-loop.sh <repo> <work-order> [iters]}"
ITERS="${3:-8}"
BASE="${LOOP_BASE:-origin/main}"
ENGINE="${LOOP_ENGINE:-claude-ds}"
MAX_TOKENS="${LOOP_MAX_TOKENS:-5000000}"

# No git add/commit: the harness commits. The agent may self-check with
# make validate, but the authoritative gate run is the harness's.
ALLOWED="Edit,Write,Read,Glob,Grep,Bash(make validate),Bash(make test*),Bash(make lint*),Bash(git status*),Bash(git diff*),Bash(git log*)"

LOGDIR="$HOME/loop-logs"; mkdir -p "$LOGDIR"
# Named once, so a run that crosses midnight keeps one log and one transcript dir.
RUN_NAME="$(date +%Y%m%d)-$(basename "$ORDER" .md)"
RUN_DIR="$LOGDIR/$RUN_NAME"
exec > >(tee -a "$LOGDIR/$RUN_NAME.log") 2>&1

cd "$REPO"
git fetch origin
BRANCH="loop/$(date +%Y%m%d)-$(basename "$ORDER" .md)"
# Pin the starting point as a SHA before moving any refs. Resuming a run with
# LOOP_BASE set to the loop branch itself makes BASE and BRANCH the same ref, so
# checkout -B drags BASE along with HEAD and the end-of-run "did we produce
# commits" test compares the branch against itself and always says no. That ate
# the push and PR of a completed run on 2026-09-12.
BASE_SHA=$(git rev-parse --verify "$BASE")
git checkout -B "$BRANCH" "$BASE_SHA"

# The order has to exist in the tree the agent is about to work in. Push an order
# to main, point LOOP_BASE at a branch created before it, and the agent has
# nothing to read: on 2026-09-12 one inferred the job from repo state, saw a green
# gate, wrote STATUS: DONE and burned a run. Refuse instead of improvising.
if [ ! -f "$ORDER" ]; then
  echo "=== work order '$ORDER' does not exist on base $BASE ($BASE_SHA)."
  echo "=== Put the order on that base (cherry-pick it, or branch from one that has it) and rerun."
  exit 1
fi

# Status/summary files are loop plumbing, never part of the deliverable.
for f in LOOP_STATUS.md LOOP_MSG.md; do
  grep -qxF "$f" .git/info/exclude 2>/dev/null || echo "$f" >> .git/info/exclude
done
rm -f LOOP_STATUS.md LOOP_MSG.md

GATE_OUT=$(mktemp); TURN_OUT=$(mktemp); trap 'rm -f "$GATE_OUT" "$TURN_OUT" "$TURN_OUT.tokens"' EXIT

# ---- the record ------------------------------------------------------------
# The log is not the work. A turn's reads, edits, test runs and dead ends live only
# in its session transcript, which Claude Code deletes after 30 days
# (cleanupPeriodDays) and which the weekly transcript review deliberately skips for
# loops. On 2026-09-13 the docs2data-loop project dir held 58 transcripts, the oldest
# from Sep 8, for a project that had been looping since June: everything earlier was
# gone. So each turn's transcript is copied beside the log, under the run's name,
# where nothing cleans it up. A copy that fails is a line in the log, never a failed
# run: bookkeeping must not break the loop.
TRANSCRIPTS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
keep_transcript() {
  local sid="$1" src
  [ -n "$sid" ] || return 0
  src=$(find "$TRANSCRIPTS" -mindepth 2 -maxdepth 2 -name "$sid.jsonl" -print 2>/dev/null | head -1 || true)
  if [ -z "$src" ]; then
    echo "=== transcript: none found for session $sid under $TRANSCRIPTS ==="
    return 0
  fi
  if mkdir -p "$RUN_DIR" && cp "$src" "$RUN_DIR/$sid.jsonl"; then
    # Subagent transcripts, when the engine spawned any, sit in a dir named for the session.
    if [ -d "${src%.jsonl}" ]; then cp -R "${src%.jsonl}" "$RUN_DIR/" 2>/dev/null || true; fi
    echo "=== transcript: $RUN_DIR/$sid.jsonl ==="
  else
    echo "=== transcript: could not copy $src ==="
  fi
  return 0
}

# ---- terminal states -------------------------------------------------------
# One exit path. The agent's own STATUS line decides done/blocked/decide; the
# harness decides exhausted/error/cancelled. TOKENS is the running total across
# every turn of this run.
TOKENS=0; CACHE_READS=0; SID=""
# 10216906 is unreadable at a glance; 10,216,906 is not. Pure bash, so the commas
# do not depend on a locale that cron and launchd may not set.
commas() {
  local s="$1" out=""
  while [ ${#s} -gt 3 ]; do out=",${s: -3}$out"; s="${s:0:${#s}-3}"; done
  echo "$s$out"
}
finish() {
  local state="$1" why="${2:-}" rc
  case "$state" in
    done) rc=0 ;; blocked) rc=2 ;; decide) rc=3 ;; exhausted) rc=4 ;;
    error) rc=5 ;; cancelled) rc=130 ;; *) rc=5 ;;
  esac
  # The harness writes STATUS only when the agent did not: exhausted, error and
  # cancelled are the harness's verdicts, and the train runner reads this file.
  if [ ! -s LOOP_STATUS.md ]; then
    printf 'STATUS: %s\n%s\n' "$(echo "$state" | tr 'a-z' 'A-Z')" "$why" > LOOP_STATUS.md
  fi
  # Again here, so a run cancelled or failed mid-turn keeps what that turn did.
  keep_transcript "$SID"
  echo "=== LOOP_RESULT: $state (tokens $(commas "$TOKENS")/$(commas "$MAX_TOKENS"), cache reads $(commas "$CACHE_READS") not counted, session ${SID:-none}, transcripts $RUN_DIR) $why ==="
  if [ -n "$(git status --porcelain)" ]; then
    echo "=== WARNING: uncommitted changes remain (gate red at loop end); left in working tree ==="
  fi
  if [ -z "${LOOP_NO_PR:-}" ]; then
    if [ "$(git rev-list --count "$BASE_SHA"..HEAD)" -gt 0 ]; then
      git push -u origin "$BRANCH"
      gh pr create --draft --title "loop: $(basename "$ORDER" .md) [$state]" \
        --body "$(printf 'Work order: %s\nResult: **%s** %s\nTokens: %s\n\n%s\n' \
          "$ORDER" "$state" "$why" "$(commas "$TOKENS")" "$(cat LOOP_STATUS.md 2>/dev/null)")" || true
    else
      echo "=== no commits produced; skipping push/PR ==="
    fi
  fi
  exit "$rc"
}
trap 'finish cancelled "signal received"' INT TERM

# ---- the gate --------------------------------------------------------------
# The gate is bounded and timed. Bounded because it runs on the remote builder
# over an ssh tunnel: on 2026-09-12 the docs2data container finished, the tunnel
# died, and the docker client waited 4.5 hours for an answer that was never
# coming, with nothing in the log to say so. Timed because nothing recorded how
# long a gate takes, so the timeout had to be measured after the fact.
#
# Sizing: a warm docs2data gate (image build + ruff + mypy + 205 tests) is 33s.
# The slowest known real gate was about 25 minutes, an OCR test rendering a huge
# synthetic page. Commit-to-commit intervals across past loop branches, which
# include the agent's turn as well as the gate, run a median of 31 minutes and a
# max of 70. An hour is therefore far above any gate that is actually working,
# and fires only when the gate has stopped being a gate. Override with
# LOOP_GATE_TIMEOUT. A killed gate is an `error`, not a red gate: the agent
# cannot fix a dead tunnel, so it is never asked to.
GATE_TIMEOUT="${LOOP_GATE_TIMEOUT:-3600}"
TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"
GATE_RC=0
gate() {
  local start secs
  start=$(date +%s)
  if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" --kill-after=60 "$GATE_TIMEOUT" make validate >"$GATE_OUT" 2>&1; GATE_RC=$?
  else
    make validate >"$GATE_OUT" 2>&1; GATE_RC=$?
  fi
  secs=$(( $(date +%s) - start ))
  echo "=== gate: ${secs}s, exit ${GATE_RC} ($(date '+%Y-%m-%d %H:%M:%S')) ==="
  return "$GATE_RC"
}
gate_killed() { [ "$GATE_RC" -eq 124 ] || [ "$GATE_RC" -eq 137 ]; }

# Green gate from iteration 0: the loop inherits a working baseline or
# does not run at all.
if gate; then
  echo "=== gate: baseline PASS ==="
else
  echo "=== gate: baseline FAIL - fix the baseline before looping ==="
  tail -n 40 "$GATE_OUT"
  gate_killed && echo "=== (the baseline gate was killed at ${GATE_TIMEOUT}s: check 'docker --context builder ps' before blaming the code) ==="
  exit 1
fi

# ---- the agent turn --------------------------------------------------------
# Each turn runs with JSON output so the harness can read usage. The result text
# is echoed to the log as before; the usage feeds the token ceiling. The
# reported cost is NOT trusted: Claude Code prices non-Anthropic models at
# Anthropic rates (a 43k-token DeepSeek turn showed $0.22 on 2026-09-13), so the
# ceiling is in tokens, which the endpoint reports correctly.
#
# The ceiling counts input, cache writes and output, and NOT cache reads. Every
# step of a turn re-reads the cached context, so cache reads grow with the number
# of steps rather than with the work, and the endpoint bills them at a fraction of
# the price. Counted, they ended the first real run of this ceiling after one
# green iteration (D.5, 2026-09-13): 10,216,906 tokens against 5,000,000, of which
# 9,999,232 were cache reads and 217,674 the rest. Cache reads are still printed
# per turn and totalled at the end, so a run that thrashes its context is visible.
ENGINE_FAILS=0
turn() {
  # $@ = engine args after -p. Returns 0 on a usable turn, 1 on engine failure.
  "$ENGINE" -p "$@" --output-format json \
    --permission-mode acceptEdits --allowedTools "$ALLOWED" >"$TURN_OUT" 2>/dev/null || true
  python3 - "$TURN_OUT" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print(f"=== engine: no JSON result ({e}) ===", flush=True); sys.exit(1)
u = d.get("usage") or {}
used = sum(int(u.get(k) or 0) for k in ("input_tokens", "cache_creation_input_tokens", "output_tokens"))
cache_reads = int(u.get("cache_read_input_tokens") or 0)
print(d.get("result") or "")
n = lambda k: f"{int(u.get(k) or 0):,}"
print(f"=== turn: {used:,} tokens counted (in {n('input_tokens')}, cache writes {n('cache_creation_input_tokens')}, out {n('output_tokens')}; cache reads {cache_reads:,} not counted), {d.get('num_turns',0)} model turns, error={d.get('is_error')}, session {d.get('session_id') or 'unknown'} ===", flush=True)
open(sys.argv[1] + ".tokens", "w").write(f"{used} {cache_reads}")
sys.exit(1 if d.get("is_error") else 0)
PY
}
add_tokens() {
  local used=0 reads=0
  read -r used reads < "$TURN_OUT.tokens" 2>/dev/null || true
  rm -f "$TURN_OUT.tokens"
  TOKENS=$(( TOKENS + ${used:-0} )); CACHE_READS=$(( CACHE_READS + ${reads:-0} ))
}

BUILD_PROMPT="Read $ORDER. Continue the work it describes from the current
state of this branch. Make the smallest next increment. Do NOT commit:
the harness runs the authoritative 'make validate' after your turn and
commits your changes only on green (you may run make validate yourself
to self-check). Write a one-line summary of the increment to
LOOP_MSG.md. The harness commits ALL working-tree changes on green, so
delete any scratch or debug files before ending your turn. When the run
should stop, write exactly one of these as the first line of
LOOP_STATUS.md, followed by the reason:
  STATUS: DONE     the work order is complete
  STATUS: BLOCKED  you cannot proceed; say what is missing
  STATUS: DECIDE   you could proceed more than one way and a human must
                   choose; state the options and your recommendation
Otherwise leave LOOP_STATUS.md absent. Never commit LOOP_MSG.md or
LOOP_STATUS.md."

RESUME_CTX=""
for i in $(seq 1 "$ITERS"); do
  echo "=== loop iteration $i/$ITERS (tokens so far $(commas "$TOKENS")/$(commas "$MAX_TOKENS")) ==="
  if [ -n "$RESUME_CTX" ]; then
    if turn --resume "$SID" "$RESUME_CTX"; then ENGINE_FAILS=0; else ENGINE_FAILS=$((ENGINE_FAILS + 1)); fi
  else
    SID=$(uuidgen | tr 'A-Z' 'a-z')
    if turn --session-id "$SID" "$BUILD_PROMPT"; then ENGINE_FAILS=0; else ENGINE_FAILS=$((ENGINE_FAILS + 1)); fi
  fi
  add_tokens
  keep_transcript "$SID"
  # One engine failure may be transient (rate limit, tunnel); two in a row is
  # the run's problem, not the code's.
  if [ "$ENGINE_FAILS" -ge 2 ]; then
    finish error "engine failed twice in a row (iteration $i)"
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
    case "$STATUS" in
      *DONE*)    finish done ;;
      *BLOCKED*) finish blocked ;;
      *DECIDE*)  finish decide ;;
    esac
  else
    echo "=== gate: FAIL (iteration $i) ==="
    tail -n 20 "$GATE_OUT"
    if gate_killed; then finish error "gate killed at ${GATE_TIMEOUT}s (iteration $i); check 'docker --context builder ps'"; fi
    case "$STATUS" in
      *BLOCKED*) finish blocked ;;
      *DECIDE*)  finish decide ;;
    esac
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

  # The ceiling is checked after the gate so a green increment is committed
  # before the run is declared exhausted; nothing already earned is lost.
  if [ "$TOKENS" -ge "$MAX_TOKENS" ]; then
    finish exhausted "token ceiling reached after iteration $i"
  fi
done

finish exhausted "iterations spent ($ITERS) without STATUS: DONE"
