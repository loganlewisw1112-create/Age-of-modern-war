# G7-WTUR7: unmanned wall turrets for the counter-nanite facility (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board, heartbeat via `bash .plan/hb.sh WTUR7 <calls> <tokens> "<label>" -- <cmd>`, status every
5 tool calls with calls_used / tokens_used_est / next_action, no git, no D:). Spec: docs/G7_REFERENCE.md **13.9c-9** (the
owner's note; read every word), section 7 (the G7 turret line: sim/systems/turrets7.gd, content/g7 turret defs), 13.9c..
13.9c-8 (the facility). FACB7 (live) owns the facility layout (defs_g7_facility.json, cn_facility.gd, tools/art/g7_fac7f.gd,
entity_layer facility drawing): it removes the manned nests, encloses the APC wash and spawns your turret def at start
positions you agree with it on the board. WALL7's wall-walk (sim/systems/wallwalk7.gd, movement.gd wall cells) must keep
working: a wall turret never blocks the wall-top walk.

## Build
1. A new unmanned AI wall-turret def (content/g7/defs_g7_wallturret.json; Human A and Human B variants), modelled on the
   G7 turret line (Turrets7: acquisition, arcs, ammo/power as that line does): mounted on a wall face, it fires in the
   half-plane away from the wall it hangs on (no shooting through its own wall), is selectable (selection ring on the
   mount, info card), destroyable, and leaves a wreck mark on the wall.
2. Placement rule: it can be bought and placed ONLY on an outer or inner face of a facility wall segment (a wall piece
   of the owner's counter-nanite facility, cn_part wall), one per face cell, not on gates or towers. The placement ghost
   snaps to the nearest valid wall face and shows red elsewhere. Rebuy: available from the facility's build menu (or the
   construction card, wherever the facility's own items are bought: find it) with a cost and build time (PROVISIONAL).
   Sim validation in the construction / placement path (find where a building's placement is validated; change_request
   to ORCH with exact lines if the file is shared).
3. Art: your own generator tools/art/g7_wallturret.gd (mount plate on the wall face + turret head, 8 or 16 facings,
   firing frames, damaged, destroyed), at the approved detail level; it must read as attached to the wall from every
   angle (inner and outer faces; depth correct against the wall sprite).
4. Tests tests/test_wallturret7.gd: placement only on facility wall faces (rejected elsewhere, on gates, on towers, on
   another side's wall); fires outward only; selectable and destroyable; rebuy and place works; hash twice-same; a match
   without a facility costs nothing. Playtest tools/pt7_wallturret7.gd (ORCH registered "wallturret7"): place one on an
   outer face and one on an inner face, enemies attack, one is destroyed, rebuy and re-place; shots at zoom 1 / 1.75 /
   2.5; LOOK at each (Read the PNG); list the best in your report (the owner wants them).
Files you own: content/g7/defs_g7_wallturret.json, tools/art/g7_wallturret.gd + its art, tests/test_wallturret7.gd,
tools/pt7_wallturret7.gd, presentation/art/art_catalog.gd (register only), a new sim/systems/wallturret7.gd if needed
(change_request to ORCH for a SYSTEM_ORDER slot). Anything else: change_request.
