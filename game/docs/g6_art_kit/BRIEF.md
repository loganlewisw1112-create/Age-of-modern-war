# G6 proposal art: builder brief (read all of it before writing code)

## Why this exists
The owner of "RTS: Age of Modern War" (Godot 4.7, procedural pixel art) asked for mockups of ~93 *proposed*
new units, turrets, fortifications, drones, vehicles, aircraft, ships and buildings. A first pass with
hand-drawn canvas doodles was rejected: **"each mockup needs to read as an EXACT piece/asset from our game"**.
So every proposal is now built with the game's own art pipeline (`game/tools/art/*.gd`): same iso
projection, palettes, shading, detail helpers, outline, team-colour mask and sheet layout as shipped units.
Your job: write the drawers for one module of assets so they are indistinguishable in style from the
shipped sprites, and in faction identity match their faction.

## Paths
- GAME (read-only for you): `D:\CODING\PROJECTS - CURRENTLY WORKING ON\RTS Age of Modern Warfare\game`
- S (scratch, your workspace): `C:\Users\logan\AppData\Local\Temp\claude\D--CODING-PROJECTS---CURRENTLY-WORKING-ON-RTS-Age-of-Modern-Warfare\ca18736c-4923-415b-90da-26cc9ca0659e\scratchpad\g6`
  (bash form: `C:/Users/logan/AppData/Local/Temp/claude/D--CODING-PROJECTS---CURRENTLY-WORKING-ON-RTS-Age-of-Modern-Warfare/ca18736c-4923-415b-90da-26cc9ca0659e/scratchpad/g6`)
- Your assignment list: `S/assign/<module>.md`. Your module file: `S/gd/<module>.gd`.

## Hard rules
1. **Never write anything inside GAME** (no new files, no edits, no git commands that change state, no
   `--import`). Other agents are working in that tree right now. You only *read* GAME and *run* Godot headless
   against it through `S/run.sh`.
2. Write only: `S/gd/<module>.gd`, `S/notes/<module>.md`, `S/handoff/<agent>-<gen>.json`, and your board posts.
   Do not edit `S/gd/g6_lib.gd`, `S/gd/g6_gen.gd`, `S/run.sh`, `S/gd/ex.gd` (copy code from ex.gd freely).
   If you need a helper, put it in your own module.
3. Every art_id in your assignment must be built and listed in your module's `SHOW` dict exactly as written.
4. Use only `res://tools/art/*` libraries + Godot Image/Color APIs. No external images. Deterministic (hash
   helpers `P.hn/P.hi`, no randf).
5. Do not add a GENESIS offer or any owner-facing prose; your final message is a JSON report (below).

## How a module looks (see `S/gd/ex.gd`, a working example of each kind)
```
extends RefCounted
const P = preload("res://tools/art/pix.gd")          # Canvas, box(), proj(), box_shadow, sub(), hn/hi, mul/mix
const H = preload("g6_lib.gd")                        # bld(), TEAM tint, terrain (relative preload works)
const SHOW := {"<art_id>": {"row": 0, "frame": "fire", "ground": "dirt"}, ...}
static func build(out: Dictionary) -> void: ...       # register every asset
```
Three kinds of asset:
- **vehicle / gun / drone / aircraft / ship / walker / Machine bot** -> `SL.veh_sheet(out, id, {"fw","fh","pivot"}, draw, frames)`
  (`SL = res://tools/art/g5_units_lib.gd`; draw(cv, rot, f, wreck, o) is called for 8 facings (rot = k*PI/4) x frames,
  plus a wreck pass). Frames normally `["idle","move","fire"]`, add special columns where the role needs one
  (e.g. "deployed", "launch", "unload", "work"). Model the code on `tools/art/vehicles.gd` (mbt/ifv),
  `g5_units_veh_a.gd` (SPAAG, recon car, ambulance), `g5_units_veh_b.gd`, `faction_b_veh.gd`, `g4_units_*.gd`
  (APC, halftrack, rocket truck, scrap mech), `g3b_human_a/b.gd`, `g3b_machine.gd`, `faction_m_*.gd`.
  Draw order matters: far track/wheels -> lower hull -> near track -> upper hull -> barrel (behind turret when
  pointing away: `D.faces_cam(rot,1,0)`) -> turret -> barrel (in front) -> `cv.outline(OUTL)` -> muzzle fx.
- **squad (people)** -> `SL.squad_sheet(out, id, n<=4, draw(cv48x36, k, f, alive), frames)` with the G5 figure kit
  (`g5_units_fig.gd` styles/poses, `g5_units_sq.gd` std/layered/fig_at/prop_at). Model on `g5_units_inf_a.gd` /
  `g5_units_inf_b.gd`. More than 4 people (e.g. a 10-man wave) -> write your own sheet function in your module
  (copy squad_sheet with a bigger frame, place figures with SQ.fig_at + SQ.layered).
- **building / emplacement / fortification / static structure** -> `H.bld(out, id, size_tiles, headroom_px, draw(cv, o, f))`
  rendered for rotations f=0,1. Use the part-list renderer `K.render(cv, o, f, parts, 1.0, false, dress)`
  (`K = res://tools/art/g5_bld_lib.gd`; parts `[u, v, z, hu, hv, hz, colour, role]`, roles box/team/cyl/hex/tent/
  arch/glass/slab/mat/pole; `K.pal(fk, key)` faction palettes) and dressing helpers from `bdetail.gd` / `bdress.gd`.
  Model on `g5_bld_sea.gd` (coastal battery = turret on a base), `g5_bld_med.gd`, `g5_bld_air.gd`, `buildings.gd`,
  `g3b_bld*.gd`, `g4_fort_*.gd` (walls/towers), `faction_b_bld.gd`, `faction_m_bld.gd`.

**Aircraft / hovering drones**: draw them like the game draws `a_uav` / G5 drones (`g3b_lib.air`, `g5_units_drone.gd`):
the sheet holds the airframe only; in SHOW add `"alt": <px>, "shadow": [rx, ry]` and the plate draws the ground
shadow under it. Ships: vehicles on `"ground": "water"` (or "deep"); hull sits at z=0, add wake/bow-spray pixels.
Team colour: every asset needs `cv.team = true` areas (turret band, roof panel, hull band) like shipped art.

## Faction identity (match it exactly)
- **Human A**: olive `VH.HULL` (vehicles.gd), gunmetal, vision blocks `D.VISION`, tidy modern kit, team bands.
  Buildings: `K.pal("a", ...)` concrete/olive trim/grey roofs.
- **Human B**: khaki-brown `faction_b_veh.HULL`, rust, primer patches, rivets, streaks, soot, crude welded plate;
  buildings brick/rust (`K.pal("b", ...)`).
- **Machine**: graphite `faction_m_lib.GRAPH`, light panels, joints, **cyan seams / eyes / glows** (`L.seam`,
  `L.eye`, `L.hexp`, `L.team_panel`, `L.leg`), no crew, no fuel cans.
- **Shared** (s_*): draw in Human A / neutral military style (sand, concrete, steel).
- **4th faction Irregulars** (x_*): civilian pickups / captured kit, mismatched paint patches, sand/tan.

## Workflow (budget-aware)
1. Read your assignment, `S/gd/ex.gd`, and the 2-4 game drawers closest to your assets. Look at reference
   sprites with the Read tool (PNG): `GAME/assets/generated/units/*.png` (mbt, ifv, a_apc, a_guided_arty,
   a_old_tank, b_rebuilt_mbt, b_carrier, b_halftrack, b_rocket_truck, b_scrap_mech, b_radar_aa, m_walker,
   m_tracked, m_siege_crawler, m_artillery_node, m_swarm, m_drone, a_uav, rifleman...), `GAME/assets/art/g5_units/units/*.png`
   (a_spaag, a_recon_car, b_armored_car, a_hmg_team, b_grenadiers...), `GAME/assets/generated/buildings/*_built.png`
   (hq, guard_tower, b_bunker, m_sentry, m_sensor_relay...), forts `*_conn_5.png`, and G5 buildings
   `GAME/assets/art/g5_bld/buildings/*` (a_coastal_battery_built, a_hospital_built, b_hangar_light_lvl_0, ...).
   Don't read every reference; 3-6 well-chosen ones is enough.
2. Write drawers in batches (several assets per edit), then render: `bash S/run.sh <module>` (seconds).
   It prints `G6ART <module> ok n=.. show=.. order=..` or SCRIPT ERROR lines (fix them).
3. Check with Read: `S/art/check/_contact_<module>.png` (all your plates, 4 per row in SHOW order) and
   `S/art/check/<art_id>_facings.png` (every frame x 8 facings + wreck row, 2x) for anything doubtful.
   Look for: broken draw order at some facings, missing outline, flat/one-colour blobs, unreadable role,
   wrong faction look, asset far too small/large vs comparable shipped sprites.
4. Iterate until each plate reads as a shipped game asset of that faction and the role is obvious at a glance.
5. Write `S/notes/<module>.md`: one line per art_id (kind, frames, frame size, what to look at).

## Budget protocol (owner rule: no agent may exceed its cap)
- Your caps: MAX_TOKENS 750000, MAX_TOOL_CALLS 140. Projection = max(tokens_used_est + 90k, 303k + 2.3k x calls).
- Board: `AGENT_BOARD=S/board/board.jsonl`. Post status at least every 5 tool calls (chain it onto a render
  command to save calls):
  `AGENT_BOARD="$S/board/board.jsonl" node D:/CODING/SKILLS/tools/agent-board/post.mjs <agent> orch status '{"calls_used":N,"tokens_used_est":N,"next_action":"<exact next step>","done_so_far":"<ids done>"}'`
  then check for directives: `AGENT_BOARD="$S/board/board.jsonl" node D:/CODING/SKILLS/tools/agent-board/read.mjs --for <agent> --type directive`
- On a `budget.handoff_now` directive, or when your own projection reaches 70% of MAX_TOKENS (about 96 calls),
  stop new work: write `S/handoff/<agent>-<gen>.json` {module, ids_done, ids_todo, next_steps, known_issues},
  post `handoff` `{"file":"..."}`, and finish with your final JSON with `"status":"recycled"`.
  Your module file must always compile at the point you stop (render once to confirm).

## Final message (JSON only)
`{"agent":"<id>","module":"<module>","status":"done|recycled","ids_done":[...],"ids_missing":[...],"calls_used":N,"tokens_used_est":N,"notes":"<one paragraph: anything the orchestrator must know>"}`
