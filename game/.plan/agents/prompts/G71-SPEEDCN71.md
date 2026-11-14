# G71-SPEEDCN71: CN / facility / soldier files broken by the A5 +20% speed rule (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)

You are SPEEDCN71 (generation 1). Read `G71-FIX71_COMMON.md` first and follow it. SPEEDFIX71 has the core-sim files;
read the board for `fact speedfix71.cause` before each new file, and post yours as `fact speedcn71.cause`.

## Background
A5 ("every unit +20% speed", owner-locked) went in at the G7.1 start (fda25f9, `Content._apply_g71_speed`, x1.2 at load)
without a full suite run. These 6 files fail identically at HEAD fda25f9 and pass on G7 3a66ffc, whose only sim
difference is that rule. So each failure is either (a) sim code that behaves wrongly at the new speeds (fix the sim), or
(b) a test that hard-codes a speed-coupled number (post `testfix.<test>`, ORCH asks the owner). Decide per file, with
evidence (print the numbers in both trees). Never fix by slowing units down. RAMP71 already fixed one A5 break of this
kind: `transport.gd _tick_bay_boarder` lets a vehicle settle on the line-up for one tick (the APC stopped 0.52 tiles
short); its open note: soldiers still hide ~0.73 tiles short of the ramp foot (same pop), untested. Use it as a pattern.

## Your 6 files (failure lines from the wave-1 logs)
- `test_cnsuits7` test_variants_roles_and_weapons: "g7_cns_bastion / breaker / aegis / purifier / g7_b_cns_bastion ...
  heavier than a G6 exo suit" (read what "heavier" compares: likely a speed read from raw JSON vs loaded content).
- `test_cnsim7`: test_group_pincer_auto_operators_engage_then_remount "operators remounted (got 2, expected 0)";
  test_group_pincer_on_colossus_takes_minutes_and_two_topples "a lumbering colossus gets no stride factor".
- `test_cnrole7` (script error, 10/0): "Out of bounds get index '987' (on base: 'Dictionary')" at
  test_parked_units_hold_no_chase (tests/test_cnrole7.gd:324): find why that unit id is missing (died? never spawned?
  moved out of a lookup?) at the new speed.
- `test_sent7` test_always_on_watch (~400 s per run): "13.9c-38 heavier watch: long face W always has >= 6 Sentinels on
  the wall-walk / tower decks (min 5)".
- `test_wound7` test_crawler_obeys_move_order: "crawls slowly: 4.71 tiles in 10 s" (check whether the crawl speed is
  meant to follow unit speed, and what G7 measured).
- `test_cards8c` test_barracks_options (~160 s): "fresh men took the post ([935, 936] -> [935, 936])", "the
  hand-rotation latch clears once relieved".

Suggested order: test_cnsuits7, test_wound7, test_cnrole7, test_cnsim7, test_cards8c, test_sent7 (slowest last).
After your last sim change: test_hot_state, the 3 bench hashes, test_cnfac7, test_cnops7, test_airops71.
