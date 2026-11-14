# G71-SPEEDFIX71: core-sim files broken by the A5 +20% speed rule (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)

You are SPEEDFIX71 (generation 1). Read `G71-FIX71_COMMON.md` first and follow it. SPEEDCN71 has the CN / facility /
soldier files; post any root cause you find that may also explain theirs as `fact speedfix71.cause` so they can use it.

## Background
A5 ("every unit +20% speed", owner-locked) went in at the G7.1 start (fda25f9, `Content._apply_g71_speed`, x1.2 at load)
without a full suite run. These 7 files fail identically at HEAD fda25f9 and pass on G7 3a66ffc, whose only sim
difference is that rule. So each failure is either (a) sim code that behaves wrongly at the new speeds (fix the sim), or
(b) a test that hard-codes a speed-coupled number (post `testfix.<test>`, ORCH asks the owner). Decide per file, with
evidence (print the numbers in both trees). Never fix by slowing units down.

## Your 7 files (failure lines from the wave-1 logs)
- `test_content_g6`: "m_stealth_drone speed in (0, 10] (tiers bucket unchanged)".
- `test_perf`: test_attack_order_promotes_at_once "lone far unit is REDUCED" / "still REDUCED until the next tier
  recompute"; test_tier_promotion_on_contact_and_no_duplication "units were REDUCED while far apart (0 unit-ticks)",
  "tier changes happened (0)". Likely linked to the content_g6 line: check how `sim/systems/tiers.gd` buckets by speed.
- `test_path7` test_last_protocol_facility: "APC: hull within 20 deg of its travel (88.7)".
- `test_naval_g6` test_sea_mines_laid_and_swept: "the sweeper cleared the 2-wide lane (got 3, expected 4)", "no sea
  mines left (got 1, expected 0)".
- `test_gen61` test_designates_and_sets_medevac: "the JTAC designates the believed enemy group (0)".
- `test_real61` test_fatigue_march_rest_and_assault: "fatigue grows with a long march (0.0)", "fatigue recovers at rest
  (0.0 -> 0.0)", "rest lowers fatigue".
- `test_drone_team` test_drones_shot_down_by_aa_and_jammed_by_ew: "drone shot down before impact".

Suggested order: test_content_g6 + test_perf together (tiers), then test_real61, test_gen61, test_drone_team,
test_naval_g6, test_path7. After your last sim change: test_hot_state, the 3 bench hashes, test_mil, test_squad61,
test_perfsim71.
