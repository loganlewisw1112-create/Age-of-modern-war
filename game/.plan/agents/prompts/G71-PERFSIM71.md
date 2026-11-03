# G71-PERFSIM71: sim cost at or below G6 (E2, sim side)

You are PERFSIM71. Read `G71_COMMON.md` first and follow it. Budget: MAX_TOKENS 750000, MAX_TOOL_CALLS 140.
Scope: `docs/G71_SCOPE.md` part E2, the Pre-start decision on the sim gate, Done-when 3.

## The gate (owner-clarified 2026-11-02)
Sim ms/tick on the existing **2k benchmark** (`tools/bench.gd` / the 2k fight + mixed AB scenarios) at or below **G6**
(a `git worktree` of branch `g6`, built and run on the same PC in the same session, alternating pairs, median, idle PC:
0 other Godot processes when you measure; note any you can't avoid). Last recorded: G7-final 1.42x G6.1 and G6.1 1.18x
G6, so G7.1 starts ~1.6-1.7x G6. That is a ~40% cut. **First measure it fresh** (post `fact perfsim71.baseline` with G6,
G6.1 (`55b4e04`), G7 (`g7` branch) and current g71 numbers, method and raw pairs).

## Then
1. Profile (existing prof7*.gd tools, tiers, per-system timers) and post the ranked cost table.
2. Cut cost with **exact** changes first (same results, hash-identical vs the current goldens): caching, fast paths,
   staggered cadences that are already equivalent, data layout, moving hot loops to native (rts_core via
   tools/build_native.sh stage/swap; GDScript fallback must stay hash-identical with native on/off).
3. Where an exact change isn't enough, a behaviour-equivalent approximation is allowed only through tiers.gd (same
   rules, cheaper in huge fights) and only with a change_request to ORCH explaining the hash move first.
4. Add an **LP-peak benchmark case** to tools/bench.gd / scale_bench.gd: the Last Protocol map, full base, ~150
   friendly robots (use existing sentinels / UGV / drones as stand-ins until wave 3), **1,000+ Machine units**
   attacking from several sides. Post `fact bench.lp_peak` with how to run it; PERFDRAW71 uses it for fps.
5. Future-proof: post `fact perf71.budget` = the per-system ms budget for 2k that later waves must stay inside.

## Stop rule
If after the exact wins the gate still looks unreachable, **stop and report** with numbers and the options (the owner
decides; never cut a feature or quality to reach it).
Tests `tests/test_perfsim71.gd` (hash parity native on/off, threaded on/off, perf paths on/off at 2k and 10k).
