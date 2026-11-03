# G7-PERF7K: close the 2k sim gate (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md (status every 5 calls; heartbeat .plan/hb.sh; no git, no D:). Read .plan/handoff/PERF7J.json (every
word), PERF7I.json, PERF7H.json. Gate (frozen): 2k sim ms/tick <= 1.2x G6.1 (55b4e04); in-process per-system ratio is
1.22-1.27 now. Gate-scene hash 14f1c23c6ffd1d42 at 600 ticks must hold for every change (exact only).
## Jobs, by payoff
1. Formations7 tick-1 assign: G7 650-710 ms vs G6.1 113 ms (polish 358 ms): ~1 ms/tick of the 600-tick average. Make it
   exact and fast: a native port of _polish_near_fast / _assign_exact into the rts_core GDExtension (the project
   already ships native gather paths; find the C++ source + build recipe in the repo / board history (rts_core 0.5.x),
   rebuild the DLL, keep the GDScript path as fallback, prove identical permutations on the perf7j_assign bench and the
   same hash) OR an exact algorithmic cut (spatial bucketing of candidate pairs with the same visiting order).
2. Shared-code exact speedups (PERF7J next_steps 1): Morale.add_supp / cover_level (~1 ms/tick), Fog.concealed /
   Combat._find _cand_ok chain, Damage.wound_hit. WALLFIRE7 is finished: combat.gd / damage.gd are free (keep its
   WallFire7 calls intact).
3. Rerun test_sense7, test_det7, test_squad7, test_formations7, test_wound7, test_perf_g6, test_wallfire7, test_fort.
4. Report in-process per-system ratio (same-run pairs) before/after. ORCH does the final idle 6 pairs.
Live: REGFIX7 (fac_drive7, flows), LPSHRINK7-2 (LP files), LPRES7-2 (lp_reserve7). Check claims.
