# G7-LPSHRINK7-2: squeeze the LP base to ~59 and finish LPSHRINK7 (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md (status every 5 calls; heartbeat .plan/hb.sh; no git, no D:). Spec: docs/G7_REFERENCE.md 13.9c-36
(every word, incl. the follow-up answers: squeeze to ~59 by dropping the outer ring road and merging the defence row
into the turret row; 6th helipad = a 4th Attack Helicopter, Airlift in a heavy hangar). Handoff:
.plan/handoff/LPSHRINK7.json (layout, numbers, files, tests, census probe .plan/lpshrink7_census.gd, remaining steps).
## Build (full brief, no skipping)
1. Squeeze: outer band ~6 tiles (economy row, service lane, turret+defence row, wall), base ~59x59; keep every gate road,
   chicane, patrol route, gate post and the defence commander consistent; vehicles path on the service lane (prove a
   tank and an APC can drive the full loop and out of every gate). Howitzer coverage of every approach still holds
   (re-check with the same range argument LPSHRINK7 used; report counts).
2. Helipads: start.helipad_air = 4 a_attack_heli + 2 a_transport_gunship; all six pads loaded; Airlift in a heavy hangar.
3. LPSHRINK7's remaining steps: before soak (the old 3-ring numbers: use .plan/lpshrink7/soak_before.log if it finished,
   else ORCH's .plan/soak7/early_seed77.log as the before), after soak on the final layout (tools/lp_soak7.gd --seed=77
   --tide-at=600, heartbeat): phases, ending, rings fallen, ms/tick; tests test_lpmap7, test_lpmode7, test_cine7,
   test_lpperf7, test_lpreserve7, test_det7, test_cnfac7 (change checks only per the 13.9c-36 authority record, citing
   it); windowed pt7_lpmap7 and pt7_lpmode7 0 fail; new census; shots: whole base by day at a zoom that fits it + the
   helipad column with the loaded helicopters: fact shots.best (read them first, plain caption).
Files: LPSHRINK7's files (see handoff). Live: LPRES7-2 (lp_reserve7 + its defs; the seed call), REGFIX7, PERF7J.
