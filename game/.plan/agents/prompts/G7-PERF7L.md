# G7-PERF7L: native ports to close the 2k sim gate (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md (status every 5 calls; heartbeat .plan/hb.sh; no git writes, no D:). Read .plan/handoff/PERF7K.json,
PERF7J.json, PERF7I.json. Gate (frozen): 2k sim ms/tick <= 1.2x G6.1. In-process ratio now ~1.24-1.25 (total ~27 vs ~22
ms). The gap is G7 behaviour / feature cost: combat cmb.act +3.7 ms (62k target finds vs 41k: more engagement), Senses7
~0.7, wounds passes ~0.5, shrapnel bursts ~0.6. PERF7K ported Formations7 to rts_core 0.5.4 (native/rts_core, Rust;
`cargo build --release` then `bash tools/build_native.sh`).
## Job: exact native ports, biggest payoff first (target in-process ratio <= 1.12)
1. The combat target search (Combat._find / find_target candidate loop incl. the _cand_ok chain, Fog.concealed and the
   WallFire7 cand_ok filter) into rts_core: same candidate order, same float math (f32 Vector2, f64 scalars), same
   tie-breaks; GDScript fallback kept; toggle for A/B.
2. Senses7 spot pass and/or the shrapnel burst (wound_hit rays) if 1 is not enough.
Proof per change: identical results on an A/B bench (thousands of random + real cases) AND the gate-scene hashes at
ticks 100..600 (b86d73d0a4246c4c ... 14f1c23c6ffd1d42) unchanged; tests test_formations7, test_squad7, test_sense7,
test_det7, test_wound7, test_perf_g6, test_wallfire7, test_fort, test_combat* / any combat owner test, test_hot_state
(report, no golden edits). Report the in-process ratio before/after (same-run pairs). ORCH runs the idle 6 pairs.
Live: REGFIX7-2 (fac_drive7, flows), LPSHRINK7-2 (LP files), LPRES7-2. Check claims.
