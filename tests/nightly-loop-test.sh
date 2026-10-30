#!/usr/bin/env bash
# Deterministic stub-engine regression test for nightly-loop.sh.
# Exercises every terminal state and the token ceiling without touching a
# model or a real repo: a throwaway git repo with a bare origin, a Makefile
# whose validate target passes (or hangs, for the gate-kill case), and a fake
# engine that emits Claude Code's JSON result shape. Run after ANY harness edit:
#   make validate   (runs this against bin/executable_nightly-loop.sh)
#   tests/nightly-loop-test.sh [path-to-nightly-loop.sh]   (default ~/bin/nightly-loop.sh)
# Each case prints PASS/FAIL against the expected exit code. Logs land in a
# temp dir printed at the end. Writes one throwaway line to ~/loop-logs and
# removes it.
#
# The cases for decisions/loop-checks.md (sopori-cluster) are the spec for order
# loop-checks-1. Each group stays PENDING until the harness carries the log line
# its item adds, so the gate is green before the work; the order is done only at
# "ALL PASS (0 pending)". A loop never edits this file.
set -euo pipefail
H="${1:-$HOME/bin/nightly-loop.sh}"
T="$(mktemp -d)"; mkdir -p "$T/logs"
# The harness records every run with loop_run.py into the real ledger and the
# Pushgateway, and skips recording when LOOP_RUN names no file. Without this, every
# test run lands its fake runs beside the real ones (53 events on 2026-10-29).
export LOOP_RUN="$T/no-loop-run"
FAIL=0; PENDING=0

setup() {
  rm -rf "$T/origin.git" "$T/repo"
  git init -q --bare "$T/origin.git"
  git init -q "$T/repo"; cd "$T/repo"
  git config user.email t@t; git config user.name t
  # The gate prints counts.txt when there is one, and goes red while a file named red exists.
  printf 'validate:\n\t@cat counts.txt 2>/dev/null || echo validate ok\n\t@test ! -f red\n' > Makefile
  # Numbered lines before and after the criteria are not criteria.
  printf '# Order\nAppend a line to out.txt\n\n1. Not a criterion.\n\n## Done criteria\n\n1. out.txt gains a line per turn.\n2. make validate is green.\n\n## Notes\n\n1. Not a criterion either.\n' > order.md
  # A pytest-style summary for the gate to print, when the case gives one.
  [ -z "${1:-}" ] || printf '%b' "$1" > counts.txt
  git add -A; git commit -qm init; git remote add origin "$T/origin.git"
  git push -q -u origin "$(git symbolic-ref --short HEAD)"
  cd - >/dev/null
}

cat > "$T/stub-engine" <<'EOF'
#!/usr/bin/env bash
# Fake claude CLI. STUB_MODE picks the behaviour; STUB_COUNT counts calls.
n=$(( $(cat "$STUB_COUNT" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$STUB_COUNT"
# DONE carries one row per numbered done criterion: | # | criterion | verdict | evidence |
# The separator is spaced and one verdict is capitalised: both are legal markdown.
table() { printf 'STATUS: DONE\nfinished\n\n| # | criterion | verdict | evidence |\n| --- | --- | --- | --- |\n' > LOOP_STATUS.md; printf '%s\n' "$@" >> LOOP_STATUS.md; }
R1="| 1 | out.txt gains a line per turn | Pass | out.txt |"
R2="| 2 | make validate is green | pass | make validate |"
step() { echo "line $n" >> out.txt; echo "add line $n" > LOOP_MSG.md; }
case "${STUB_MODE:-done}" in
  done)    step; [ "$n" -ge 2 ] && table "$R1" "$R2" ;;
  countsup)   step; echo "$((3 + n)) passed in 0.10s" > counts.txt; [ "$n" -ge 2 ] && table "$R1" "$R2" ;;
  countsdrop) step; echo "2 passed in 0.10s" > counts.txt ;;
  countsback) step; if [ "$n" -eq 1 ]; then echo "2 passed in 0.10s" > counts.txt; else echo "4 passed in 0.10s" > counts.txt; table "$R1" "$R2"; fi ;;
  dropflip)   step; case "$n" in 1|3) echo "2 passed in 0.10s" > counts.txt ;; 2) echo "4 passed in 0.10s" > counts.txt ;; *) echo "5 passed in 0.10s" > counts.txt; table "$R1" "$R2" ;; esac ;;
  donedrop)   step; if [ "$n" -eq 1 ]; then echo "2 passed in 0.10s" > counts.txt; table "$R1" "$R2"; else echo "4 passed in 0.10s" > counts.txt; fi ;;
  redhigh)    step; if [ "$n" -eq 1 ]; then echo "9 passed in 0.10s" > counts.txt; touch red; else rm -f red; echo "5 passed in 0.10s" > counts.txt; table "$R1" "$R2"; fi ;;
  skipsup)    step; echo "3 passed, 1 skipped in 0.10s" > counts.txt ;;
  gatefile)   step; echo "# touched" >> Makefile; mkdir -p sub; echo "# fixture" > sub/conftest.py; table "$R1" "$R2" ;;
  notable)    step; case "$n" in 1) printf 'STATUS: DONE\nfinished, no table\n' > LOOP_STATUS.md ;; 2) : ;; *) table "$R1" "$R2" ;; esac ;;
  notablenever) step; printf 'STATUS: DONE\nfinished, no table\n' > LOOP_STATUS.md ;;
  fewrows)    step; if [ "$n" -eq 1 ]; then table "$R1"; else table "$R1" "$R2"; fi ;;
  navverdict) step; if [ "$n" -eq 1 ]; then table "$R1" "| 2 | make validate is green | n/a | not applicable |"; else table "$R1" "$R2"; fi ;;
  failrow)    step; if [ "$n" -eq 1 ]; then table "$R1" "| 2 | make validate is green | fail | red locally |"; else table "$R1" "$R2"; fi ;;
  unresolved) step; table "$R1" "| 2 | make validate is green | unresolved | could not run it here |" ;;
  blocked) printf 'STATUS: BLOCKED\nno fixture\n' > LOOP_STATUS.md ;;
  decide)  echo "line $n" >> out.txt; echo "msg" > LOOP_MSG.md; printf 'STATUS: DECIDE\nA or B?\n' > LOOP_STATUS.md ;;
  never)   echo "line $n" >> out.txt; echo "add line $n" > LOOP_MSG.md ;;
  crash)   echo "boom" >&2; exit 1 ;;
esac
# Like Claude Code, keep a transcript per session under $CLAUDE_CONFIG_DIR/projects.
sid=""; prev=""; for a in "$@"; do case "$prev" in --session-id|--resume) sid="$a" ;; esac; prev="$a"; done
if [ -n "$sid" ] && [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
  mkdir -p "$CLAUDE_CONFIG_DIR/projects/stub-repo"
  echo "{\"type\":\"assistant\",\"call\":$n}" >> "$CLAUDE_CONFIG_DIR/projects/stub-repo/$sid.jsonl"
fi
printf '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"result":"stub turn %s","session_id":"%s","usage":{"input_tokens":1000,"cache_read_input_tokens":%s,"cache_creation_input_tokens":0,"output_tokens":100}}\n' "$n" "$sid" "${STUB_CACHE_READ:-500}"
EOF
chmod +x "$T/stub-engine"

run() { # name mode iters extra-env expected-exit expected-commits [base counts.txt]
  local name=$1 mode=$2 iters=$3 extra=$4 want=$5 wantc=$6 rc base commits
  setup "${7:-}"; rm -f "$T/count"
  base=$(git -C "$T/repo" symbolic-ref --short HEAD)
  set +e
  rm -rf "$HOME/loop-logs/$(date +%Y%m%d)-order" "$T/claude"
  env STUB_MODE="$mode" STUB_COUNT="$T/count" CLAUDE_CONFIG_DIR="$T/claude" LOOP_ENGINE="$T/stub-engine" LOOP_NO_PR=1 LOOP_BASE="origin/$base" $extra \
    bash "$H" "$T/repo" order.md "$iters" > "$T/logs/$name.log" 2>&1; rc=$?
  set -e
  commits=$(git -C "$T/repo" rev-list --count "origin/$base..HEAD")
  if [ "$rc" = "$want" ] && [ "$commits" = "$wantc" ]; then v=PASS; else v=FAIL; FAIL=1; fi
  printf "%-10s exit %-3s want %-3s commits %s want %s  %s  %s\n" "$name" "$rc" "$want" "$commits" "$wantc" "$v" "$(head -1 "$T/repo/LOOP_STATUS.md" 2>/dev/null)"
}

run done    done    8 "" 0 2
# The record: every turn names its session, and each session's transcript is copied beside the log.
RUNDIR="$HOME/loop-logs/$(date +%Y%m%d)-order"
turns=$(grep -c '^=== turn: .*session [0-9a-f-]\{36\} ===$' "$T/logs/done.log" || true)
kept=$( { ls "$RUNDIR"/*.jsonl 2>/dev/null || true; } | wc -l | tr -d ' ')
if [ "$turns" = 2 ] && [ "$kept" = 2 ] && grep -q "transcripts $RUNDIR" "$T/logs/done.log"; then v=PASS; else v=FAIL; FAIL=1; fi
printf "%-10s turns naming a session %s want 2, transcripts kept %s want 2  %s\n" record "$turns" "$kept" "$v"
run blocked blocked 8 "" 2 0
run decide  decide  8 "" 3 1
run iters   never   3 "" 4 3
run tokens  never   8 "LOOP_MAX_TOKENS=2000" 4 2
# Cache reads are reported, never counted: a context-heavy turn (10M cache reads, like
# D.5's first) must not end a run whose counted tokens (1,100 a turn) are far under
# the ceiling. Counted, the old harness stops after 1 iteration; this runs all 3.
run cache   never   3 "LOOP_MAX_TOKENS=5000 STUB_CACHE_READ=10000000" 4 3
if grep -q "cache reads 30,000,000 not counted" "$T/logs/cache.log" && grep -q "^=== turn: 1,100 tokens counted (in 1,000, cache writes 0, out 100; cache reads 10,000,000 not counted)" "$T/logs/cache.log"; then v=PASS; else v=FAIL; FAIL=1; fi
printf "%-10s cache reads totalled, numbers shown with commas  %s\n" cachesum "$v"
run crash   crash   8 "" 5 0
# No transcript to copy is a log line, not a failure.
if grep -q "=== transcript: none found for session" "$T/logs/crash.log"; then v=PASS; else v=FAIL; FAIL=1; fi
printf "%-10s missing transcript is logged and survived  %s\n" notrans "$v"

# Gate killed mid-run: validate hangs once the first increment exists.
setup; printf 'validate:\n\t@test ! -f out.txt || sleep 30\n\t@echo ok\n' > "$T/repo/Makefile"
git -C "$T/repo" commit -qam hang; git -C "$T/repo" push -q
base=$(git -C "$T/repo" symbolic-ref --short HEAD); rm -f "$T/count"; set +e
env STUB_MODE=never STUB_COUNT="$T/count" LOOP_ENGINE="$T/stub-engine" LOOP_NO_PR=1 LOOP_BASE="origin/$base" LOOP_GATE_TIMEOUT=2 \
  bash "$H" "$T/repo" order.md 8 > "$T/logs/gatekill.log" 2>&1; rc=$?; set -e
if [ "$rc" = 5 ]; then v=PASS; else v=FAIL; FAIL=1; fi
printf "%-10s exit %-3s want 5   %s  %s\n" gatekill "$rc" "$v" "$(head -1 "$T/repo/LOOP_STATUS.md" 2>/dev/null)"

# ---- decisions/loop-checks.md (order loop-checks-1) --------------------------
pending() { printf "%-10s PENDING: the harness never prints '%s'\n" "$1" "$2"; PENDING=$((PENDING + 1)); }
# The first two turns ran in one session: the harness resumed rather than starting fresh.
samesession() { local k; k=$(grep -o 'session [0-9a-f-]\{36\} ===$' "$T/logs/$1.log" | head -2 | sort -u | wc -l | tr -d ' '); if [ "$k" = 1 ]; then v=PASS; else v=FAIL; FAIL=1; fi; printf "%-10s second turn resumed the first's session  %s\n" "$1" "$v"; }
has() { if grep -q "$2" "$T/logs/$1.log"; then v=PASS; else v=FAIL; FAIL=1; fi; printf "%-10s log has '%s'  %s\n" "$1" "$2" "$v"; }
lacks() { if grep -q "$2" "$T/logs/$1.log"; then v=FAIL; FAIL=1; else v=PASS; fi; printf "%-10s log lacks '%s'  %s\n" "$1" "$2" "$v"; }

# Item 1: the gate's counts ratchet. A green gate that measured less than the last
# accepted one is not committed; twice running ends the run as decide.
if grep -q "=== gate counts" "$H"; then
  run noneread done      8 "" 0 2
  has noneread "^=== gate counts: none read ===$"
  run countsup countsup  8 "" 0 2 '3 passed in 0.10s\n'
  has countsup "^=== gate counts: passed 3, not run 0 (baseline) ===$"
  has countsup "^=== gate counts: passed 5, not run 0 (accepted 4/0) ===$"
  # A slow run prints its minutes, a coloured one escape codes, and some gates run pytest twice.
  run sum      done      8 "" 0 2 '3 passed in 75.12s (0:01:15)\n==== 2 passed, 1 deselected, 1 xfailed, 2 warnings in 0.20s ====\n\033[32m1 passed in 0.10s\033[0m\n'
  has sum "^=== gate counts: passed 6, not run 2 (baseline) ===$"
  run countsdrop countsdrop 8 "" 3 0 '3 passed in 0.10s\n'
  has countsdrop "^=== gate counts: measured less than accepted (passed 2 < 3) ===$"
  samesession countsdrop
  # One violation, a recovery, then one more: the streak reset, so this is not decide.
  run dropflip dropflip  8 "" 0 2 '3 passed in 0.10s\n'
  # A DONE written with a violation is cleared, so restoring the counts alone is not done.
  run donedrop donedrop  2 "" 4 1 '3 passed in 0.10s\n'
  # A red gate's counts are never accepted: 9 then 5 is no violation against 3.
  run redhigh  redhigh   8 "" 0 1 '3 passed in 0.10s\n' 
  run countsback countsback 8 "" 0 1 '3 passed in 0.10s\n'
  run skipsup  skipsup   8 "" 3 0 '3 passed in 0.10s\n'
  has skipsup "^=== gate counts: measured less than accepted (not run 1 > 0) ===$"
else pending counts "=== gate counts"; fi

# Item 2: files that define the gate are listed, never blocked.
if grep -q "=== gate files touched" "$H"; then
  run gatefile gatefile  8 "" 0 1
  has gatefile "^=== gate files touched: Makefile sub/conftest.py ===$"
  a=$(grep -n "^=== gate files touched" "$T/logs/gatefile.log" | head -1 | cut -d: -f1); b=$(grep -n "^=== LOOP_RESULT" "$T/logs/gatefile.log" | head -1 | cut -d: -f1)
  if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; then v=PASS; else v=FAIL; FAIL=1; fi
  printf "%-10s gate files line comes before LOOP_RESULT  %s\n" gatefile "$v"
  run untouched done     8 "" 0 2
  has untouched "^=== gate files touched: none ===$"
else pending gatefiles "=== gate files touched"; fi

# Item 3: DONE carries a row per done criterion; unresolved ends the run as decide.
if grep -q "=== criteria" "$H"; then
  run notable  notable   8 "" 0 3
  # Once, because the challenged LOOP_STATUS.md was deleted and the quiet second turn left none.
  k=$(grep -c "^=== criteria: no table ===$" "$T/logs/notable.log" || true)
  if [ "$k" = 1 ]; then v=PASS; else v=FAIL; FAIL=1; fi
  printf "%-10s 'criteria: no table' printed once, got %s  %s\n" notable "$k" "$v"
  samesession notable
  run notablenever notablenever 3 "" 4 3
  lacks notablenever "LOOP_RESULT: done"
  run fewrows  fewrows   8 "" 0 2
  has fewrows "^=== criteria: 1 rows for 2 criteria ===$"
  run failrow  failrow   8 "" 0 2
  has failrow "^=== criteria: 2 rows, 1 pass, 1 fail, 0 unresolved ===$"
  # A verdict that is not pass, fail or unresolved counts as fail.
  run navverdict navverdict 8 "" 0 2
  has navverdict "^=== criteria: 2 rows, 1 pass, 1 fail, 0 unresolved ===$"
  run unresolved unresolved 8 "" 3 1
  if [ "$(head -1 "$T/repo/LOOP_STATUS.md" 2>/dev/null)" = "STATUS: DECIDE" ]; then v=PASS; else v=FAIL; FAIL=1; fi
  printf "%-10s LOOP_STATUS.md now opens 'STATUS: DECIDE'  %s\n" unresolved "$v"
  has unresolved "^=== criteria: 2 rows, 1 pass, 0 fail, 1 unresolved ===$"
  if grep -qx "harness: criteria unresolved: 2" "$T/repo/LOOP_STATUS.md"; then v=PASS; else v=FAIL; FAIL=1; fi
  printf "%-10s LOOP_STATUS.md names criterion 2 unresolved  %s\n" unresolved "$v"
else pending criteria "=== criteria"; fi

rm -rf "$HOME/loop-logs/$(date +%Y%m%d)-order.log" "$HOME/loop-logs/$(date +%Y%m%d)-order"
echo "logs: $T/logs"
[ "$FAIL" = 0 ] && echo "ALL PASS ($PENDING pending)" || { echo "FAILURES ($PENDING pending)"; exit 1; }
