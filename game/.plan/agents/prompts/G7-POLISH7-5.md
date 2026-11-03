# G7-POLISH7-5: fuel bay re-sited so it makes sense + atmo7 shots (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board, heartbeat via `bash .plan/hb.sh POLISH7-5 <calls> <tokens> "<label>" -- <cmd>`, status every
5 tool calls with calls_used / tokens_used_est / next_action, also during long runs; post `fact shots.best` as soon as
something is visible; no git, no D:). Read the predecessor's handoff .plan/handoff/POLISH7-4.json first. Spec:
docs/G7_REFERENCE.md **13.9c-21a** (the owner's new note: read every word), 13.9c-21, 13.9c-13, 13.9c-18.

## Build
1. Re-site the fuel bowser bay (Engineer7.BOWSER_BAY in sim/systems/engineer7.gd, the display park in
   presentation/view/fac_life7.gd, the markings in presentation/view/fac_atmo7.gd). The owner rejected the current
   spot: it must NOT be in front of (or in the approach / swing of) any door, garage door, gate, blast door, pad /
   helipad edge, lane mouth or another bay. Pick a lay-by off a lane, against a building side or the wall's inner face,
   near where refuelling happens (helipad / loading pad apron, garages), with a clear drive-out onto the lane, out of
   every fac_drive7 route (post fact eng7.bowser_bay again so APCMOV7-2 sees it). The whole truck sprite fits inside the
   marked bay (the last one was wider than the bay). Read every door / garage / gate / pad / lane from
   content/g7/defs_g7_facility.json `_g7_facility`; never hard-code around them.
2. A test that makes this a rule: extend tests/test_life7.gd: the bay rect plus a 1-tile approach margin in front of
   each door / garage door / gate / pad edge never overlaps the bay; the bay touches a lane on its drive-out side; the
   truck's drawn size fits inside the bay. test_eng7 / test_life7 / test_atmo7 stay green (never weaken a check).
3. Also: the dog kennel at the barracks front sits on the y16 lane: move it off the lane (same rule).
4. Windowed: re-run pt7_life7 and pt7_atmo7 (timeout 900), Read every PNG, post fact shots.best: the new fuel bay (zoom
   2 and 3, with the doors / garages around it in frame), the workshop / barracks, and the atmo7 night / alarm shots
   POLISH7-4 could not post.
Files you own: sim/systems/engineer7.gd (bay only), presentation/view/fac_life7.gd, presentation/view/fac_atmo7.gd,
tests/test_life7.gd, tests/test_atmo7.gd, tools/pt7_life7.gd, tools/pt7_atmo7.gd. WALL7-2 / EXO7 / APCMOV7-2 are live:
never edit their files. Anything else: change_request (exact lines).
