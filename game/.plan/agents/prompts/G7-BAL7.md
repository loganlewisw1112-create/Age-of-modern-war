# G7-BAL7: the facility is a fortress (~4x to break), Sentinels strong but not invincible (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board; status DIRECTLY every 5 tool calls with calls_used / tokens_used_est / next_action,
including before / after long runs; no git, no D:). Spec: docs/G7_REFERENCE.md **13.9c-33** (owner choice: "Fortress:
needs ~4x"; read the authority record), 13.9c-10/-11 (Sentinels "very strong ... dont make them invincible"),
13.9c-27/-27a (drone hive "defend the facility at all cost"), 13.9c-32 (roof CIWS).
State: test_sent7 test_balance_fight fails "Sentinels lose vs combined arms" (they now HOLD at 2.5x: 16-18 left, 0
attackers inside) since the drone hive landed; CIWS7-2 proved the CIWS fires 0 rounds there. test_dronebay7
test_hive_breach_full_commit fails: its 6000-hp breach foe dies to the facility defences by ~tick 112 before the whole
garrison launches (a fixture problem: give it a foe that survives, as the other hive test does with 1e6 hp; never
weaken the full-commit checks).
## Build
1. Measure the full facility vs combined arms (armour + artillery + infantry, the SENT7-4 assault drill in _fight) at
   2.5x, 3x, 3.5x, 4x, 4.5x (3 seeds each if time allows): where does it break? Also Sentinels-only (drone bay off, as
   the drill already does via _silence for the guns-silenced variants) at 2.5x.
2. Tune (PROVISIONAL numbers in the content json of the system you tune: drone hive / Sentinels / towers) so the full
   facility HOLDS at 2.5x and a ~4x combined-arms assault BREAKS IN (core reached or the compound overrun), and the
   Sentinels alone (drone bay off) still lose to combined arms at 2.5x (not invincible). Infantry x2/x3 and Machine x2.5
   stay HELD. Prefer small changes; report every number you change.
3. Tests: test_sent7 test_balance_fight becomes, per the 13.9c-33 authority record: full facility holds at 2.5x; a ~4x
   combined-arms assault breaks in; Sentinels alone (drone bay off) lose to combined arms at 2.5x. Cite 13.9c-33 + the
   owner quote in the test. Fix the test_dronebay7 hive-breach fixture. Keep test_cnfac7 / test_lpmode7 / test_det7 /
   test_ciws7 / test_wallturret7 green.
Files: sentinels7.gd + defs_g7_sentinels.json, drone_bay7.gd + defs_g7_dronebay.json, ciws7 defs, tests/test_sent7.gd,
tests/test_dronebay7.gd (no live owners; post a fact naming each file before editing). LIGHT7-7 is live (display only).
