# PERF5: per-system full-scan sweep (index-based iteration)
Read G3B_COMMON.md first. Context: the owner's #1 ask is no lag with thousands of units. Native movement (N1-core-2) and fidelity tiers + native combat (PERF4) are cutting the big systems. PERF4 measured that the remaining systems each make a full pass over `w.entities` every tick: at 10k units on valley_conquest_l, construction 19.3, production 10.9, gather 19.1, repair 20.0, orders 10.2 and victory 12.7 ms per tick, about 92 ms, more than the whole 50 ms budget.

Your files: `sim/systems/construction.gd`, `production.gd`, `gather.gd`, `repair.gd`, `orders.gd`, `victory.gd`, `territory.gd`, `status.gd`, `damage.gd`, `ops.gd`, `ops_missions.gd`, `bridges.gd`, `tests/test_perf_systems.gd`. NOT yours: movement.gd (N1-core-2); combat/supply/morale/fog/economy/tiers.gd/sim_index.gd (PERF4 and its successor); `sim/ai/**` (AI4 line); world.gd (orchestrator: post a CHANGE_REQUEST).

PERF4's change request (board seq 770), your starting point:
- `const SimIndex = preload("res://sim/systems/sim_index.gd")` (PERF4's file).
- Replace `for id in w.entities: ... if e.kind != "building": continue` with `for e in SimIndex.of(w, "building"):` (and the same for "unit", "resource", "wreck"), skipping entries no longer in w.entities.
- Ascending id order must be unchanged: determinism.
- Where a loop needs only a subset (builders, gatherers, repairers, buildings with queues, construction sites), filter once via a static per-def flag cache, or keep a subset list maintained in the index.
- status.ew_tick: iterate only EW units (per-def cache), and use the combat spatial grid for targets when present.
Also check each system for O(n²) patterns (nearest-X searches over all entities per unit) and use the spatial grid (`sim/native_core.gd` make_grid / combat's grid in w.cache) or per-tick buckets.

Rules:
- Behaviour must be identical. Same seed gives the same state_hash before and after your change on a 3000-tick AI-vs-AI fixture; record the hash with the original code first. If an optimisation can't keep the hash identical, it must at least keep all tests green, and you must say exactly why the hash changed.
- Measure per-system ms with `tools/scale_bench.gd --breakdown` (N1's) at 2k on river_crossing_s and 10k on valley_conquest_l, before and after, with machine load stated.
- Full suite green at the end (in hb.sh).
MAX_TOKENS 600000, MAX_TOOL_CALLS 150, board id `PERF5`.
