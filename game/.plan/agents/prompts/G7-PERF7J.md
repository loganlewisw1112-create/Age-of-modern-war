# G7-PERF7J: exact sim headroom for the 2k gate (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md (status every 5 calls; heartbeat .plan/hb.sh; no git, no D:). Read .plan/handoff/PERF7I.json,
PERF7H.json, PERF7G.json. Gate (frozen): 2k sim ms/tick <= 1.2x G6.1; ORCH runs the final idle-PC 6 pairs at the end.
The new gate-scene hash after PERF7I's formation fix is 14f1c23c6ffd1d42 (600 ticks): every change you make must keep
it (prove at ticks 100..600) and keep test_det7 green. Fight now: G7 kills 1.32x G6.1, shots ~equal.
Job: profile both trees in-process (perf7h_prof.gd --sub, per-system, compare inside pairs; load is shared, use ratios
within a run) and cut G7-only cost with EXACT changes: Senses7._pass per-call lookups (_is_machine string compares,
cf() per target), shrapnel per-candidate Content lookups / add_supp, _vis_sync tail per hit, Wounds passes, the tick-1
_mass_line cost (measure it), movement drain. Target: G7 per-system total <= 1.12x G6.1 in the same in-process run.
Report per-system before/after, every change + hash proof, tests (test_squad7, test_formations7, test_wound7,
test_det7, test_perf_g6). Full brief: no skipping. Live: REGFIX7, WALLFIRE7 (combat/damage line-of-fire), LPSHRINK7,
LPRES7-2. Check claims before editing.
