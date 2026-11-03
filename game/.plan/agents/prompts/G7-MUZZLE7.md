# G7-MUZZLE7: muzzle flashes from the barrels, everything that fires (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board, heartbeat via `bash .plan/hb.sh MUZZLE7 <calls> <tokens> "<label>" -- <cmd>`, status every 5
tool calls with calls_used / tokens_used_est / next_action, also during long runs; post `fact shots.best` as soon as
something is visible; no git, no D:). Spec: docs/G7_REFERENCE.md **13.9c-28** (the owner's note: read every word), 13.9c-13.
What exists: presentation/art/muzzle_g61.gd (anim61.muzzle per facing from the art manifests, measured by
tools/art/g61_anim_veh.gd), presentation/view/fx61_core.gd muzzle_offset (fallback when no data), fx_layer.gd
_fx61_muzzle; infantry / turret / building / aircraft paths may use other code (grep muzzle).
## Build
1. Audit: list every def that can fire (units, turrets incl. G7 wall turrets and tower weapons, buildings, aircraft,
   drones, CN suits, Sentinels, ships) and how its muzzle point is found today; flag every def that falls back to a
   centre / height guess. Post the audit on the board.
2. Fix: measured muzzle points per facing (and per turret facing, per pose: stand / crouch / prone / wall-top / garrison
   port; per barrel with alternation for multi-barrel weapons) for every firing def, from each sprite's own fire frame
   (extend the measuring tool; never hand-type hundreds of numbers); the flash, tracer start, barrel smoke, casings and
   backblast all start there. Keep it cheap (cached tables).
3. Tests (tests/test_muzzle7.gd): every firing def has muzzle data for all 8 facings; each point lies on an opaque barrel
   pixel near the sprite edge in the fire frame; multi-barrel alternation; display-only: hash on == off.
4. Windowed: a playtest (tools/pt7_muzzle7.gd, ORCH registers "muzzle7") of a firing line-up (infantry stand / crouch /
   prone, Sentinels on a wall, tanks, APCs, wall turrets, tower guns, helicopters, CN suits) at zoom 2.5 with frame-exact
   shots on the flash; Read every PNG; post fact shots.best.
Files you own: presentation/art/muzzle_g61.gd, presentation/view/fx61_core.gd (muzzle parts), presentation/view/fx_layer.gd
(muzzle parts), tools/art/g61_anim_veh.gd (+ a new measuring tool), the anim61.muzzle data in art manifests (data only:
regenerating sheets is NOT yours), tests/test_muzzle7.gd, tools/pt7_muzzle7.gd. Live agents' files: change_request.
