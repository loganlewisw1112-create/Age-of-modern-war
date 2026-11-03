# G7-LPSHRINK7: shrink the Last Protocol base drastically (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board; status DIRECTLY every 5 tool calls, never 10 min silent: heartbeat .plan/hb.sh around
long runs; no git, no D:). Spec: docs/G7_REFERENCE.md **13.9c-36** (every word, with the owner answers and the ORCH
helipad decision), plus section 10 (Last Protocol), 13.9c-34 (100-Sentinel reserve: unchanged), 13.9c BASE7 notes
(patrols, gate posts). Owner verbatim: "i feel like the base now is TOO mf big for the last protocol game mode help me
decide HOW and what to remove to shrink it down drastically so its more realistically difficult -- obviously facility
stays same in center with all of its upgrades/etc".
Census today (.plan/orch_lpbase.gd, seed 77, map last_protocol 512x512): rings outer 87x87 / economy 73x73 / core 53x53;
874 wall segments; outer ring ~160 defences; economy ring 45 generators, 29 depots, 8 refineries, 7 barracks, 6 research,
3 hospitals, 3 exo garages, 3 motor pools; core: CN facility + HQ, company HQ, airfield, 3 heavy hangars, 2 VTOL pads,
2 helipads, 4 howitzer pits, 5 SAM, 4 laser CIWS, 3 barracks, repair bay, ...; ~344 own units on the map.
## Build (answers: two tight rings; defences + army about half; economy about half; 6 helipads loaded)
1. Layout: the economy ring is deleted; an inner wall around the facility + HQ + air pads and one outer defensive wall
   close around it, about 55x55 tiles across; the kept economy sits between the two walls. Find where the layout comes
   from (lp_setup.gd layout / build_rings, the last_protocol map's map.lp.base, lp_world.gd map generation, map file /
   generator) and change it at the source so the map, the walls, gates, patrol routes (lp_garrison7), gate posts, the
   defence commander (lp_defence), creep / Machine spawn distances, rings_fallen / endings (last_protocol.gd) and the
   LP HUD all agree with 2 rings. Facility untouched (same position, size, parts, upgrades, reserve).
2. Defences ~half keeping the mix (about 80 total), army ~half, economy ~half (all kinds incl. airfield: hangars 3->1-2,
   VTOL pads 2->1), all PROVISIONAL numbers in content / rules, not hard-coded.
3. Helipads: 6 total (2 + 4 new) each with a helicopter loaded at start: 3 a_attack_heli, 2 a_transport_gunship,
   1 a_airlift (check pad / size rules in content; use a_forward_helipad or a heavy pad if a type needs it). They sit
   parked and usable by the player (and by the LP defence commander only if it already handles air).
4. Difficulty sanity: run the LP soak (tools/lp_soak7.gd --seed=77 --tide-at=600, heartbeat) before and after: report
   phase timing, rings fallen, ending, ms/tick (should drop with fewer entities); LP must still be winnable / losable
   (report ending). Also print a new census with the same probe (.plan/orch_lpbase.gd).
5. Tests: update the LP tests that assert 3 rings / old totals ONLY per the 13.9c-36 authority record (cite it), keep
   every other check: test_lpmode7, test_lpmap7, test_lpperf7, test_lpreserve7, test_det7 (LP scenes), test_cnfac7.
   Windowed pt7_lpmap7 + pt7_lpmode7 0 fail; new overview shots of the smaller base (whole base at a zoom that fits it,
   day; plus the helipad row with the loaded helicopters): post fact shots.best (read them first, plain caption).
Files: lp_setup.gd (NOT the LpReserve7.seed call line in fill_facility: LPRES7-2 owns lp_reserve7), lp_world.gd,
last_protocol.gd, lp_garrison7.gd, lp_defence.gd, the LP map source, LP content json, LP tests / flows. Live: LPRES7-2,
WALLFIRE7, PERF7I, CIWS7-6, FACINT7: check claims first.
