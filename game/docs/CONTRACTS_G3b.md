# Integration contracts: G3b + Scale "Big Armies"

This extends `docs/CONTRACTS.md`, `CONTRACTS_G2.md` and `CONTRACTS_G3a.md`; all their hard rules still apply. Every number is PROVISIONAL unless marked **OWNER-APPROVED**.

Goal (from `PROGRESS.md`): finish the G3 slice (3 maps, Stage 7→8→9 with research) on a sim and renderer that hold **2,000 fully simulated units and 10,000+ on the large map** on the owner's PC (Ryzen 5 8640HS, Radeon 760M).

## 0. Hard rules added in this slice
- **Determinism stays.** Same seed + same commands = same `state_hash()`. Native code iterates in ascending entity-id order, uses no hash-map iteration order, no threads inside a tick, no wall-clock time and no global RNG.
- **Native is optional at runtime.** If `bin/rts_core.dll` fails to load, every system falls back to its GDScript path and all tests still pass. `NativeCore.available()` reports which path is live, and every perf number must say which.
- **Fidelity tiers never change outcomes that the player could see.** A unit near any enemy (contact radius) is always FULL tier. A tier change never duplicates or deletes materials, ammo, fuel or units.
- Never hard-code def names in new code. Use roles, flags, and the stage helpers below.

## 1. Ownership
| Agent | Owns (create/edit) |
|---|---|
| **N1-core** | `native/**` (Rust crate), `bin/**` (DLL + `rts_core.gdextension`), `sim/native_core.gd`, `sim/systems/movement.gd`, `tools/scale_bench.gd`, `tools/build_native.sh`, `tests/test_native.gd` |
| **R4-render** | `presentation/match_view.gd`, `presentation/view/entity_layer.gd`, `terrain_layer.gd`, `fog_layer.gd`, `fx_layer.gd`, `overlay_layer.gd`, new `presentation/view/batch_*.gd` / `lod_*.gd` |
| **MAP4** | `sim/map_gen.gd`, new `sim/maps/*.gd`, new `content/maps.json`, `sim/systems/bridges.gd`, `sim/systems/territory.gd`, `tests/test_maps.gd`. In `sim/world.gd`: **only** `_spawn_bridge()` and the spawn-assignment line in `new_match()` |
| **STG4** | new `sim/systems/progression.gd` (+ helper modules `sim/systems/progression_*.gd`), `production.gd`, `construction.gd`, `economy.gd`, `status.gd`, and `combat.gd` (EW/guided hooks only); `content/units.json`, `buildings.json`, `production.json`, `weapons.json`, `factions.json`, `stages.json`, new `content/research.json`, the `advancement` block of `rules.json`; `tests/test_stages.gd`, plus fixes to `tests/test_factions.gd` if stage gating breaks it |
| **UI4** | `presentation/**` except R4's files and `presentation/art/**`; `tools/ui_playtest.gd` |
| **ART4** | new `tools/art/g3b_*.gd` modules, the `MODULES` list in `tools/gen_art.gd` (append only), new entries in `assets/generated/**`, `tests/test_art_g3b.gd` |
| Wave 2: **AI4** | `sim/ai/**`, `tests/test_ai.gd` |
| Wave 2: **PERF4** | fidelity tiers across systems: takes over `combat.gd`, `supply.gd`, `morale.gd`, `fog.gd` and `economy.gd` after STG4/N1 finish |
| ORCH | `sim/world.gd` (except MAP4's lines), `sim/content.gd`, `tests/test_base.gd`, `tests/test_core.gd`, docs, `export_presets.cfg`, packaging |

Cross-file needs go in CHANGE_REQUESTS. Never edit another agent's file. Never run git write commands.

## 2. Scaffold already done (ORCH)
- `w.factions[fid]` now carries:
  - `stage` (int, 7/8/9);
  - `research = {"done": [], "active": "", "progress": 0.0, "facility": -1}`;
  - `advancing = {"to": 0, "ticks_left": 0}`;
  - `stats` gains `ore_refined`, `power_ok_ticks`, `line_trained`, `officers_trained`.
- `SimWorld.SCHEMA_VERSION = 3`.
- `sim/systems/progression.gd` is a stub in `SYSTEM_ORDER`, right after Production. Commands `"research"` and `"advance_stage"` route to it.
- `cfg.advancement` is `"free" | "standard" | "simulation"` (default `"standard"`). `cfg.map` is a map id (default `"river_crossing_s"`).
- `Content.role(faction_id, role, stage := 8)` returns the role def, honouring `factions.json` `stage_roles` overrides. `Content.available(def_dict, stage)` checks `stage_min` (default 7) and `stage_max` (optional).
- `content/rules.json` gains `advancement` with the OWNER-APPROVED gates (§3.2).

## 3. Stages and research (STG4)

### 3.1 Data
- Every unit, building and production def may carry `stage_min` (default 7) and `stage_max` (optional), plus `requires_research: [project ids]`.
- Construction and Production reject unavailable defs with a reason: `"Requires Stage 8"`, `"Requires research: Digital Networks"`.
- Stage-gated existing defs (`stage_min: 8`):
  - Human A `mbt`;
  - Human B `b_artillery_truck`, `b_heavy_rifle` (+ their production entries);
  - Machine `m_walker`, `m_artillery_node`.
- **New units** (ids fixed; ART4 draws them, STG4 defines stats):

| Faction | Stage 7 (older baseline, stays available) | Stage 9 (`stage_min: 9`) |
|---|---|---|
| human_a | `a_old_tank` Cold-War Tank (heavy at 7) | `a_uav` Recon-Strike UAV (`is_air`), `a_ew_truck` EW Truck, `a_guided_arty` Guided Artillery |
| human_b | `b_field_gun` Towed Field Gun (artillery at 7) | `b_radar_aa` Radar AA Truck (`anti_air`, long range), `b_jammer_truck` Jammer Truck (EW), `b_guided_battery` Guided Rocket Battery |
| machine | `m_siege_crawler` Siege Crawler (heavy at 7) | `m_swarm` Drone Swarm (`is_air`), `m_ew_node` EW Node, `m_lancer` Lancer (precision rail walker) |

- **New buildings:**
  - research (flag `research: true`, `stage_min` 7): `research_station` (A), `b_drafting_office` (B), `m_compute_node` (M);
  - comms (flag `comms: true`, `stage_min` 8): `comms_tower` (A), `b_signal_mast` (B). Machine's existing `m_sensor_relay` gets `comms: true`.
- `factions.json` `stage_roles`:
  - `{"7": {"heavy": <stage-7 heavy>, "artillery": <stage-7 artillery or "">}}`;
  - `"9"` entries add `air`, `ew` and `precision` roles.
- `content/research.json`: projects `integrated_manufacturing`, `combined_arms`, `digital_networks`, `target_fusion`, `electronic_resilience`.
  - Each has `name`, optional `names: {faction: name}`, `cost`, `time` (s), `stage_min`, `for_stage` (8 or 9).
  - Fixture costs: 7→8 projects 800 credits / 45 s; 8→9 projects 1,200 credits + 200 ore / 60 s.
  - One project at a time per side, at any building with `research: true`. Losing the building pauses research; progress is kept.

### 3.2 Advancement gates (OWNER-APPROVED 2026-10-23, numbers are tunable fixtures)
| | 7 → 8 | 8 → 9 |
|---|---|---|
| Running industry | `stats.ore_refined >= 600` (ore consumed by any `refines` building) | `>= 2` completed `comms` buildings |
| Power | power_prod >= power_use for 60 s straight (`power_ok_ticks >= 1200`; resets on any shortfall) | same |
| People | `officers_trained >= 1` and `line_trained >= 8` (units trained whose production id is the faction's infantry or antitank role) | `>= 3` living units of the faction's `recon` role (or `infantry` if recon is ""), OR `>= 40%` of map cells explored by the side's team |
| Research | integrated_manufacturing + combined_arms | digital_networks + target_fusion + electronic_resilience |
| Cost (Standard) | 3,000 credits + 400 salvage | 6,000 credits + 800 ore |

- Advancement rules multiply the cost: free x0, standard x1, simulation x1.5.
- `advance_stage` is a manual command, valid only when every gate is met. The cost is charged once through the ledger. It starts a **60 s transition** (`advancing.ticks_left = 1200`), then `stage += 1` and an event `StageAdvanced {fid, stage}` fires.
- Advancement **never spawns units or stock**; it only unlocks eligibility.
- `Progression.gate_report(w, fid) -> Array[{key, label, have, need, ok}]` is the single source for UI and AI.

### 3.3 New mechanics (minimal)
- **EW:** a unit with `ew_radius: R` applies status `jammed` to enemy units within R, refreshed every 10 ticks, lasting 20 ticks.
  - A jammed unit fires for 0.7x damage and has 0.7x sight. `electronic_resilience` research changes this to 0.85x for that side.
  - Status lives in `status.gd`; combat reads `Status.damage_mult(w, e)`.
- **Guided:** weapon flag `guided: true` means indirect fire with no friendly splash and no minimum-range scatter.
- Stage 9 air units reuse the G3a `is_air` / `anti_air` rules.

## 4. Maps (MAP4)
- `content/maps.json`: `id`, `name`, `size: "s"|"m"|"l"`, `w`, `h`, `spawns` (list), `spawn_sets` (`"2"`, `"3"`, `"4"` → spawn indices for fair layouts), `pois`, `max_sides`.
  - `river_crossing_s`: 96×96 (existing; behaviour unchanged, tests keep passing).
  - `industrial_heartland_m` Industrial Heartland: about **160×160**, a medium river basin.
    - Factory blocks (impassable building-terrain with salvage around), a rail siding (passable track decor), a refinery site (rich ore), a ruined plant (salvage-rich), towns, road loops.
    - 2 bridges plus fords; 6 spawn sites.
  - `valley_conquest_l` Valley Conquest: about **256×256**, a large valley.
    - River branches, a dam (a crossing), a tunnel portal (scenery), an airfield (open flat ground), foothill ridges, industrial pockets.
    - 3+ crossings; 8 spawn sites. **This map must physically hold 10,000 units**: plenty of open passable area.
- Map generation stays seeded and deterministic and passes `MapGen.validate` (all spawns mutually reachable for foot and vehicle, resources reachable, spawn fairness).
- Side i uses `map.spawns[map.spawn_sets[str(n)][i]]` (n = side count).
- Bridges: `map.bridges = [{cells, ...}]` (a list). `_spawn_bridge()` spawns all of them; the Hold-the-bridge victory uses bridge 0, or the map's `hold_bridge` id.
- Territory sectors stay 12×12 cells, so bigger maps get more sectors.
- New terrain/decor art goes through ART4 via CHANGE_REQUEST. Until it lands, use existing terrain codes and decor.

## 5. Native core (N1-core): Rust + godot-rust (gdext)
- Crate `native/rts_core/` (cdylib) builds `bin/rts_core.dll`; `bin/rts_core.gdextension` loads it.
  - `tools/build_native.sh` runs `cargo build --release` and copies the DLL.
  - **The built DLL is committed**, so a fresh clone runs without Rust.
- Classes (names fixed; methods take and return Packed arrays only, never Dictionaries):
  - `RtsGrid`: a uniform spatial hash.
    - `rebuild(ids: PackedInt32Array, pos: PackedVector2Array, team: PackedInt32Array, radius: PackedFloat32Array)`
    - `query_radius(center, r) -> PackedInt32Array` (sorted)
    - `nearest_enemy_batch(src_idx, ranges, team_mask...) -> PackedInt32Array`
  - `RtsNav`: grid pathfinding on the terrain codes for each move class, incremental block/unblock of footprints.
    - `find_path(start, goal, mc) -> PackedVector2Array`
    - **flow fields** shared by units heading to the same goal cell: `flow(goal, mc) -> handle`, `flow_dir(handle, cell) -> Vector2`, with an LRU cache.
  - `RtsSteer`: batch movement + separation step (positions, desired velocities, radii, move classes → new positions), with collision against the passability grid.
- `sim/native_core.gd`: a GDScript facade (preload, no class_name). It exposes `available()` and the same functions with GDScript fallbacks (the existing movement code).
- movement.gd uses the facade. `w.native_enabled` (default true when available) can be set false by tests to compare paths.
- **Packaged build:** the DLL must load in `build/...` from export-pack + the renamed runtime exe. Prove this with a log line `NATIVE rts_core loaded` from the packaged console exe. If it can't load, that is a STOP-IF: report it immediately.
- `tools/scale_bench.gd` (headless):
  - `--map=<id> --units=N --factions=a,b,m --ticks=600`
  - places N units across the sides on the map, mixed roles, half fighting and half marching;
  - prints a table of avg / p95 / max ms per tick and the native on/off state.

## 6. Rendering (R4-render)
- Targets (windowed 1600x900, vsync, this PC):
  - **60+ fps with 2,000 units fighting on screen**;
  - **30+ fps zoomed out with 10,000 units on Valley Conquest**.
- Replace one-Sprite2D-per-entity with batched drawing (MultiMesh or batched canvas draws per texture), cull everything off screen, and use zoom LOD:
  - close: full sprites + anim;
  - mid: sprites without small FX;
  - far: team-coloured unit/squad icons.
- Interpolate unit positions between sim ticks so motion stays smooth.
- If the sim tick still stalls frames after N1's work, move `world.step()` to a worker thread with a double-buffered render snapshot. Measure first.
- The terrain layer must handle 256×256 (65k cells) without per-frame cost: pre-baked chunks.
- Keep `--spawn-test=N`, `--fps-log`, `--sim-paused` and `--no-vsync` working. Add `--map=<id>` and `--zoom=<f>` for perf runs.

## 7. UI (UI4)
- Skirmish setup:
  - **map picker** (the 3 maps, showing size and max sides);
  - a **Stage 7/8/9 dropdown per side**;
  - an **Advancement rules** option (Free / Standard / Simulation).
  - The summary line shows the stage per side.
- HUD:
  - **stage panel**: current stage, the gate checklist from `Progression.gate_report` (have/need ticks), and an **Advance** button, enabled only when eligible, that shows the transition countdown;
  - **research panel** on research buildings: project list, cost, progress, start/cancel;
  - unavailable build/train buttons are shown disabled with the reason ("Requires Stage 8").
- Camera and minimap work on 160×160 and 256×256 (bounds, minimap scaling, edge pan speed).
- `tools/ui_playtest.gd` gets a `--ui-playtest-stages` flow: pick a map + stages in setup, build the research building, start a research project, and check the stage panel shows gates. Advancing fully is optional in the playtest; a test covers it.

## 8. Art (ART4)
- Sprites for the 9 new units and 5 new buildings in §3.1, in each faction's existing style (Human B: industrial/riveted; Machine: panels/emissive). Same pipeline as G3a: manifest-driven, team-colour masks, facings and animations like comparable units.
- Then POI decor for the maps: rail track, factory block, refinery tanks, ruined plant, dam, tunnel portal, airfield tarmac/hangar.
- Then far-zoom **LOD icons** (one per role class, per faction tint) for R4.
- Use the `art.gen_lock` board fact before running the full generator.

## 9. Acceptance (maps to the Done-when items)
- Tests, existing plus new:
  - MATCH-01: 3 sides at stages 7/8/9 with independent credits and different opening assets;
  - QA-002: AI Stage 9 vs player Stage 7, different tooling;
  - QA-014: exactly 13 IDs, only 7–9 active;
  - gates: each gate refuses when unmet and passes when met; cost charged once; no spawn on advance;
  - research: progress, pause on facility loss, save round trip mid-research;
  - native: deterministic hash with native on, save/load round trip, fallback path still passes;
  - maps: all 3 maps validate across seeds 1–20.
- Soaks: a 3-faction FFA with mixed start stages on each map ends with a winner, and an AI advances 7→8 and 8→9 (log line).
- Scale bench: 2,000 FULL units within the 50 ms budget at p95; 10,000 on `valley_conquest_l` within budget.
