# G7-LPFIN7: finish Last Protocol (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md (status every 5 calls; heartbeat; no git, no D:). Read .plan/handoff/LPSHRINK7-2.json, LPSHRINK7.json,
the LPRES7-2 report items in .plan/orch_todo.md, docs/G7_REFERENCE.md 13.9c-34 / -36. ORCH accepts 61x61 (the
3x3 economy buildings need a 3-deep row). Full brief, no skipping:
1. pt7_lpmap7 lpmap7_valid fail: cn_facility's approach strip (conf.approach [0,28,28,5]) paves cells 3 rows past the
   map's reserved facility site where the fuel depot / repair bay / dropship pad / QRF barracks stand. Fix so nothing
   overlaps: prefer moving those core plots in sim/maps/last_protocol.gd (the map owns the core layout) so the facility
   stays unchanged; pt7_lpmap7 0 fail; test_lpmap7 / test_cnfac7 green.
2. Helicopters on the LP helipads draw as small sprites at each pad's back corner, not centred / full size (the sim has
   them landed, lp_pad 0..5). Find why (landed air draw offset / scale, pad pivot, parked-air sprite) and fix so each sits
   centred on its pad at its normal size; also check the generic (skirmish) helipad still looks right. Shots: the six
   pads with their helicopters (fact shots.best, read them first).
3. Windowed LP speed: LPRES7 saw ~7 sim ticks/s windowed (busy PC). On the new 61x61 base, measure windowed tps at 1x
   (reserve on vs LpReserve7.enabled=false) and render vs sim split; if the game cannot hold 20 tps at 1x on this PC
   when it is not overloaded, find the cost (render or sim) and report it with numbers (fix it if it is in LP-only
   code you can change exactly).
4. test_lpreserve7::test_quiet_sector_returns_home failed once in a multi-test loop ("field 8, in 92"): find the cause
   (static state leaking between tests, test order, non-determinism) and fix it; run the whole file 5 times.
5. Re-run the LP neighbour tests (test_lpmode7, test_lpmap7, test_lpreserve7, test_lpperf7, test_det7, test_cnfac7,
   test_sent7) and windowed pt7_lpmode7, pt7_lpmap7, pt7_lpres7 once each: all 0 fail.
Live: PERF7L (combat/senses/shrapnel native), REGFIX7-3 (fac_drive7, flows). Check claims.
