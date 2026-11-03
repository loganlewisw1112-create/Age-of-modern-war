# G7-PERF7F: the counter-nanite facility's sim cost (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board; status DIRECTLY every 5 tool calls with calls_used / tokens_used_est / next_action,
including before / after long runs; no git, no D:). Frozen Done-when (PROGRESS.md Active goal G7): idle-PC perf 2k p10 >= 60
fps, 10k p10 >= 30, 2k sim <= 1.2x G6.1 (55b4e04, G6.1 tree at C:/CODING/g7_regress2_wt/game); LP soak reaching the Tide.
DRONEBAY7-2 measured (.plan/db7_ab.gd, 2k units, river_crossing_s, 600 ticks): no facility ~28 ms/tick; WITH a CN
facility the facility as a whole adds +14..+33 ms/tick (not the drone bay: its share is 0.33-0.40 ms). Today many G7
facility systems landed: CnFacility, WallWalk7, Sentinels7, Engineer7, FacDrive7, VehDrive7, DroneBay7, Traverse7,
WallTurret7, Turrets7, BaseState7, CnRole7, Vanta7, Apc7, fac_suits7 (inside fac_drive7), plus display layers.
## Build
1. Profile a 2k fight with a facility per system (.plan/prof7.gd per-system timings; extend it) back-to-back with the
   same scene without a facility; find the systems / functions that cost the +14..33 ms (full-unit scans per tick,
   per-unit loops over all units, path re-plans, union-find per call, SimIndex scans without caching...). Post the
   table on the board.
2. Fix the top costs without changing behaviour (hash-identical where possible: prove it with two runs before / after;
   where a fix must change the hash, say so and why). Cache per tick, stagger thinks, index by cell, early-outs.
   Files: only systems with no live owner, posting a fact naming each file before you edit it; PATH7 (veh_drive7.gd,
   movement except gates), TURRET7C (traverse7.gd, turrets7, wallturret7), LIGHT7-5 (display) are live: change_request.
3. Measure after (same scene, back-to-back, 3 alternating pairs, median) and the 2k bench without a facility
   (.plan/sim_ab7.gd vs the G6.1 tree) to confirm the 1.2x gate; test_lpperf7 green.
Report numbers honestly (shared PC: alternate runs; never claim idle-PC fps).
