# G7-WALL7-2: castle-style hardened wall-walk, futuristic (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board, heartbeat via `bash .plan/hb.sh WALL7-2 <calls> <tokens> "<label>" -- <cmd>`, status every
5 tool calls with calls_used / tokens_used_est / next_action, also during long runs; post `fact shots.best` as soon as
something is visible; no git, no D:). Spec: docs/G7_REFERENCE.md **13.9c-23** (the owner's note: read every word), 13.9c-4
(walkable walls), 13.9c-13 (realism, no gimmicks), 13.9c-18 (NOTHING see-through), 13.9c-10/-11 (Sentinels), and the
approved art bar (Look checkpoints).
What exists: WallWalk7 (sim/systems/wallwalk7.gd: own foot units walk the wall top, cover 2 on the wall), the facility
wall / tower art in tools/art/g7_fac7f.gd (+ g7_cn_facility.gd), the unit-on-wall offset / depth in
presentation/view/motion.gd (wall_top_offset, wall_top_depth) and entity_layer.gd (~line 587), the Sentinel display bits
(render_snap g7u "s7": 1 reloading, 2 sidearm) and motion.gd's s7 columns.

## Build
1. Wall art: every facility wall segment (and where it meets the towers and gatehouses) gets a real wall-walk on top:
   a deck wide enough for a man, behind an armoured parapet on the OUTER face: modern crenellation (armoured
   battlement panels with firing slots / gaps between them), inner-side guard rail or low lip, access stairs / ladders
   at the towers' free inner cells; futuristic Human engineering (composite armour panels, sensor strips, no medieval
   stone), at the approved detail level; autotiling stays seamless at corners, T-junctions and tower joins; opaque.
2. Units on the wall stand ON the deck (correct offset and depth: never floating, never under the wall sprite) and
   behind the parapet: the parapet's front edge is drawn over their legs / lower body so they read as standing behind
   it (an occluding parapet strip drawn after the unit, not transparency).
3. Sentinels (and any own infantry) on the wall: crouch behind the parapet when reloading, when suppressed / pinned and
   between aimed shots; rise to fire through a gap / over the top. Display-side from existing snapshot bits first
   (s7 reloading bit, pinned / suppression, fire timing); if the sim needs a new bit, change_request to ORCH with the
   exact lines (sentinels7.gd / render_snap.gd are not yours). Crouched = lower sprite pose, head / helmet just above
   the parapet line, never fully hidden in a way that makes them unselectable.
4. Tests (extend tests/test_wallwalk7.gd or a new tests/test_wallwalk7b.gd): wall-top offset / depth for a unit on
   every wall orientation; the crouch rule (reloading -> crouched pose on the wall, firing -> up); hash on == off for the
   display-only parts; no facility = no cost. Playtest: extend tools/pt7_wallwalk7.gd (registered "wallwalk7"): a stretch
   of wall with Sentinels manning it under attack, one reloading crouched, one firing up; walls at corners / tower joins;
   shots at zoom 1 / 1.75 / 2.5; Read every PNG; post fact shots.best with plain captions.
Files you own: tools/art/g7_fac7f.gd (wall / tower / parapet parts) + its assets, presentation/view/motion.gd
(wall_top_offset / wall_top_depth / the crouch pose only), presentation/view/entity_layer.gd (the unit-on-wall block and
a parapet occluder pass), tests/test_wallwalk7.gd / test_wallwalk7b.gd, tools/pt7_wallwalk7.gd. EXO7 / APCMOV7-2 /
POLISH7-5 are live: never edit their files. Anything else: change_request (exact lines).
