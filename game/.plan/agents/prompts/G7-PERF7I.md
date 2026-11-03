# G7-PERF7I: finish the big-group formation fix honestly, then the 2k sim gate (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board; status DIRECTLY every 5 tool calls, never 10 min silent: heartbeat .plan/hb.sh around
long runs; no git, no D:). Successor to PERF7H: read .plan/handoff/PERF7H.json (every word: changes, hash proofs, tools,
next_steps) and PERF7G.json. Gate (frozen, PROGRESS G7 Done-when 3): 2k-unit sim ms/tick <= 1.2x G6.1 (55b4e04).
## The catch you must resolve FIRST
PERF7H's Formations7 fix (big groups whose shape overflows the map mass on the goal as 12-man hollow-square boxes) removed
the corner-walk bug, but the gate fight changed: 1742 units alive at tick 600 vs G6.1's 995 (bugged G7: 813). A cheaper
sim because fewer units fight would NOT be an honest gate pass. So:
1. Measure engagement in both trees over the 600 ticks (deaths per 100 ticks, ShotFired count, units in contact, time
   to first contact, where the blocks end up) for: G6.1, G7 mass_fallback on, G7 off.
2. Read G6.1's fix (d601e1d in C:/CODING/g7_regress2_wt: "groups > 12 are now chunks of <= 12 abreast") and make G7's
   big-group fallback match its intent for an ATTACK move: chunks of <= 12 placed as a line / staggered line facing the
   enemy (attack-move), not a defensive box blob; keep groups <= 12 bit-identical (prove with a small-group hash A/B)
   and big groups whose shape fits unchanged. Target: engagement in the same range as G6.1 (state your bound and why).
   The owner wants real military formations (G7 13.x squads / formations): no blobs, no walking back to base.
3. Regression test (PERF7H next_step 1, adjusted): 0 edge/corner slots, sane mean slot distance, AND the armies engage
   (deaths by tick 600 within a stated band of G6.1's), and mass_fallback=false still shows the corner bug.
4. Tests: test_squad7, test_det7, test_perf_g6, test_senses7, test_squad61 / test_officer61 if present, test_wound7;
   test_hot_state (report golden moves, do NOT edit goldens: ORCH re-baselines).
5. Gate: 6 alternating pairs (bash .plan/perf7g_pairs.sh 6 final7i res://.plan/sim_ab7.gd): raw table, median pair ratio,
   CPU load, plus the engagement numbers next to it. If the ratio is still > 1.15x with a fair fight, use PERF7H's
   next_step 5 (all exact) for headroom.
Files: sim/systems/formations7.gd (yours), wounds.gd (done, leave), senses7.gd / shrapnel.gd (exact only), tests.
Post a claim first. Live: LPRES7, FACINT7, CIWS7-6 (check claims).
