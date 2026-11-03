# G7-WALL7: walkable facility walls (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board, heartbeat via `bash .plan/hb.sh WALL7 <calls> <tokens> "<label>" -- <cmd>`, status every 5
tool calls with calls_used / tokens_used_est / next_action, no git, no D:). Spec: docs/G7_REFERENCE.md **13.9c-4** (the
owner's note: "walls of facility need to be walkable for your units"), 13.9c / 13.9c-2 / 13.9c-3 (facility layout), 6.2
(the facility). BASE7-3 (live) owns the facility layout (sim/systems/cn_facility.gd zone placement, defs_g7_facility.json,
sim/maps/last_protocol.gd, lp_setup.gd) and is adding 4 more large towers + outward sentry turrets on the walls: agree
on the board which wall cells / defs you key on; never edit its files (send it a `need` instead).

## What to build
- **Wall-walk:** the counter-nanite facility's walls (cn_wall / the facility wall ring, and its towers) can be walked on
  by the OWNER's foot units: they climb up from inside the compound (stairs / access at towers and at the inner side),
  path along the wall top, and stand on it. Enemies are still blocked by the wall; vehicles never go on it.
- Use the existing team-aware passability (sim/systems/movement.gd: w.nav.gates / _gate_open(team) lets own units
  through gates) or an equivalent per-team layer: own foot units treat facility wall cells as passable; everything else
  as solid. Pathfinding, separation and formations must handle it (no unit stuck in a wall when the wall is destroyed:
  a unit on a wall cell that is destroyed drops to the nearest free cell).
- **On the wall:** a soldier on the wall gets a height / cover bonus (use the existing elevation / cover rules:
  sim/systems/elevation.gd, Morale.cover_level) and sight bonus; is drawn ON TOP of the wall at the right depth
  (presentation/view/entity_layer.gd / motion: the wall-top offset), never hidden behind the wall sprite.
- Player orders: right-clicking a wall cell with infantry selected sends them up onto it; AI (the Last Protocol
  defence commander / garrison) may man the facility walls when the facility is attacked (optional if time is short;
  say so).
- Determinism and cost: deterministic, saved and hashed; a match without a facility costs nothing extra; measure the
  2k bench (.plan/sim_ab7.gd) before / after: no regression beyond noise.

## Files you own
sim/systems/movement.gd (passability / nav / gate parts only: NOT formation_slots or formations7.gd, which ORCH owns),
a new sim/systems/wallwalk7.gd if useful (ask ORCH via change_request for a SYSTEM_ORDER slot if it needs a tick),
presentation/view/entity_layer.gd (unit-on-wall depth / offset only), presentation/view/motion.gd (wall-top offset),
tests/test_wallwalk7.gd (new), tools/pt7_wallwalk7.gd (new; ORCH registers "wallwalk7").

## Tests
own infantry path onto and along the wall and stand on it; enemy infantry and own vehicles cannot; height/cover bonus
applied; destroyed wall drops the unit to a free cell; state hash twice-same; a match without a facility hashes as before
(compare with the bench hash before your change). Playtest pt7_wallwalk7 windowed: a squad ordered onto the wall,
walking along it, firing from it; shots at zoom 1 / 1.75 / 2.5; look at every shot yourself (Read the PNG).
