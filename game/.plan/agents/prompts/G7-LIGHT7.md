# G7-LIGHT7: lighting overhaul for the facility (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board, heartbeat via `bash .plan/hb.sh LIGHT7 <calls> <tokens> "<label>" -- <cmd>`, status every 5
tool calls with calls_used / tokens_used_est / next_action, also during long runs; post `fact shots.best` as soon as
something is visible; no git, no D:). Spec: docs/G7_REFERENCE.md **13.9c-24a** and **13.9c-24** (the owner's notes: read every word),
13.9c-18 (no transparency), 13.9c-13 (realism). Read .plan/handoff/POLISH7-5.json if present and POLISH7-5's board posts
(it removed the translucent glow boxes). Look at the latest shots in .plan/shots/POLISH7-5/atmo7b/.
## Build
1. Inventory every light the facility draws (presentation/view/fac_atmo7.gd, fac_life7.gd, fac_seq7.gd, tools/art/g7_atmo7.gd,
   the fac art) and for each: what it is mounted on, at what drawn height. Fix every floating light; give each a drawn
   fixture on a real surface.
2. Re-plan the lighting like a real hardened compound (13.9c-24a list): fixture types, placement, direction, colour
   temperature, light pools and falloff on ground and wall faces, day vs night vs alarm; opaque only.
3. Test (tests/test_atmo7.gd or a new tests/test_light7.gd): every light anchor lies on a drawn surface at its height; no
   translucent volume over a building footprint; light count bounded (fps). Display-only: hash on == off.
4. Windowed: pt7_atmo7 day / dusk / night / alarm at zoom 1 / 1.75 / 2.5; Read every PNG; post fact shots.best.
Files you own: presentation/view/fac_atmo7.gd (POLISH7-5 hands its fuel-bay markings to you as change_requests),
tools/art/g7_atmo7.gd, tests/test_atmo7.gd / test_light7.gd, tools/pt7_atmo7.gd; light-only parts of fac_life7.gd / fac_seq7.gd
via change_request to their current owner (POLISH7-5 owns fac_life7.gd until it hands off). Never edit WALL7-2 / FACB7-6 /
EXO7-2 / APCMOV7-3 files.
