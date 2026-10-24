# Integration contracts: G4a + G4e + G4b (binding)

This extends CONTRACTS.md, CONTRACTS_G2.md, CONTRACTS_G3a.md and CONTRACTS_G3b.md; all their hard rules still apply.
- Plan: `docs/PLAN_G4.md`. Goal and Done-when: `PROGRESS.md` (Active goal).
- Every number is PROVISIONAL unless marked OWNER.

## 0. Hard rules (every agent)
1. **Determinism.** Same seed + same commands = same `state_hash()`, threaded or not, native or fallback. No wall-clock time, no global RNG, no hash-order iteration in the sim. Iterate in ascending id order.
2. **One owner per file (§1).** Touch only the files you own. Cross-file needs go in CHANGE_REQUESTS to the owner on the board: `post.mjs <you> <owner-id> fact change_request '{"file":..,"edit":..}'`. The orchestrator (ORCH) routes requests for files whose owner has finished.
3. **Content goes ONLY into your own fragment files** under `content/g4/` (§2.1). Never edit the base `content/*.json`.
4. **Never write more than ~250 lines per tool call.**
   - Status every 5 calls or 4 minutes, with `calls_used`, `tokens_used_est` (≈60k + 5k per call) and `next_action`.
   - Wrap every godot/cargo run over ~60 s in `.plan/hb.sh`.
   - At 70% of the projection, write a handoff and stop.
5. **Keep the shared tree compiling after every write.** If you break compile for others, fix it immediately.
6. **Kill your own leftover godot processes** before you finish: filter by your log/output path.
7. **Benchmarks:** compare per-phase ratios; the orchestrator takes final numbers on a quiet machine.
8. **No git write commands.** No `--import`, unless your brief says so.
9. **Final report** in the AGENT_RULES format, with no GENESIS/postflight offer.

## 1. File ownership
| Agent | Role | Owns |
|---|---|---|
| **NAT** | Engine foundations: terrain semantics, movement classes, gate nav, native threads build | `sim/terrain.gd`, `sim/systems/movement.gd`, `sim/native_core.gd`, `native/**`, `bin/**`, `tools/build_native.sh`, `sim/systems/damage.gd` (LOS terrain set only), `tests/test_terrain_classes.gd`, `tests/test_native.gd` |
| **THREAD** | Sim off the main thread, render snapshot, HUD read safety, integration owner for presentation | `presentation/match_view.gd`, `presentation/view/**` except `terrain_layer.gd` and `g4b_*.gd`, `presentation/hud/**` except `g4b_*.gd`, new `sim/render_snap.gd`, `tests/test_thread.gd` |
| **MAPIO** | Map file format, file-map loading, triggers runtime, new victory presets, save at scale | `sim/map_io.gd`, `sim/systems/triggers.gd`, `sim/systems/victory.gd`, `sim/map_gen.gd` (export only), `tests/test_map_io.gd`, `tests/test_triggers.gd`, `tests/test_save_scale.gd` |
| **ED1** | Editor framework + land tools | `presentation/editor/**` (core, terrain, water, nature, resources, symmetry, undo, minimap), `presentation/main.gd` (scene switching only), `presentation/menu/main_menu.gd` (Map Editor button only), `tests/test_editor_core.gd` |
| **ED2** | Editor scenario tools + custom maps in skirmish | new `presentation/editor/ed2_*.gd` (units/buildings palette, players, victory/triggers/regions, validate, test-play), `presentation/menu/skirmish_setup.gd`, `tools/editor_playtest.gd`, `tests/test_editor_scenario.gd` |
| **FORT** | Walls, gates, towers sim | new `sim/systems/fortify.gd`, `sim/systems/construction.gd`, `content/g4/fort.json`, `tests/test_fort.gd` |
| **TRANS** | Transport system for every carrier | new `sim/systems/transport.gd`, `sim/systems/ops.gd` + `ops_missions.gd` (cargo-aware prune, "transport to point" mission), `sim/systems/economy.gd` (pop counts cargo), `content/g4/transport.json`, `tests/test_transport.gd` |
| **UNITS** | 8 new human units + their mechanics | new `sim/systems/g4b_mech.gd` (mines, charges, fire spread, concealment, set-up), `sim/systems/combat.gd`, `content/g4/units_g4b.json`, `tests/test_units_g4b.gd` |
| **UI4B** | Player UI for walls, gates, transports, new unit commands | new `presentation/hud/g4b_*.gd`, `presentation/view/g4b_*.gd`, `tools/ui_playtest.gd`. Wiring into hud.gd/match_view goes via CHANGE_REQUEST to THREAD. |
| **PERF10K** | 10,000 units in budget | `sim/systems/tiers.gd`, `sim/systems/sim_index.gd`, `sim/systems/territory.gd`, `sim/systems/fog.gd`, `sim/systems/supply.gd`, `sim/systems/morale.gd`, `tools/scale_bench.gd`, `tests/test_perf.gd`. Native-held positions in movement.gd/native go via NAT, or take ownership after NAT posts `done`. |
| **ART-T** | Terrain art + terrain rendering | new `tools/art/g4_terrain*.gd`, `presentation/view/terrain_layer.gd`, terrain entries in `assets/generated/**`, `tests/test_art_g4_terrain.gd` |
| **ART-F** | Walls/gates/towers art (3 factions) | new `tools/art/g4_fort*.gd`, fort entries in `assets/generated/**`, `tests/test_art_g4_fort.gd` |
| **ART-U** | 8 new units + editor tool icons | new `tools/art/g4_units*.gd`, `tools/art/g4_editor*.gd`, entries in `assets/generated/**`, `tests/test_art_g4_units.gd` |
| **AI5** | AI uses walls, gates, transports, new units, file maps | `sim/ai/**`, `tests/test_ai.gd`, `tools/soak.gd` |
| **ORCH** | Contracts, scaffold, world/content core, packaging | `sim/world.gd`, `sim/content.gd`, `tools/gen_art.gd`, base `content/*.json`, `tests/test_core.gd`, docs, `export_presets.cfg` |

**Art generator:** only one agent runs the full generator at a time. Post `fact art.gen_lock {"by":id}` first and `art.gen_unlock` after; check `read.mjs --topic art.gen_lock` before you start. The `g4_*` modules are already registered in `tools/gen_art.gd` as stubs, so don't edit gen_art.gd.

## 2. Scaffold (ORCH has already done these)
### 2.1 Content fragments
- `Content` merges every `content/g4/*.json` (sorted by filename) after the base files. A fragment has top-level keys named after tables (`units`, `buildings`, `production`, `weapons`, `research`) and their entries get merged into the table.
- An id that already exists is an ERROR. You add new ids; you never override existing ones.
- Optional `faction_roles: {faction_id: {role: id}}` adds new role keys to `factions.json` roles. It never overrides an existing role.
- `stage_roles` patches use `faction_stage_roles: {faction_id: {"7": {...}}}`, with the same rule.

### 2.2 Terrain constants (semantics: NAT)
`Terrain` codes:
- existing: GRASS 0, DIRT 1, ROAD 2, FOREST 3, WATER 4 (river), BRIDGE 5, FORD 6, RIDGE 7;
- new: BUILDING 8, SHALLOW 9, DEEP 10, BEACH 11, CLIFF 12, HILL 13.

`map.biome` (optional PackedByteArray, same size as terrain) is cosmetic only: 0 temperate, 1 desert, 2 snow, 3 wasteland.

### 2.3 Stub systems wired into world.gd
**SYSTEM_ORDER is now:** Economy, Construction, **Fortify**, Production, Progression, Gather, Repair, Ops, Orders, Movement, **Transport**, Combat, **G4bMech**, Morale, Supply, Bridges, Fog, **Triggers**, Victory.

**COMMANDS:**

| Command | Handler |
|---|---|
| `load`, `unload`, `unload_all` | Transport |
| `build_line`, `set_gate_lock` | Fortify |
| `lay_mine`, `plant_charge`, `deploy` (set-up/pack-up) | G4bMech |

- `cfg.map_file` (a res:// or user:// path to a `.rtsmap`): `new_match` calls `MapIO.load_map(w, cfg)` before sides are created (fills `w.map`, including spawns/spawn_sets from the file's player starts), skips start packages when `w.map.start_packages == false`, then calls `MapIO.place_entities(w, cfg)` after start packages.
- `SimWorld.SCHEMA_VERSION = 4`.

## 3. Movement classes and terrain semantics (NAT)
| Class | Passable | Notes |
|---|---|---|
| foot | GRASS, DIRT, ROAD, FOREST, BRIDGE, FORD, BEACH, HILL, SHALLOW (0.5x) | infantry |
| vehicle | GRASS, DIRT, ROAD, BRIDGE, FORD, BEACH, HILL (0.8x), SHALLOW (0.4x) | |
| amphibious | vehicle set + WATER + DEEP (0.6x on water) | G4d |
| naval_small | WATER, SHALLOW, DEEP | G4d |
| naval | DEEP, plus WATER cells that are part of a ≥3-wide channel | G4d |
| air / air_low | everything | `air` = existing drones; air_low = helicopters (G4c) |
| air_high | everything | jets (G4c) |

- **Never passable** for ground classes: RIDGE, CLIFF, BUILDING.
- **CLIFF, RIDGE and BUILDING block line of sight** (Damage.line_clear plus native RtsCombat.line_clear).
- **HILL:** +2 sight for ground units standing on it; foot units get a light cover bonus.
- **Buildable:** GRASS, DIRT, BEACH (only shore buildings may also need water cells, G4d), HILL.
- **Gates:** `Movement.set_gate(w, cells: Array[Vector2i], owner_team: int, locked: bool)`.
  - Nav keeps a per-team blocked overlay: a gate cell is solid for a team unless it is the owner team (or an ally) and the gate is unlocked.
  - Paths and `is_passable` take the team from the entity automatically.
  - Walls are ordinary solid building footprints.
- **Threads:** the native core is built with gdext `experimental-threads`. Each SimWorld owns its native objects; the main thread never calls into a world that is stepping.

## 4. Sim thread + render snapshot (THREAD)
- `world.step()` runs on a worker (WorkerThreadPool). The main thread never reads `w.entities`, `w.factions` or `w.map` arrays while a step is in flight.
- At the end of each step the sim builds `w.render_snap` (sim/render_snap.gd, built on the sim thread):
  - packed ids, pos, prev_pos, facing, def index, owner, hp fraction, flags bits;
  - buildings: state, progress, conn mask;
  - this tick's events;
  - per-faction top-bar numbers;
  - `detail` = full dict copies for the ids in `w.snap_request` (the selection plus hovered), which the main thread sets between steps.
- The renderer and HUD read only the latest snapshot and the immutable content.
- Commands are queued on the main thread and handed over between steps (they already apply at tick boundaries).
- `--sim-thread=off` runs the step on the main thread, reading the same snapshot path.
- `tests/test_thread.gd`: a recorded command stream gives the same hash threaded and unthreaded; no crash over 2,000 ticks at 2k units.

## 5. Map file `.rtsmap` (MAPIO) and triggers
- **The file is JSON:**
  `{format:"rtsmap", version:1, name, author, description, w, h, terrain_b64, biome_b64?, decor:[{id, cell:[x,y], size?}], resources:[{res, amount, cell}], bridges:[{cells:[[x,y]...], state}], hold_bridge?, players:[{slot, faction, team, color, stage, credits, stock:{...}, ai, difficulty, start:[x,y]}], entities:[{kind:"unit"|"building", def, owner_slot, cell or pos, facing, built, cargo?:[defs]}], victory:{...same shape as cfg.victory/rules}, regions:[{id, name, rect:[x,y,w,h]}], triggers:[...]}`.
- **API:**
  - `MapIO.save(path, map_dict, scenario_dict) -> String` (error or "");
  - `MapIO.read(path) -> {map, scenario}` or `{error}`;
  - `MapIO.load_map(w, cfg) -> String` and `MapIO.place_entities(w, cfg)` (the hooks above). Players come from `cfg.sides`; the skirmish/editor UI builds `cfg.sides` from the file's players unless the user overrides them;
  - `MapIO.validate(map, scenario) -> Array[{code, msg, cell?}]`, using the map validator plus player/start checks.
  - `MapGen` can export any built-in map: `MapGen.to_file(seed, id, path)`.
- **Triggers** (`sim/systems/triggers.gd`; state in `w.sys_state.triggers`, saved):
  - when types: `time_reached{t}`, `unit_in_region{region, owner_slot, count}`, `entity_destroyed{tag}`, `stage_reached{slot, stage}`, `units_below{slot, n}`;
  - then types: `message{text}`, `spawn{slot, def, count, region}`, `reveal{slot, region}`, `grant{slot, res, amount}`, `win{slot}`, `lose{slot}`, `ai_target{slot, region}`;
  - `once` (default true);
  - placed entities can carry a `tag`.
- **New victory presets** (victory.gd): `survive{seconds}`, `destroy_target{tag}`, `reach_stage{stage}`, `hold_point{region, seconds}`. All are combinable with the existing AND/OR.

## 6. Walls, gates, towers (FORT); IDs fixed
| Faction | Wall segment | Gate | Tower |
|---|---|---|---|
| human_a | `a_wall` | `a_gate` | `a_wall_tower` (MG) |
| human_b | `b_wall` | `b_gate` | `b_wall_tower` (flak, also hits drones) |
| machine | `m_barrier` (energy wall) | `m_field_gate` | `m_spire` |
- All size 1. Flags: `wall: true`, `gate: true`, `tower: true`. Stage_min 7 (towers 8).
- Walls, gates and towers use the new armor type `fortification`. FORT adds that column in its fragment's `armor_mult` block (for example `{"artillery": {"fortification": 1.6}, "at": {...}, "small_arms": {"fortification": 0.02}}`). New columns and new weapon classes (such as `demolition`) are allowed; overriding an existing pair is an error.
- **`build_line {issuer, def, from: [x,y], to: [x,y], unit_ids}`:**
  - snaps to 8 directions and makes one foundation per cell, skipping illegal cells (reason listed in the event);
  - charges per segment as each foundation starts (the usual construction ledger);
  - builders work the queue in order.
- **Connections:** `e.conn` = a 4-bit (N, E, S, W) neighbour mask of same-faction wall/gate/tower, recomputed on build complete or destroy. The renderer picks the art state `conn_<mask>`.
- **Gates:** `set_gate_lock {building_id, locked}`. Fortify calls `Movement.set_gate` whenever a gate is completed, destroyed or locked/unlocked.
- **Breach (AI/pathing):** when no path exists for a team, `Movement.order_path` returns false; units ordered to attack-move then target the nearest blocking wall segment (combat accepts wall targets).

## 7. Transports (TRANS); one system for land, air (G4c) and sea (G4d)
- **Carrier def fields:** `cargo_slots: int`, `cargo_accepts: ["foot"]` or `["foot","vehicle_light"]` etc.
- **Cargo def field:** `cargo_size` (default foot 1, light vehicle 4, heavy vehicle 8, by `cargo_class` = foot | vehicle_light | vehicle_heavy).
- **Loading:**
  - the unit's dict moves into `carrier.cargo` (an Array of entity dicts, ascending id) and is removed from `w.entities`;
  - event `UnitLoaded{id, carrier}`;
  - `w.cache.cargo_of[id] = carrier_id` (a cache, rebuilt on load);
  - loaded units still count in pop and keep their squad/officer group membership (Ops.prune ignores ids that are in cargo).
- **Unloading:** the dict is reinserted with the same id at free cells around the target (or the carrier); event `UnitUnloaded`.
- **Commands:**
  - `load {issuer, carrier, unit_ids}`: units walk to the carrier; a carrier ordered to a unit picks it up;
  - `unload {issuer, carrier, target, unit_ids?}`;
  - `unload_all {issuer, carrier}`.
- **Carrier destroyed (rules.json `transport` block, ORCH adds):** ground: cargo ejects at 50% hp; air: cargo dies; naval: cargo dies unless adjacent to land (G4d). Every outcome goes through the normal destroy/ledger path.
- **Save/load:** cargo is part of the carrier dict, so it saves for free. Test it.

## 8. New human units (UNITS); IDs fixed (D2: 4 + 4)
| id | Faction | Stage | Role | Mechanic |
|---|---|---|---|---|
| `a_apc` | human_a | 7 | transport | 10 slots foot; light MG (TRANS handles cargo) |
| `a_sniper` | human_a | 8 | sniper | long range vs infantry; `conceal_still`: hidden from enemies beyond 3 tiles while it hasn't moved or fired for 60 ticks |
| `a_mortar` | human_a | 7 | mortar | light indirect; `setup_ticks: 40`; must `deploy` before firing, packs up to move |
| `a_combat_engineer` | human_a | 8 | engineer | `lay_mine`, `plant_charge` (on walls/buildings/bridges), detects mines in 4 tiles, repairs walls |
| `b_flamer` | human_b | 7 | flamer | short range, ignores cover; hits on FOREST start fires (fire spreads to adjacent forest every 40 ticks with seeded chance, burns 300 ticks, damages units inside, then FOREST becomes DIRT) |
| `b_halftrack` | human_b | 7 | transport | 8 slots foot; HMG |
| `b_scrap_mech` | human_b | 8 | heavy | slow walker, front armor x1.5, crushes infantry it walks over (damage per tick) |
| `b_rocket_truck` | human_b | 8 | artillery | salvo of 6 rockets, splash, long reload |

- **Mines:** entity kind `mine` (owner, hidden from enemies unless detected within an engineer's or recon's 4 tiles). They trigger on enemy ground units, damage in radius 1, then are destroyed.
- **Charges:** kind `charge`; detonate after 100 ticks; big damage to buildings/walls/bridges.
- All are new defs in `content/g4/units_g4b.json` (+ production + weapons), with roles added via `faction_roles` (`sniper`, `mortar`, `engineer_combat`, `flamer`, `transport`).

## 9. Editor (ED1 / ED2)
- A separate scene, opened from the main menu ("Map Editor"). It reuses the terrain/entity drawing layers with a non-stepping SimWorld built from an editable map dict.
- The editor holds `{map, scenario}` exactly in the §5 shape. Save/load via MapIO. Test-play starts a match with `cfg.map_file` = a temp file, and returns to the editor on exit.
- **Tabs** (PLAN_G4 §3.1):
  - ED1: Map, Terrain, Water, Nature & objects, Resources, plus symmetry, undo/redo, minimap, overlays;
  - ED2: Units & buildings, Players, Victory & triggers, Regions, Validate, Test Play; plus custom maps in skirmish setup.
- **Brushes** are pure functions `(map, cells, params) -> changed_cells`, unit-tested, and fast on 256×256. Symmetry is applied by transforming cells before the brush.
- **Undo/redo:** a 200-step stack; one stroke is one step.
- Custom maps live in `user://maps/*.rtsmap`. Skirmish setup lists "Built-in" and "Custom".
