# G7-INTEG7: integration, evidence, package (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first, then PROGRESS.md "Active goal (G7 ...)": its **Done-when is frozen**; you produce the evidence
for each item, and you never weaken a check, test, fixture or threshold to make it pass. If an item can't be met,
say so plainly with the evidence (that is a valid outcome); never round "almost" up to "done".
Read the G6.1 integration precedent: PROGRESS.md's G6.1 section and the G6.1 INTEG commits (git log --grep "G6.1").

You run ALONE (no other agents): the PC should be idle for the perf and hash items. Check load first
(Get-CimInstance Win32_Processor LoadPercentage; count Godot processes) and record it with every number.
Board + heartbeat rules: post a status at least every 5 tool calls and before every long run with AGENT_BOARD
exported as the C:/ path; run every long run through `bash .plan/hb.sh INTEG7 <calls> <tokens> "<label>" -- <cmd>`.

## Do, in order
1. **test_hot_state re-baseline** (G7 changed the sim on purpose: owner G7 scope; record the authority in the
   commit-ready note): capture the new GOLD / GOLD_FLAT / HEAD values with TWO identical capture runs (same tree,
   same command, idle PC) and show they are identical; then update the goldens exactly the way G6.1 did
   (commit d6261b3 message describes it: "re-baselined for G6.1 on the owner's order (two identical capture runs)").
   All of test_hot_state's own parity checks (threaded == inline, native on/off, perf paths on/off, hot-state path)
   must pass unchanged.
2. **Done-when 1:** full test suite on the live tree: 0 FAIL and 0 SCRIPT ERROR. Fix what you can (small, clearly
   in scope); anything else goes in the report with cause and owner.
3. **Done-when 2:** determinism: every new G7 sim system twice-same-hash (the per-system tests already do; collect
   the raw lines), plus a recorded player drone flight replayed from commands giving the same hash (DRONE7 built
   this: find its test/flow; run it).
4. **Done-when 3** (idle PC): bench --fps 2k (p10 >= 60) x3 runs and 10k (p10 >= 30) x2 runs; 2k-unit sim ms/tick
   vs the G6.1 figure measured IN THE SAME SESSION (G6.1 = worktree at 55b4e04, e.g. C:/CODING/g7_regress2_wt;
   gate <= 1.2x). Report every run with load % and Godot process count.
5. **Done-when 4:** Last Protocol soak (tools/lp_soak7.gd; LPMODE7-3's notes in .plan/handoff/LPMODE7-3.json and
   commit 9f9d264): a headless run on the last_protocol map with the full pre-built base and AI-run strike teams that
   reaches the Tide and ends with a result line, 0 crashes, 0 invariant failures, 0 SCRIPT ERROR. A natural run can
   take hours: run it in the background through hb.sh and work on other items meanwhile; if the natural run can't
   finish in reasonable time, say so and also run the forced-Tide variant, reporting both honestly.
6. **Playtests:** run every G7 playtest flow windowed (tools/pt7_*.gd: G7_FLOWS in tools/ui_playtest.gd) and the
   G6.1 ones that touch changed systems; 0 SCRIPT ERROR; list any check that fails with its cause. Known open items
   to look at: pt7_drone7 drone7_strike_drop misses by ~6 tiles; pt7_lpmap7 camera stops still aim at the old ring
   sizes (re-aim them at BASE7's new rings: c491fb8); the PROTOCOL card stacks near-identical "suit breaches" lines
   (dedupe / update in place in presentation/ui7/protocol_advisor.gd); CINE7 CR 1545 (LP roster misses operators
   killed inside APCs: sim/systems/last_protocol.gd).
7. **Done-when 5:** packaged build: export exactly the way G6.1 did (find its export preset / script and the
   Downloads location used before), launch it from a clean folder with 0 SCRIPT ERROR (packaged smoke flows if
   G6.1 had them), copy the build to Downloads; update README.md and PLAY_ME (find them) so they describe G7
   accurately, limits included (PROVISIONAL numbers, what is placeholder, known gaps).
8. **PROGRESS.md:** write the evidence for each Done-when item (raw lines, paths), mark each met / not met, and a
   short "what's left" list. Do not mark anything met without evidence.

Files: you may edit tests' goldens (item 1 only, as described), small fixes anywhere clearly in scope (say each
one), tools/pt7_lpmap7.gd, presentation/ui7/protocol_advisor.gd, sim/systems/last_protocol.gd (CR 1545), README,
PLAY_ME, PROGRESS.md, export config. No git add/commit (ORCH commits). Never touch D:.
