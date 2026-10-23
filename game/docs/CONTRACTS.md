# Integration contracts: G0+G1 slice

Status: the orchestrator's working contract for parallel builders. These are new engineering decisions, not user-approved design. Every numeric value in `content/` is a PROVISIONAL balance fixture (DEC-14).

Engine: **Godot 4.7.2**, GDScript, Compatibility renderer. Single-player offline.

## 0. Hard rules (every agent)

1. **Simulation (`sim/`) is authoritative and pure.** No Nodes, no rendering, no `randf()`/`randi()`/`randomize()`, no wall-clock time. Use `w.rng` (SimRng) for anything that affects gameplay. Presentation may use its own cosmetic RNG. **Trap (found 2026-10-22):** inside any class, a bare call like `randf()` resolves to Godot's GLOBAL non-deterministic function even if the class defines a method of that name. Always call RNG methods on an explicit object (`w.rng.randf()`), and never name your own methods `randf`/`randi`/`seed`.
1b. **Files must be UTF-8.** If you script-edit a file with Python, use `io.open(p, encoding='utf-8')` for both read and write. Prefer ASCII in code comments.
2. **Determinism.** Iterate `w.entities` in insertion order (Dictionary order). Never iterate a Dictionary built from non-deterministic sources. Same config + seed + command stream gives the same `state_hash()`.
3. **All gameplay changes go through commands.** The player and the AI both call `w.submit({...})`. Validation runs at the authoritative tick, and an invalid command never partly mutates state.
4. **All money and material movement goes through the ledger:** `w.spend()` (atomic) and `w.credit()`. Never write `faction.credits` or `faction.stock` directly.
5. **Serializable state only.** Entity dicts, faction dicts and `w.sys_state[...]` must contain only int/float/String/bool/Vector2/Vector2i/Array/Dictionary/PackedByteArray. Caches that are not authoritative go in `w.cache` or `w.nav` (never saved; rebuilt).
6. **System scripts have no `class_name`.** Reference them with `const X = preload("res://sim/systems/x.gd")`. Global classes: `SimWorld`, `SimRng`, `Content`, `Terrain` (+ `ArtCatalog` in presentation).
7. **Only edit files you own** (table below). `content/*.json`, `sim/world.gd`, `sim/map_gen.gd`, `tests/run_tests.gd` and `tests/test_base.gd` are orchestrator-owned. If you need a change there, put the exact request in your final report under `CHANGE_REQUESTS`. If your work is truly blocked, add a minimal clearly-commented helper in your own file instead.
8. **Do not `git commit`, stash or reset.** The orchestrator commits by path.
9. Build UI and scenes **in code**. Keep `.tscn` files minimal.
10. After adding a new `class_name` script or new assets, run the import step (§9) before running scripts.

## 1. File ownership

| Agent | Owns |
|---|---|
| ORCH | `sim/world.gd`, `sim/map_gen.gd`, `sim/sim_rng.gd`, `sim/content.gd`, `sim/terrain.gd`, `content/*`, `tests/run_tests.gd`, `tests/test_base.gd`, `tests/test_core.gd`, `docs/CONTRACTS.md`, `project.godot`, README/PROGRESS |
| A sim-econ | `sim/systems/economy.gd`, `construction.gd`, `production.gd`, `gather.gd`, `tests/test_econ.gd` |
| B sim-mil | `sim/systems/movement.gd`, `combat.gd`, `fog.gd`, `victory.gd`, `tests/test_mil.gd` |
| C art | `tools/gen_art.gd`, `assets/generated/**`, `presentation/art/art_catalog.gd`, `tests/test_art.gd` |
| D presentation-core | `presentation/match_view.gd`, `presentation/view/**` (terrain/entity/fog/fx renderers, camera, input, build ghost) |
| E hud-menus | `presentation/main.gd`, `presentation/main.tscn`, `presentation/menu/**`, `presentation/hud/**` |
| F infra | `sim/save_system.gd`, `tools/soak.gd`, `tools/bench.gd`, `tests/test_save.gd`, `tests/test_determinism.gd`, `perf/**` |
| G ai (wave 2) | `sim/ai/**`, `tests/test_ai.gd` |

## 2. World state (`sim/world.gd`)

- `w.tick` (int, 20 ticks/s, `SimWorld.DT` = 0.05 s). `w.step()` runs one tick in this order: apply due commands, then Economy, Construction, Production, Gather, Movement, Combat, Fog, Victory, then AI `think` for each AI side.
- `w.factions[fid]` = `{id, name, faction_def, color "#rrggbb", is_ai, stage, credits:int, stock:{salvage:int, ore:int}, power_prod:int, power_use:int, pop:int, pop_cap:int, alive:bool, spawn:Vector2i, journal:[...], stats:{trained, built, lost, killed}}`. fid 0 is the player and fid 1 is the AI. `SimWorld.NEUTRAL` = -1.
- `w.map` = `{id, name, w:96, h:96, terrain:PackedByteArray (Terrain codes, idx y*w+x), spawns:[Vector2i], resources:[{res, amount, cell}], bridge_cells, ford_cells, seed}`.
- Coordinates: world positions are `Vector2` in **tile units**. A cell is `Vector2i(floor(x), floor(y))`, and the centre of cell c is `Vector2(c) + Vector2(0.5, 0.5)`.

### Entity dicts (`w.entities[id]`)
Common: `id, kind ("unit"|"building"|"resource"|"wreck"), def, owner, pos:Vector2, hp:float, max_hp:float`.

- **unit**: `order:{type,...}`, `path:Array[Vector2]`, `path_i:int`, `target:int (-1)`, `cooldown:float`, `facing:float (radians, world space)`, `carry:{res:String, amt:int}`, `squad:int`, `moving:bool`, `firing:int` (ticks remaining of the muzzle-flash hint for presentation). Systems may add fields; add defaults lazily with `e.get("x", default)`.
  - Order types: `idle`; `move {target:Vector2}`; `attack_move {target}`; `attack {target_id}`; `hold`; `gather {resource_id, phase:"to_res"|"harvest"|"to_drop", drop_id}`; `build {building_id}`.
- **building**: `cell:Vector2i (top-left of the square footprint)`, `size:int`, `built:bool`, `progress:float 0..1`, `queue:[{item, progress 0..1, paid:{credits,salvage,ore}}]`, `rally:Vector2`, `target`, `cooldown`, `status:String` (blocked reason shown in the UI, e.g. `"LOW_POWER"`, `"SUPPLY_CAP"`, `""`).
- **resource**: `res ("salvage"|"ore")`, `amount:int`. Non-blocking. Engineers harvest while adjacent (within 1.2 tiles of `pos`).
- **wreck**: persistent, `from_owner`, `size`, `facing`, `tick`. Created by `w.destroy()` for vehicles (`leaves_wreck`) and buildings. Wrecks do not block movement in G1.

### World helpers (use these, don't re-implement them)
`spawn_unit(def, owner, pos)`, `spawn_building(def, owner, origin_cell, complete)` (this calls `Movement.on_footprint_changed(..., true)`), `destroy(id, cause, killer_owner)` (handles wrecks, footprint release and stats), `emit(type, data)`, `can_afford(fid, cost)`, `spend(fid, cost, cause)`, `credit(fid, amounts, cause)`, `units_of(fid)`, `buildings_of(fid, def="")`, `terrain_at(cell)`, `in_bounds(cell)`, `cell_of(pos)`, `is_enemy(a,b)`, `is_visible(fid,pos)`, `visible_enemies(fid)`, `preview_command(cmd)` (dry-run reason for the UI), `state_hash()`, `to_dict()`/`from_dict()`.

## 3. Commands

Envelope: `{"type": String, "issuer": fid, ...params}`. `submit()` assigns `id` and `tick` (default `w.tick + 1`). At apply time the world first runs common checks: the issuer is alive, `unit_ids` are filtered to the issuer's own existing units (rejected if none remain), and `building_id` must be the issuer's own. Then it calls `Handler.validate_command(w, cmd) -> String` (empty string = OK). On success it calls `Handler.apply_command(w, cmd)`, which **must not fail** after validation passed. Emits `CommandRejected {command_id, type, issuer, reason}` or `CommandApplied`.

| type | params | handler |
|---|---|---|
| move | unit_ids, target:Vector2 | Movement |
| attack_move | unit_ids, target | Movement |
| stop | unit_ids | Movement |
| hold | unit_ids | Movement |
| attack | unit_ids, target_id | Combat (must be a currently **visible** enemy for the issuer) |
| gather | unit_ids, target_id (resource) | Gather (only `can_gather` units) |
| build | unit_ids (engineers), def, origin:Vector2i | Construction |
| assist_build | unit_ids, target_id (own unfinished building) | Construction |
| cancel_building | building_id (unfinished) | Construction |
| queue_unit | building_id, item (production id) | Production |
| cancel_unit | building_id, index:int | Production |
| set_rally | building_id, target:Vector2 | Production |

Reasons must be human-readable sentences. The UI shows them directly.

## 4. Economy / Construction / Production / Gather (agent A)

- **Economy.tick**: recompute `power_prod` and `power_use` from **built** buildings (`power` field, positive or negative), and `pop` (sum of unit `pop`) and `pop_cap` (sum of built `pop_cap`, clamped to `rules.pop_cap_max`). The HQ credit stipend is `rules.hq_stipend_credits_per_second` per alive built HQ, credited once per second (every 20 ticks) via `w.credit(..., "hq_stipend")`. Power is a flow, not a stock.
- **Construction**: `placement_error(w, fid, def, origin) -> String` is a public static used by the build ghost and the AI. Rules: def is `buildable`, `requires` prereqs are built and owned, the footprint is in bounds, every cell is `Terrain.buildable`, there is no overlap with any building footprint or resource cell, the cells are explored by fid (fog), and the origin is within 20 tiles of one of fid's own buildings. `build` validates the placement plus `can_afford`, then **spends the full cost once at placement**, spawns an unfinished building (`complete=false`), and orders the listed engineers to build. An engineer adjacent to the footprint adds `build_power` per second, so progress += build_power * DT / build_time. HP rises with progress, and on completion it emits `ConstructionCompleted` and sets `stats.built`. `cancel_building`: refund 100% if progress < 0.05, else 50% rounded down, then destroy (no wreck needed; acceptable if the world spawns one). An unfinished building contributes no power and no pop.
- **Production**: `queue_unit` requires that the building is built, `item` is in the building's `produces`, `queue.size() < 5` and `can_afford`. It spends the full cost at queue time and stores `paid`. Only the head item progresses: `progress += DT / train_time` while not blocked. Blocked reasons (set `building.status`): `LOW_POWER` (building `requires_power` and `power_use > power_prod`), `SUPPLY_CAP` (`pop + item pop > pop_cap`). Blocked items do not progress and recover automatically. On completion, spawn each `spawns` unit near the building edge facing the rally, give them a shared `squad` id, order them to move to `rally`, and emit `ProductionCompleted {building_id, item, unit_ids}`. `cancel_unit` refunds `paid` exactly. `set_rally` sets `rally`. No duplication under cancel, save/load or repeated commands.
- **Gather**: an engineer cycle runs `to_res`, then `harvest` (`gather_rate` per second, integer accounting, up to `carry_capacity`, and the resource's `amount` decreases by exactly what was taken; it is destroyed at 0), then `to_drop` (nearest own built `deposit` building), then delivery via `w.credit(fid, {res: amt}, "delivery")`, then back to the same resource, or the nearest same-type resource if it is depleted. Movement uses `Movement.order_path(w, e, goal)` (below).
- Tests in `tests/test_econ.gd`: ECON-01 (no double spend, conservation: the journal sums equal the balance deltas, resource amount removed equals the amount delivered plus the amount carried), ECON-02 (power stall with reason, then recovery, no duplication), BUILD-01 (illegal placement reasons: overlap, water, unexplored, missing prereq), production queue/cancel refund, the gather cycle delivering salvage.

## 5. Movement / Combat / Fog / Victory (agent B)

- **Nav**: `rebuild_nav(w)` builds two grids in `w.nav` (`foot`, `vehicle`) from terrain passability (`Terrain.passable`) plus building footprints (solid for both). `on_footprint_changed` updates them incrementally and must no-op if nav is not built. Use `AStarGrid2D` (diagonals only when both orthogonals are free). Terrain speed comes from `Terrain.speed_mult`.
- Public helpers used by other systems/AI: `order_path(w, e, goal:Vector2) -> bool` (sets `e.path`, `e.path_i`, `e.moving`, and does NOT change `e.order`; false if unreachable; the goal snaps to the nearest reachable cell within 6 tiles), `nearest_free_cell(w, cell, move_class) -> Vector2i`, `is_passable(w, cell, move_class) -> bool`.
- `move`/`attack_move` with several units: assign formation slots around the target (grid offsets ~1.1 tiles for foot, 1.8 for vehicles, sorted deterministically), then path each unit. `stop` sets idle and clears the path. `hold`: the unit stays put and fires at enemies in range but never chases.
- **Movement.tick advances every unit with `e.moving == true` along `e.path`, whatever its order type** (gather/build/attack chase all use `order_path`). On reaching the final waypoint it sets `moving=false`, and only for `order.type == "move"` it also sets the order to idle. Other systems detect arrival by distance or by `moving == false`.
- Steering: follow path waypoints at `speed * speed_mult(terrain)`. Units must never enter impassable cells. Apply light separation between overlapping friendly units (spatial hash in `w.cache`), and never push a unit into an impassable cell. Update `e.facing`.
- **Combat**: each unit/tower with a `weapon` scans for the nearest visible enemy (unit or building) within weapon range, or within `sight` when idle/attack_move (then chases). `hold` units never chase. Explicit `attack` orders chase the target while it stays visible. If the target becomes non-visible, the unit moves to its last-known position, then goes idle. Fire when `cooldown <= 0`: roll `w.rng.chance(accuracy)`. Damage = `weapon.damage * Content.armor_mult(class, target_armor)`. Emit `ShotFired {shooter, target, weapon, hit:bool, from:Vector2, to:Vector2}` for every shot (presentation uses these for tracers) and set `e.firing = 3`. At hp <= 0, `w.destroy(id, "killed", shooter_owner)`. Buildings under construction can be shot. Units idle by default auto-engage (aggressive stance). Engineers only fire back when they themselves are attacked, or never; pick one and document it.
- **Fog**: per-faction `visible` and `explored` PackedByteArrays (1 = yes). Recompute visible every 4 ticks (and on tick 0) from built and unbuilt own units/buildings (circle of radius `sight`). Explored is sticky. `memory[fid][eid]` stores the last-seen `{def, kind, owner, pos, tick}` for enemy **buildings**, and drops entries whose cell is visible while the entity no longer exists. `is_visible(w, fid, pos)` and `visible_enemies(w, fid)` are the ONLY legal enemy queries for AI. Units whose cells are not visible to fid must not be returned.
- **Victory**: `hq_elimination`: a side with no HQ is `alive=false` (emit `SideEliminated`). When only one alive side remains, set `match_state = {ended:true, winner:fid, reason:"hq_elimination", end_tick}` and emit `MatchEnded`. `endless`: never ends, but sides are still eliminated.
- Tests in `tests/test_mil.gd`: MIL-01 (group move arrives, no unit inside impassable cells, dead units stay dead and are removed), the armor table (small arms barely hurt the MBT), AI-02 core (`visible_enemies` excludes units in unexplored or non-visible cells; an `attack` on a non-visible target is rejected), victory on HQ destruction, endless never ends.

## 6. AI (agent G, wave 2)
`AiController.new_state(w, fid) -> Dictionary` (serializable) and `think(w, fid)` (called every tick; it self-throttles with `rules.ai_difficulties[cfg.ai_difficulty].think_interval_ticks`). It only issues `w.submit()` commands and only reads its own entities, the public map (terrain, spawns, resources list) and `visible_enemies`/`memory`. Debug inspector fields in state: `objective, last_command, last_result, next_think_tick, known_contacts, log[]` (last 20 lines).

## 7. Presentation (agents C, D, E)

- Isometric projection (fixed, no rotation): `screen = Vector2((x - y) * 32, (x + y) * 16)` for world tile coords (TILE_W 64, TILE_H 32). The inverse is `MatchView.screen_to_world`. The cell (cx, cy) diamond has its top vertex at `world_to_screen(Vector2(cx, cy))`.
- **MatchView** (`presentation/match_view.gd`, Node2D, agent D): `var world: SimWorld`, `var player_fid := 0`, `var selection: Array[int]`, `signal selection_changed`, `signal world_events(events: Array)` (emitted after each sim step), `var speed := 1.0`, `var paused := false`, `func issue(cmd) -> Dictionary`, `func begin_build_placement(def_id)`, `func cancel_placement()`, `func center_camera_on(world_pos)`, `static world_to_screen / screen_to_world`, `func select_ids(ids: Array)`, `var control_groups: Dictionary`. The sim ticks at 20 Hz via an accumulator, and render positions are interpolated between ticks. The HUD (agent E) is a child CanvasLayer created by `main.gd`, which receives a reference to the MatchView.
- Input (agent D): left click / drag marquee select (own units first; buildings if no units), shift adds, double-click selects all of the same def on screen. Right click is a smart command (enemy → attack; resource + engineers → gather; own unfinished building + engineers → assist_build; else move). A then left click is attack-move. S is stop, H is hold, Ctrl+1–9 / 1–9 for control groups, WASD/arrows/edge pan, wheel zoom (0.5×–2×, pivot under cursor), Space jumps to the last alert, Esc cancels placement/deselects. Build ghost: footprint diamonds green/red using `Construction.placement_error`, cost tooltip, left click to place (`build` with the selected engineers), right click/Esc to cancel.
- **ArtCatalog** (`presentation/art/art_catalog.gd`, `class_name ArtCatalog`, agent C). It loads PNGs from `res://assets/generated/` with `Image.load_from_file(ProjectSettings.globalize_path(path))` and turns them into `ImageTexture` (no import pipeline dependency). API (static):
  - `load_all()`
  - `terrain_texture(code:int, variant:int) -> Texture2D` (64×32 diamond tile + any skirt). `terrain_variants(code) -> int`. `water_frame(t_seconds)` optional.
  - `decor(code:int, cell:Vector2i) -> Dictionary` `{texture, offset}` or `{}`: trees/rocks drawn as y-sorted sprites on forest/ridge cells (deterministic per cell).
  - `entity_sprite(e:Dictionary, team_color:Color, anim_time:float) -> Dictionary` `{texture, offset:Vector2, flip_h:bool}`. `offset` places the sprite so the ground contact point sits at `world_to_screen(e.pos)`. Handles units (8 facings from `e.facing`; walk frames while `e.moving`; firing frame while `e.firing > 0`), buildings (built vs under construction), resources and wrecks.
  - `effect_frames(name:String) -> Array[Texture2D]` for `muzzle`, `explosion_small`, `explosion_large`, `smoke`.
  - `icon(def_or_item:String) -> Texture2D` (32×32 HUD icons for production items and buildings).
  - `selection_ring(size_tiles:float) -> Texture2D`, plus `fog_tile(kind)` where kind is `"unexplored"` or `"explored"`.
  - Team colour: sprites use a team-mask (store a mask layer and tint, or pre-generate per colour on load). Faction colours come from `w.factions[fid].color`.
  - Missing art must never crash: return a visible magenta placeholder.
- **HUD** (agent E): top bar (credits, salvage, ore, power prod/use, pop/cap, Stage 8, game clock, speed/pause), minimap (terrain + fog + own/enemy-known dots + camera rectangle; click to jump), bottom panel (selection inspector: owner, HP, order, carried resource; multi-select unit counts by type; contextual buttons: engineers → build menu with costs and disabled reasons; HQ/barracks/motor pool → production buttons with costs, queue with progress, cancel, blocked reason), alerts feed (severity-coloured: under attack, production blocked, construction complete, unit trained, insufficient resources, command rejected reasons), pause menu (resume, save, load, quit to menu), end screen (victory/defeat, stats, continue watching / menu). Main menu: title; Skirmish setup (map River Crossing, seed field + randomize, starting credits, AI difficulty, victory HQ elimination/Endless, Stage selector showing all 13 IDs with only 8 enabled and others labelled "not in this slice", summary/validation line using `SimWorld.validate_config`), Load game, Quit.

## 8. Save / determinism / perf (agent F)
`sim/save_system.gd`: `save(w, path) -> String` (writes a JSON header line + `var_to_bytes(w.to_dict())` (var_to_str is LOSSY for doubles; never serialize sim state as text) to `path + ".tmp"`, verifies it parses back, keeps the previous file as `.bak`, then renames over it; returns "" or a reason) and `load(path) -> SimWorld` (null + push_error on missing/corrupt/unsupported schema). Saves go in `user://saves/slot_N.sav`. Tests: SAVE-01 (treasury, stock, hp, ownership, queues, orders, rng state, ids all equal after a round trip; continued runs hash-equal), corrupt file rejected, MATCH-02 (same config + seed + scripted command stream gives an equal hash at tick 3000 across 2 runs; save at 1500 then load and continue gives the same hash as an uninterrupted run). `tools/soak.gd` (AI vs AI headless, both sides AI, prints a periodic summary + final `SOAK RESULT winner=… ticks=…`). `tools/bench.gd` (spawns N mixed combat units per side in open terrain, measures avg/p95/max tick ms over 600 ticks for N total = 64, 128, 256, 512 and writes `perf/BENCH_<date>.md` with hardware info from `OS.get_processor_name()` / `OS.get_memory_info()`).

## 9. Running

```
GODOT=<path to Godot_v4.7.2-stable_win64_console.exe>
"$GODOT" --headless --path game --import
"$GODOT" --headless --path game -s tests/run_tests.gd              # all tests
"$GODOT" --headless --path game -s tests/run_tests.gd -- --only=test_econ
```
The test runner exits 0 only if everything passes. Parse errors show as `SCRIPT ERROR`/`Parse Error` lines; treat any of them as a failure even if the exit code is 0.
