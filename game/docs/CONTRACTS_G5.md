# CONTRACTS_G5: binding engineering contract for G5 "Full Spectrum"

Plan: `docs/PLAN_G5.md` (owner-approved rev 4, 2026-10-24, defaults D9-D20). Where this file and the plan disagree, **this file wins** for IDs, ownership and APIs. Send changes to ORCH as a board `change_request`.

---
## §0 Hard rules (every agent)
1. **Ownership is exclusive** (§1). Touching another owner's file needs a `change_request` on the board. ORCH may grant a narrow edit.
2. **Determinism:** same seed + commands = same `state_hash` with the sim thread on or off, and with native on or off.
   - Iterate in ascending id order, with no `Dictionary` key-order assumptions.
   - All randomness comes from `w.rng` in a fixed draw order.
   - New state lives in `w.sys_state.<system>` or on entity dicts, is saved, and is included in the hash. Runtime caches go in `w.cache` and are never saved.
3. **Results must not change for existing content** unless a contract section says so. Every G4 hash test stays green.
   - New behaviour that changes results for existing units goes behind a `rules.json` flag that defaults to **off**.
   - The exceptions: wounded state (D16, human infantry only) and auto-resupply (only when a player or the AI turns it on).
4. **Content:** only your own `content/g5/<file>.json`. New IDs only; never redefine an existing id. Fragment rules are in `sim/content.gd` (§2.1).
5. **Keep the tree compiling after every write:**
   - stubs first, chunks of ≤250 lines;
   - after each write, `godot --headless --path . --quit-after 60 2>&1 | grep -A1 "SCRIPT ERROR"` must print nothing;
   - if you break the build, append `<ID> BLOCK tree.broken <file>` to the bus and fix it at once.
6. **Thread rule:** presentation code reads only `w.render_snap` while `sim_busy()` is true, never `w.entities` during a step.
7. **Tests:**
   - your acceptance skeleton is in `tests/pending_g5/`: move it to `tests/` when you start and make it pass;
   - never weaken an assertion; never delete another agent's test;
   - the full suite runs once at the end inside `.plan/hb.sh`.
8. **Numbers are PROVISIONAL balance fixtures**, not approved values. Keep them in content JSON, not code.

---
## §1 Ownership

| ID | Owns (exclusive) |
|---|---|
| ORCH | `sim/world.gd` (except the HOT block), `sim/content.gd`, `content/*.json` (base), `sim/map_gen.gd`, `docs/**`, `.plan/**`, `tests/pending_g5/**` (creates only), `presentation/ui5/README.md` |
| CORE10K | `sim/hot_state.gd`; the `# >>> G5 HOT` … `# <<< G5 HOT` block in `sim/world.gd`; `sim/systems/{movement,combat,damage,supply,morale,fog,tiers,territory,sim_index,unit_subsets}.gd`; `sim/native_core.gd`; `native/**`; `bin/**`; `tools/build_native.sh`; `tools/scale_bench.gd`; `tests/test_perf*.gd`; `tests/test_hot_state.gd`; `tests/test_native.gd` |
| AIRSYS | `sim/systems/air.gd`, `sim/systems/airfield.gd`, `sim/systems/transport.gd`, `content/g5/air.json`, `tests/test_air.gd`, `tests/test_airfield.gd`, `tests/test_air_transport.gd`, `tests/test_transport.gd` |
| NAVAL | `sim/systems/naval.gd`, `sim/maps/coastal_front.gd`, `content/g5/naval.json`, `tests/test_naval.gd`, `tests/test_coastal_front.gd` |
| UNITS5 | `sim/systems/g5_mech.gd`, `sim/systems/g4b_mech.gd`, `content/g5/units_g5.json`, `tests/test_units_g5.gd`, `tests/test_drone_team.gd`, `tests/test_units_g4b.gd` |
| SUPPORT | `sim/systems/support.gd`, `sim/systems/medical.gd`, `content/g5/support.json`, `tests/test_support.gd`, `tests/test_medical.gd` |
| UI5a | `presentation/ui5/kit/**`, `presentation/hud/{hud,hud_theme,scaled_layer,minimap,objectives,g2_alerts,g4b_alerts,g3_score,g3b_data,g3b_stage}.gd`, `presentation/menu/**` except `settings.gd`, `presentation/match_view.gd`, `tools/ui_fit_test.gd`, `tests/test_ui_fit.gd` |
| UI5b | `presentation/ui5/panels/**`, `presentation/hud/{g2_commands,g4b_commands,g3_faction,g2_inspector}.gd`, `presentation/view/{g4b_input,g4b_overlay}.gd`, `presentation/menu/settings.gd`, `tests/test_ui_panels.gd` |
| FONT | `tools/font/**`, `assets/fonts/**`, `tests/test_font.gd` |
| ART-U5 | `tools/art/g5_units*.gd`, `assets/art/g5_units/**`, `tests/test_art_g5_units.gd` |
| ART-BLD | `tools/art/g5_bld*.gd`, `assets/art/g5_bld/**`, `tests/test_art_g5_bld.gd` |
| ART-AIR | `tools/art/g5_air*.gd`, `assets/art/g5_air/**`, `tests/test_art_g5_air.gd` |
| ART-NAV | `tools/art/g5_naval*.gd`, `assets/art/g5_naval/**`, `tests/test_art_g5_naval.gd` |
| VIEW5 | `sim/render_snap.gd`, `presentation/view/{entity_layer,batch_art,batch_atlas,fx_layer,terrain_layer,lod_icons,sim_runner}.gd`, `presentation/art/**`, `tests/test_view5.gd` |
| AI6 | `sim/ai/**` except `ai_air.gd` and `ai_naval.gd`; `tools/soak.gd`; `tests/test_ai.gd`, `tests/test_ai_g5.gd` |
| AI6-AN | `sim/ai/ai_air.gd`, `sim/ai/ai_naval.gd`, `tests/test_ai_air_naval.gd` |
| PT5 | `tools/ui_playtest.gd`, `tools/editor_playtest.gd`, `.plan/shots/PT5/**` |
| ED5 | `presentation/editor/**`, `presentation/main.gd`, `sim/systems/triggers.gd`, `sim/map_io.gd`, `content/scenarios/**`, `tests/test_editor_*.gd`, `tests/test_triggers.gd`, `tests/test_map_io.gd`, `tests/test_tutorial.gd`, `tests/test_editor_g5.gd` |

Unlisted G4 files (e.g. `sim/systems/{economy,construction,production,progression*,gather,repair,ops*,orders,bridges,fortify,victory}.gd`) are owned by ORCH. Request changes through a CR.

---
## §2 Scaffold (ORCH, in place before any agent starts)
1. `sim/content.gd` merges `content/g4/*.json` and then `content/g5/*.json`, each sorted by name. The fragment rules are unchanged (new IDs only; `facility` links production).
2. **Empty system stubs**, registered in `SYSTEM_ORDER` and compiling. Each has `static func tick(w)`, `validate_command`, `apply_command`.
   - **Order:** Economy, Construction, Fortify, **Airfield**, Production, Progression, Gather, Repair, Ops, Orders, Movement, **Air**, **Naval**, Transport, Combat, G4bMech, **G5Mech**, **Medical**, **Support**, Morale, Supply, Bridges, Fog, Triggers, Victory.
   - The stubs do nothing, so every G4 hash stays equal.
3. `COMMANDS` entries point at the owners' stubs (§4). A stub's `validate_command` returns `"not_implemented"` until the owner fills it in.
4. `sim/hot_state.gd` is a stub class. `world.gd` contains the HOT block markers.
5. `sim/ai/ai_air.gd` and `ai_naval.gd` expose `static func manage(w, fid, st) -> void` (no-op). `ai_controller.think` calls both after G4b.
6. `content/g5/{air,naval,units_g5,support}.json` each hold only `_meta`.
7. Placeholder art: units with no art draw as a team-tinted silhouette by class (infantry dot, vehicle box, air delta, naval hull, building block) instead of a magenta square (`ArtCatalog.placeholder_for`).
8. `tests/pending_g5/test_*.gd` holds failing acceptance skeletons per agent (§11). These files are **not** discovered by the runner until moved to `tests/`.
9. `presentation/ui5/kit/` and `presentation/ui5/panels/` exist (README only).

---
## §3 IDs (fixed; art, AI, UI and tests key on these)

### §3.1 New ground units (UNITS5, `units_g5.json`)

| Human A | Human B | Machine |
|---|---|---|
| `a_medic_team` (2) | `b_grenadiers` (4) | `m_maint_swarm` |
| `a_hmg_team` (3) | `b_shock_troops` (4) | |
| `a_spaag` | `b_at_rocket_team` (3) | |
| `a_recon_car` | `b_armored_car` | |
| `a_special_forces` (4) | `b_field_ambulance` | |
| `a_drone_team` (3) | `b_drone_team` (3) | |
| `a_airfield_engineers` (4) | `b_airfield_engineers` (4) | |
| `a_ambulance` | | |

- `(n)` = squad size: one entity with `squad_size n`, and `squad_alive` tracking losses.
- Launched drones (short-lived `air_low` entities):
  - `a_drone_strike`, `a_drone_frag`, `a_drone_recon`, `a_drone_emp`;
  - `b_drone_strike`, `b_drone_frag`, `b_drone_recon`, `b_drone_emp`.

### §3.2 Air units (AIRSYS, `air.json`)

| Faction | Unit ids |
|---|---|
| Human A | `a_attack_heli`, `a_transport_gunship`, `a_strike_jet`, `a_interceptor`, `a_vtol_dropship` |
| Human B | `b_gunship`, `b_heavy_lift`, `b_bomber`, `b_vtol_dropship` |
| Machine | `m_drone_carrier`, `m_lifter_drone`, `m_interceptor_swarm`, `m_micro_drone` (spawned by the carrier) |

### §3.3 Naval units (NAVAL, `naval.json`)

| Faction | Unit ids |
|---|---|
| Human A | `a_patrol_boat`, `a_landing_craft`, `a_destroyer`, `a_aa_frigate` |
| Human B | `b_river_gunboat`, `b_barge_carrier`, `b_monitor` |
| Machine | `m_hydro_skiff`, `m_amphib_crawler` |

### §3.4 Buildings

| Owner | Human A | Human B | Machine |
|---|---|---|---|
| AIRSYS | `a_airfield`, `a_airstrip`, `a_hangar_light`, `a_hangar_heavy`, `a_helipad`, `a_air_tower`, `a_forward_strip`, `a_forward_helipad` | `b_aerodrome`, `b_airstrip`, `b_hangar_light`, `b_hangar_heavy`, `b_helipad`, `b_air_tower`, `b_forward_strip`, `b_forward_helipad` | `m_launch_rail`, `m_drone_bay` |
| NAVAL | `a_shipyard`, `a_supply_pier`, `a_coastal_battery` | `b_shipyard`, `b_supply_pier`, `b_coastal_battery` | `m_shipyard`, `m_supply_pier`, `m_coastal_battery` |
| SUPPORT | `a_hospital`, `a_field_hospital` | `b_hospital`, `b_field_hospital` | |

### §3.5 Upgrades (AIRSYS; stored on the building entity)
- `airfield.extra_strips`: 0..3.
- `hangar.level`: 0..3. L1 rearm/refuel −40%; L2 repairs while parked; L3 armored roof.
- `hangar.class`: `light` | `heavy`. Light → heavy is an upgrade.
- Machine `m_launch_rail` uses `extra_rails` 0..3. `m_drone_bay` levels match hangars.

### §3.6 Movement and target classes
- Existing G4 classes: `foot`, `vehicle`, `amphibious`, `naval_small`, `naval`, `air_low` (alias `air`), `air_high`.
- Weapon flags:
  - `anti_air_low`: can hit air_low;
  - `anti_air_high`: can hit air_high;
  - `anti_drone`: bonus vs launched drones.
- AIRSYS defines the targeting rule `Air.can_target(weapon, target)`; CORE10K's combat calls it (CR wiring by CORE10K).

---
## §4 Commands (registered in `COMMANDS` by ORCH → owner stub)

| Command | Owner script | Fields |
|---|---|---|
| `build_hangar` | Airfield | `{issuer, building_id (airfield), class: "light"\|"heavy"}` |
| `upgrade_hangar` | Airfield | `{issuer, building_id (hangar), kind: "level"\|"to_heavy"}` |
| `upgrade_airfield` | Airfield | `{issuer, building_id, kind: "extra_strip"}` |
| `assign_engineers` | Airfield | `{issuer, unit_ids, building_id}` (airfield, hangar, helipad or forward strip) |
| `sortie` | Air | `{issuer, unit_ids, target_id?, area?: [x,y,r]}` (air_high) |
| `rebase` | Air | `{issuer, unit_ids, building_id}` |
| `land_at` | Air | `{issuer, unit_ids, cell: [x,y]}` (air_low lands on open ground; jets land only at a field) |
| `take_off` | Air | `{issuer, unit_ids}` |
| `bombard` | Naval | `{issuer, unit_ids, cell: [x,y]}` |
| `launch_drone` | G5Mech | `{issuer, unit_id, drone: "strike"\|"frag"\|"recon"\|"emp", target_id?, cell?}` |
| `tactical` | G5Mech | `{issuer, unit_id, ability: "infiltrate"\|"takedown"\|"breach"\|"stack_up"\|"armored_attack", target_id?, cell?}` |
| `set_auto_resupply` | Support | `{issuer, unit_id, mode: "off"\|"station"\|"roam", center?: [x,y], radius?, ammo_pct?, fuel_pct?}` |
| `set_auto_evac` | Medical | `{issuer, unit_id, on: bool, center?: [x,y], radius?}` |

- Existing `load`/`unload`/`unload_all` (Transport) gain air/naval carriers. AIRSYS adds `cargo_size`, `sling` and mixed cargo for the VTOL.
- Production gating: `Production` calls `Airfield.can_produce(w, fid, def_id) -> String` (`""` = ok, else a reason such as `"no_free_hangar"`, `"no_free_pad"`). ORCH wires this call into production.gd; AIRSYS implements it.

---
## §5 Cross-agent APIs (signatures fixed; post the fact when callable)

| Fact | Owner | API |
|---|---|---|
| `core.hot_api_ready` | CORE10K | `HotState.set_pos(w,id,v2)`, `set_target(w,id,tid)`, `set_moving(w,id,b)`, `set_order(w,id,kind)`, `set_hp(w,id,hp)`, `get_*`; `HotState.flush(w)` before hash/save/snapshot |
| `core.zero_hp_hook_ready` | CORE10K | `Damage` calls `Medical.on_zero_hp(w, e) -> bool` before destroying a unit (`true` = keep it alive as Wounded) |
| `core.breach_wired` | CORE10K | `Movement` calls `Fortify.on_attack_move_blocked(w, e, goal)` when an attack-move path fails |
| `air.api_ready` | AIRSYS | `Airfield.can_produce`, `Airfield.free_slots(w, bid)`, `Airfield.repair_crater(w, eng, bid)`, `Airfield.service_point_at(w, fid, pos)`, `Air.can_target`, `Air.is_landed(e)`, `Air.landing_ok(w, cell, def)` |
| `air.gating_ready` | AIRSYS | production returns `no_free_hangar` / `no_free_pad` |
| `naval.api_ready` | NAVAL | `Naval.beach_ok(w, cell)`, `Naval.pier_at(w, fid, pos)`, bombard command |
| `map.coastal_front_ready` | NAVAL | `sim/maps/coastal_front.gd` generate + validate (ORCH registers `coastal_front_m`) |
| `units5.api_ready` | UNITS5 | `launch_drone`, `tactical`; `G5Mech.drone_charges(e)`, `G5Mech.mode(e)` (`"drone"`\|`"tactical"`), `G5Mech.restock_drones(w, e)` |
| `support.api_ready` | SUPPORT | `set_auto_resupply`; `Support.needs_supply(w, e) -> bool` |
| `medical.api_ready` | SUPPORT | `set_auto_evac`; `Medical.on_zero_hp`; `Medical.is_wounded(e)`; `Medical.carrying(e) -> Array` |
| `ui5.kit_ready` | UI5a | `UiKit.panel()`, `UiKit.button(text, hotkey, tooltip)`, `UiKit.icon_button`, theme constants, `UiKit.fit_register(control)` |
| `font.specimen_ready` / `font.final` | FONT | `assets/fonts/rts_mil_{bold,regular}.ttf` + `specimen.png` |
| `art.<group>_ready` | ART-* | manifest entries for every ID in the group |

Until a fact is posted, callers use the stub (which returns a safe default). Calls must never crash on the stub.

---
## §6 State keys (saved, hashed)
- `w.sys_state.air`: `{flights: {id: {phase, field, strip, t}}, holding: {field_id: [ids]}, ver}`.
- `w.sys_state.airfield`: `{fields: {bid: {strips: [{open, crater_t, busy_id}], hangars: [{bid, class, level, occupant}], pads, engineers: [ids]}}, ver}`.
- `w.sys_state.naval`: `{wrecks: [[x,y,t]], ver}`.
- `w.sys_state.g5mech`: `{drones: {id: {owner_squad, type, t}}, ver}`.
- `w.sys_state.support`: `{trucks: {id: {mode, center, radius, thr, queue}}, ver}`.
- `w.sys_state.medical`: `{wounded: {id: t_left}, carriers: {id: [ids]}, ver}`.
- `w.map.burnt`: a PackedByteArray (UNITS5), saved with the map state.
- Entity fields added by owners carry a G5 comment in the owner's file header (copy the G4 header style).

---
## §7 Air rules (AIRSYS; provisional numbers in `air.json`)
- **Airfield:**
  - footprint 4×26 strip + apron; rotation 0..3 (`facing` on the build command, rotating the footprint);
  - base strips 1, max +3; hangar slots 4 + 2 per extra strip;
  - requires Stage 8 + an `*_air_tower` within 20 tiles for air_high production.
- **Airstrip:** 3×14, 2 light slots, no extra strips. Offered when a full airfield can't fit.
- **Strips:** one movement at a time. Takeoff = taxi (lane) → roll (strip axis) → airborne. Landing = approach on the axis → touchdown → taxi → hangar.
- **Holding:** arrivals circle the field; lowest fuel lands first, ties by id.
- **Craters:**
  - a hit with `cratering` closes a strip until repaired;
  - `Airfield.repair_crater` by engineers takes N seconds;
  - all strips closed or the field destroyed → divert to the nearest friendly field; none → crash when fuel runs out.
- **A destroyed hangar** destroys any aircraft parked in it (unless L3 roof: then the aircraft takes 50% damage).
- **Helicopters (D11):**
  - can `land_at` any open, flat, dry cell without trees or buildings;
  - each has a `home_pad` (buying needs a free pad);
  - rearm/refuel/repair at any friendly pad, forward strip or airfield. With engineers assigned it is automatic, and 50% faster.
- **Landing zones (owner note, 2026-10-24):** VTOLs, gunships and helicopters land ANYWHERE with open ground big enough for that aircraft, OR at their pads/hangars/airfield. `Air.landing_ok` checks a clear square of `lz_size` (helicopters/lifters 2×2, heavy-lift and VTOLs 3×3): in bounds, no water/deep/cliff/forest/building, no landed aircraft. A too-small spot is rejected with "Not enough open ground to land".
- **Jets:** sortie → strike → return → land → rearm (time by hangar level). They can't hover.
- **VTOL Dropship:** air_low, Heavy hangar, `cargo: {vehicle: 2, foot: 8}`, Stage 9; heavy AA missiles + cannon; lands on any `land_at` cell or at a field.
- **Interceptors and VTOLs** auto-engage enemy aircraft in range.

---
## §8 Naval rules (NAVAL)
- Ships use `naval` (channel ≥3) or `naval_small` (rivers). Amphibious units cross water↔land.
- Shipyard footprint: at least 2 water cells + at least 2 beach/land cells. Units spawn on the water side.
- Landing craft / barge unload only onto `BEACH`/`SHALLOW`-adjacent land.
- Bombard: indirect fire at a land cell within `bombard_range`.
- Wrecks: a ship at 0 HP sinks over N ticks. The cell becomes `SHALLOW` (an obstruction for `naval`, passable for `naval_small`), and the nav for both classes is updated through the Movement API.
- Supply Pier: ships within 3 tiles restock from faction stock.
- **Coastal Front** (`coastal_front_m`, 192×192): mainland coast, 2 islands, beaches, estuary + fords, 2–4 spawns validated (land or sea reachable), seeds 1–5.

---
## §9 Drone Team and new units (UNITS5)
- **Squad entities:** one entity with `squad_size`, `squad_alive`; selection and orders target the entity. Losses reduce `squad_alive` and firepower; at 0 the entity dies.
- **Drone Team:**
  - `drone_charges` 4;
  - `launch_drone` spawns a drone entity (air_low, short life, speed and payload by type, shootable by `anti_air_low`/`anti_drone`, jammed by EW within range);
  - strike = top-attack anti-armor; frag = small area; recon = reveal + mark for N s; emp = disable machines/turrets and jam drones for N s;
  - at 0 charges `mode = "tactical"`, which unlocks the `tactical` abilities;
  - restock at a supply source restores the charges and sets `mode = "drone"`.
- **Human B** drones: cheaper, ±spread on impact, rigged look.
- **Others:**
  - HMG deploy/pack (G4 `setup_ticks` pattern);
  - Special Forces: concealment (G4 sniper pattern) + charges (G4 engineer pattern) + `airdrop_ok`;
  - Grenadier/Shock: bonus vs wall/tower;
  - SPAAG: `anti_air_low` + `anti_air_high` + `anti_drone`;
  - ambulances: `wounded_slots` (A 6, B 4); medic team: 2 + heal aura.
- `w.map.burnt` holds burnt cells (from G4b fire), saved and hashed; the render snapshot reads it.

---
## §10 Support and medical (SUPPORT)
- **Auto resupply:**
  - modes `station` | `roam`; default thresholds ammo < 40%, fuel < 30%, `drone_charges == 0`;
  - a unit in combat leaves only at 0 ammo;
  - units resume their saved order (`e.resume_order`);
  - a truck refills at the nearest depot/refinery when its stock is empty;
  - trucks claim units (no doubling up).
  - Works for ships at a pier and helicopters landed nearby.
- **Wounded:**
  - human infantry (`armor == "infantry"`, faction human_a/human_b) at 0 HP → `wounded = true`, hp 1, immobile, no fire, untargetable by direct fire (splash can still kill), for `bleed_out` 60 s;
  - not evacuated in time → destroyed;
  - pop still counted.
- **Evac:**
  - a med unit on `set_auto_evac` picks up the wounded in its area (capacity by unit) and delivers them to the nearest hospital;
  - a Field Hospital heals light wounds (≤30 s bleed used) in place and forwards the rest;
  - a Hospital heals fully → the unit re-spawns at the Hospital at full HP, free;
  - AI uses the same rules.

---
## §11 Acceptance skeletons (`tests/pending_g5/`)
- One file per agent (`test_<area>.gd`), with test names = Done-when items. Each test starts as `fail("not implemented: <item>")`.
- The owner moves its files into `tests/` at start. Done = all of its tests pass.
- **The final gate requires `tests/pending_g5/` to be empty.**

---
## §12 Board, bus, budgets
- **Board** `.plan/board.jsonl` (agent-board):
  - status every 5 calls (`calls_used`, `tokens_used_est`, `next_action`);
  - `claim`, `fact`, `change_request`, `handoff`, `done`;
  - `.plan/hb.sh` for long runs.
- **Bus** `.plan/bus.log` (agent-bus):
  - one line per finding/decision/dead end/milestone: `HH:MM:SS <ID> NOTE|FOUND|BLOCK|DONE <msg>`;
  - BLOCK lines name who they need.
- **Budgets:** per brief; registered by ORCH; guarded. Handoff at 70% of the projection to `.plan/handoff/<ID>-<n>.json`.
