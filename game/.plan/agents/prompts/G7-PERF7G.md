# G7-PERF7G: 2k sim cost back under 1.2x G6.1 (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board; status DIRECTLY every 5 tool calls with calls_used / tokens_used_est / next_action, also
before/after every long run; no git, no D:). Gate (PROGRESS Active goal G7 Done-when 3, frozen): 2k-unit sim ms/tick <=
1.2x the G6.1 figure (55b4e04) measured in the same session. Bench: .plan/sim_ab7.gd (river_crossing_s 2k fight, 600
ticks, NO CN facility), same script in both trees: G7 = this tree, G6.1 = C:/CODING/g7_regress2_wt/game (read-only for
you except dropping a copy of a bench script into its .plan/). Last busy-PC result 1.65x (before PERF7F's fixes).
PERF7F handoff (.plan/handoff/PERF7F.json) has the per-system profiler .plan/prof7fac.gd (--case=A = this gate scene,
--sub = sub-phases) and what was already cut (mostly facility-case costs).
## Build
1. Per-system ms/tick for the gate scene in BOTH trees (copy prof7fac.gd's per-system timer loop into a G6.1-safe probe
   if needed), inside alternating pairs: which systems does G7 add or make slower? (Suspects from INTEG7: wounds,
   senses7, squads7, the movement prepass ~1.7 ms, morale.) The PC is shared with other agents: compare inside pairs,
   use medians, report CPU load.
2. Cut the G7 overhead with hash-preserving changes first (prove per change: same state_hash at 600 ticks on and off,
   or a per-tick compare). A hash-changing change needs a stated reason and goes in the report (test_hot_state will be
   re-baselined after). Never remove or weaken a G7 feature, test or threshold to win time.
3. Final: 6 alternating pairs of sim_ab7 (G6.1 vs G7), with the raw numbers, median ratio and CPU load at the time.
   Run test_perf_g6, test_hot_state (record its result; 5 known golden fails until the regold), test_det7, test_squad7,
   test_wounds7 (or whichever tests own the systems you touch).
Files: any sim system you profile EXCEPT sentinels7.gd, drone_bay7.gd, ciws7.gd and their defs (BAL7 / CIWS7-3 live).
Post a claim fact naming each file before editing; check the board for live claims first.
