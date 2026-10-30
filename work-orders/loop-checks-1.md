# Work Order, loop-checks 1: the harness checks the checks

**For:** `nightly-loop.sh` (isolated mode, branch from `main`). **Repo:** the chezmoi source, looped
from its own clone `~/TORMENTA/chezmoi-loop`.
**Status:** reviewed before launch on 2026-10-29. A throwaway reference built to this order reached
`ALL PASS (0 pending)`, and each item alone left the gate green with the other two `PENDING`. The
review found five gaps in this text (pytest's `(0:01:15)` suffix, backticks in `BUILD_PROMPT`, the
spaced separator and unknown verdicts, where criteria end, sort order), now fixed, and 11 of 30
mutations the tests missed; the tests were strengthened until all 35 mutations, five of them new,
turned the gate red. The reference is not in the repo; write your own.
**Read first:** `tests/nightly-loop-test.sh` (the spec: every log line, exit code and commit count
it asserts, cases after the `decisions/loop-checks.md` banner), then `bin/executable_nightly-loop.sh`
end to end. The decision is `decisions/loop-checks.md` in the sopori-cluster repo; everything you
need from it is restated here.

The harness commits whatever passes `make validate`, so an agent that weakens a test, or a test
that skips inside the gate, turns the gate green without anything being measured. And DONE is
prose, so an unresolved criterion can be reported as a pass. This order makes the harness check
both. Three items, each mergeable alone; do them in order.

## What this order is NOT

- Never edit `tests/`, the `Makefile`, `.chezmoiignore`, `work-orders/`, or any file but
  `bin/executable_nightly-loop.sh`. A failing case means the harness is wrong, never the test. A
  `PENDING` case is not done.
- No new terminal state, exit code or environment knob. No change to `loop-train.sh`,
  `loop_run.py`, the engine call, `ALLOWED`, or how the gate is run and timed.
- No repeat-failure cap (the decision rejected it on the logs).

## LOOP_CONSTRAINT

Edit only `bin/executable_nightly-loop.sh`. Bash plus the `python3` already used for JSON; no new
dependencies. Every new log line is printed exactly as written below (the tests match whole lines).
Keep the file's commenting style: say why, with the incident that taught it.

## 1. The gate's counts ratchet

After every gate run, read the pytest summary lines in `$GATE_OUT`. First strip ANSI colour codes
(`\x1b\[[0-9;]*m`) from each line. A summary line is then one matching
`^=*\s*\d+ \w+(, \d+ \w+)* in [0-9.]+s( \([0-9:]+\))?\s*=*$`: with `-q` pytest prints it bare,
without it between `=` runs, and a run over a minute ends `in 75.12s (0:01:15)`. A gate slower than
a minute that read `none read` would switch the ratchet off silently. Sum across every summary line
in the output (some gates run pytest twice):
**passed** is the `passed` count; **not run** is `skipped + xfailed + deselected`. Ignore other
words (`warnings`, `failed`, `errors`, `xpassed`).

- Baseline gate: print `=== gate counts: passed P, not run N (baseline) ===`, or
  `=== gate counts: none read ===` when no summary line is found.
- Every later gate: print `=== gate counts: passed P, not run N (accepted AP/AN) ===`, where
  `AP/AN` are the accepted counts this gate is compared against (before this gate is accepted), or
  `=== gate counts: none read ===`. When nothing has been accepted yet, print the `(baseline)`
  form's numbers with `(accepted none)` and accept them.
- The **accepted** counts are those of the last green gate whose counts were read, starting with
  the baseline. Red gates print their counts but are never accepted or compared.
- On a **green** gate, if `P < AP` or `N > AN`, it is a violation:
  - Print `=== gate counts: measured less than accepted (passed P < AP) ===`, or, when passed did
    not fall, `=== gate counts: measured less than accepted (not run N > AN) ===`.
  - **Do not commit.** Resume the same session (as the red-gate path does) with: "The gate
    measured less than it did before your turn: passed P (was AP), not run N (was AN). Restore
    what it measured. If the work order requires measuring less, write STATUS: DECIDE in
    LOOP_STATUS.md and say why." Clear a `STATUS: DONE` the agent left, as the red path does.
  - A second violation on the very next gate ends the run with `finish decide` and the reason
    `gate measured less twice running: passed P (accepted AP), not run N (accepted AN)`. A green gate
    with no violation resets this.
  - If the agent wrote `STATUS: BLOCKED` or `STATUS: DECIDE` on a violating gate, finish with that
    state as the red-gate path does, still without committing.
  - The `finish` warning about uncommitted changes says "gate red" today; make it
    `(gate red, or measured less, at loop end)`.
- `none read` never blocks anything.

Spec cases: `noneread`, `countsup`, `sum`, `countsdrop`, `dropflip`, `donedrop`, `redhigh`,
`countsback`, `skipsup`.

## 2. Gate files touched are reported, never blocked

In `finish`, before the `LOOP_RESULT` line, list the files changed between `$BASE_SHA` and `HEAD`
whose **basename** is one of `Makefile`, `conftest.py`, `pytest.ini`, `setup.cfg`, `tox.ini`,
`.coveragerc`, `mypy.ini`, `ruff.toml`, `pyproject.toml`, `package.json` (so `sub/conftest.py`
counts). Print `=== gate files touched: <paths> ===` (repo-relative paths, sorted in byte order as
`LC_ALL=C sort` does, space-separated) or
`=== gate files touched: none ===`. Put the same list as the first line of the draft PR body:
`Gate files touched: <paths|none>`.

Spec cases: `gatefile`, `untouched`.

## 3. DONE carries a criteria table

Add to `BUILD_PROMPT`, after the STATUS list, this text exactly. `BUILD_PROMPT` is a double-quoted
bash string, so it must contain no backticks (bash would run them as a command and the harness
would die on a syntax error) and no unescaped double quotes:

    With STATUS: DONE, add a table to LOOP_STATUS.md with one row per
    numbered item under the work order's '## Done criteria' heading. Its
    header row is | # | criterion | verdict | evidence |. The verdict is
    one of pass, fail or unresolved; the evidence is a command and its
    result, a test id, or a path. Unresolved is an honest answer, never
    a pass.

When the agent wrote `STATUS: DONE` and the gate is green (after committing, as now), read the
table from `LOOP_STATUS.md`: data rows are lines starting with `|`, excluding the header (the row
whose third cell is `verdict`; review fix 2026-10-29, the order first said any row containing the
word, which drops a criterion that names a verdict) and separator rows (any line matching `^\|[\s:|-]+\|?\s*$`, so
`| --- | --- |` is a separator too). Split a row on `|`: the first cell is the criterion number, the
third is the verdict, trimmed and lowercased. A verdict other than `pass`, `fail` or `unresolved`
(`n/a`, `partial`) counts as `fail`.

The criteria count C is the number of lines matching `^[0-9]+\. ` after the `## Done criteria`
line in `$ORDER` and before the next line starting `## ` (or the end of the file). Numbered lines
elsewhere in the order are not criteria. If `$ORDER` has no `## Done criteria` line, C is 1.

- No data rows: print `=== criteria: no table ===`.
- Fewer rows than criteria: print `=== criteria: R rows for C criteria ===`.
- Otherwise print `=== criteria: R rows, P pass, F fail, U unresolved ===`.
- No table, too few rows, or any `fail`: do not finish. Delete `LOOP_STATUS.md` and resume the
  same session with what was wrong ("write the table", "R rows for C criteria", or "criterion N
  is marked fail: fix it or say why it cannot be met"; for a verdict outside the three, "criterion
  N verdict X is not pass, fail or unresolved").
- Any `unresolved` (and no `fail`): replace the first line of `LOOP_STATUS.md` with
  `STATUS: DECIDE`, keep the rest, add a line `harness: criteria unresolved: <numbers>`, and
  `finish decide`.
- All `pass`: `finish done` as now.

Spec cases: `notable`, `notablenever`, `fewrows`, `failrow`, `navverdict`, `unresolved`.

## Done criteria

1. `make validate` ends `ALL PASS (0 pending)`, with every pre-existing case still passing.
2. `git diff main --stat` shows only `bin/executable_nightly-loop.sh`.
3. The new code says why in the file's style, naming `decisions/loop-checks.md`.
4. `STATUS: DONE` with the criteria table this order describes, one row per item above.

## For the reviewer (what the gate cannot see)

- The gate is green at `(2 pending)` too, and the harness running this loop does not check
  criteria, so a DONE after one item finishes the run as `done`. Check the final line reads
  `ALL PASS (0 pending)` before anything else.

- The `BUILD_PROMPT` wording; the PR-body line (the tests run with `LOOP_NO_PR`).
- A pytest summary inside a red gate's output is never accepted; a resumed session after a
  violation still gets the counts in its prompt.
- Deploy: `chezmoi diff` alone, read it, then `chezmoi apply ~/bin/nightly-loop.sh`; copy to the
  vault's `_Scripts/nightly-loop.sh`; update the runbook's harness section. The first real run
  afterwards is supervised.
