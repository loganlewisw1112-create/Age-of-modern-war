# G61-PERF61: keep G6.1 fast (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G61_COMMON.md first.

G6.1 added a lot of thinking to every unit (squad AI, chain of command + intel, officer drills, realism pass, ammo
bearers, plans, auto generals). Frozen Done-when items:
- 4: 2k-unit sim ms/tick <= 1.2x the G6 figure measured in the same session and load.
- 6: windowed fps gates still PASS: 2k on screen p10 >= 60 fps, 10k zoomed out p10 >= 30 fps.
VFX61 measured on a loaded PC (87-99% CPU): 2k p10 41.8 fps (G6 was 83.7 under similar load) and the same with effects
hidden; profile: p_ent 7-14 ms (render, ANIMA61-2 is rebuilding entity_layer now) and sim 12-16 ms per frame.

## Baseline
ORCH created a detached worktree of the G6 commit 979a6d8 at
`C:/Users/logan/AppData/Local/Temp/claude/D--CODING-PROJECTS---CURRENTLY-WORKING-ON-RTS-Age-of-Modern-Warfare/1121247f-c9b8-4ed3-adb4-546f11b33109/scratchpad/g6base/game`
(run `--import` there once). Never edit it; never run git there. Run the SAME benches back to back in both trees
(alternate G6 / G6.1 / G6 / G6.1, record CPU load and Godot process count each time) so load noise cancels:
- `tools/scale_bench.gd` 2k on river_crossing_s and 10k on valley_conquest_l with `--breakdown` (per-system ms);
- the fps harness `tools/bench.gd -- --fps --fps-secs=30` (2k on screen, 10k zoomed out).

## Your job
1. Measure and attribute the G6 -> G6.1 sim cost per system (squad_ai, command_net, intel, morale realism pass /
   fatigue / veterancy, doctrine drills, ammo_bearer, plans, commanders/general, ops) at 2k and 10k.
2. Optimise the sim side WITHOUT changing behaviour: you may edit the files of FINISHED agents (squad_ai.gd,
   command_net.gd, intel.gd, morale.gd, fatigue.gd, veterancy.gd, ammo_bearer.gd, plans.gd, doctrine/*, ops*.gd,
   orders.gd, supply.gd, tiers.gd, sim_index use) — cadence/staggering, caching, early-outs, avoiding per-tick allocations
   and Dictionary churn, skipping work for units that can't act (tier REDUCED, idle far from enemies), using SimIndex
   buckets / the native grid where available. Rule: the state hash for a fixed seed must be IDENTICAL before and after each
   optimisation (prove with two runs). If a speed-up needs a behaviour change, report it to ORCH instead.
   NOT yours (live): entity_layer.gd / batch_art.gd / motion.gd (ANIMA61-2), vehicle drawers (ANIMB61), general*.gd /
   commanders.gd / ai_command.gd (GEN61-2), and files INTEG61 is editing (check its `claim files` on the board).
3. Render side: profile p_ent at 2k and send ANIMA61-2 concrete findings by change_request (where the time goes, what to
   cache). Coordinate; don't edit its files.
4. Report final numbers in a table: G6 vs G6.1 (before your work) vs G6.1 (after), same session, with CPU load.
Tests: after each optimisation run the owning feature's test file (test_squad61, test_chain61, test_real61, test_officers61,
test_bearer61, test_plans61) plus test_perf_g6 and test_perf; hashes identical.
Machine load: you share the PC with other agents. One heavy job at a time; record load with every number.
