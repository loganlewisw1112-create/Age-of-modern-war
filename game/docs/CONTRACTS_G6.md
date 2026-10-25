# CONTRACTS_G6: binding engineering contract for G6 "Command & Terrain"

Plan: `docs/PLAN_G6.md` (owner-approved 2026-10-25, all defaults D21-D44). Where this file and the plan disagree, **this file wins** for IDs, ownership and APIs. Changes go to ORCH as a board `change_request`. Branch: `g6`.

---
## §0 Hard rules (every agent)
1. **Ownership is exclusive** (§1). Touching another owner's file needs a `change_request` on the board. ORCH may grant a narrow edit.
2. **Determinism:** same seed + commands = same `state_hash` with the sim thread on or off, and with native on or off.
   - Iterate in ascending id order; assume nothing about Dictionary key order.
   - All randomness comes from `w.rng` in a fixed draw order.
   - New state lives in `w.sys_state.<system>`, on entity dicts or in `w.map`, is saved, and is in the hash. Runtime caches go in `w.cache` and are never saved.
3. **Existing results must not change** unless a section here says so. Every G5 hash test stays green.
   - **Allowed, contract-sanctioned changes:**
     - elevation, on maps that carry height (§7);
     - airfield v2 geometry (§13);
     - the built-in maps getting authored height (§7.5).
   - Anything else that would change existing results goes behind a `rules.json` flag that defaults to **off**.
4. **Content:** only your own fragment(s) (§1). New IDs only; never redefine an existing id (`sim/content.gd` rejects it).
5. **Write in chunks:**
   - a compiling skeleton first; edits ≤250 lines;
   - after each write: `"$G" --headless --path . --quit-after 60 2>&1 | grep -E -A1 "SCRIPT ERROR|Parse Error"` must print nothing;
   - post a board status after each write or test run;
   - if you break the build: `<ID> BLOCK tree.broken <file>` on the bus, then fix it at once.
6. **Runners time out and show parse errors:** never pipe Godot through a filter that drops `SCRIPT ERROR` / `Parse Error`. Wrap anything over 60 s in `.plan/hb.sh`; give long Godot runs a `timeout`. Godot hangs on exit after a GDScript parse error.
7. **Thread rule:** presentation reads only `w.render_snap` while `sim_busy()` is true, never `w.entities` during a step.
8. **Tests:**
   - your acceptance skeleton(s) are in `tests/pending_g6/`: `git mv` them to `tests/` when you start and make every test pass with real checks;
   - never weaken an assertion or delete another agent's test;
   - iterate with `bash tests/run.sh --only=<file>`; run the full suite once at the end inside `.plan/hb.sh`.
9. **Numbers are PROVISIONAL balance fixtures**, kept in content JSON, never hard-coded.
10. **Height-aware:** once `elev.api_ready` is posted, any new code that reads range, sight or line of sight goes through the `Elevation` API (§5).
11. **Network drop:** if your run is cut, you are resumed from your own transcript. Your first call back is a board status.

---
## §1 Ownership

| ID | Owns (exclusive) |
|---|---|
| ORCH | `sim/world.gd` (except the HOT block), `sim/content.gd`, `sim/save_system.gd`, `sim/systems/g6_hooks.gd`, base `content/*.json` (except the CONTENT6 grants), `content/rules.json` (except its `advancement` block), `docs/**`, `.plan/**`, `tests/pending_g6/**` (creates only), `tests/test_determinism.gd`, `tests/test_save*.gd`, `presentation/ui6/README.md`, every file not listed below |
| ELEV | `sim/terrain.gd`, `sim/systems/elevation.gd` (new), `sim/map_io.gd`, `sim/map_gen.gd`, `sim/maps/{valley_conquest,industrial_heartland,coastal_front,map_util,map_check}.gd`, `content/g6/rules_elevation.json`, `tests/test_elevation.gd`, `tests/test_maps.gd`, `tests/test_map_io.gd`, `tests/test_coastal_front.gd`, `tests/test_terrain_classes.gd` |
| PERF6 | `sim/hot_state.gd`; the `# >>> G5 HOT` block of `sim/world.gd`; `sim/systems/{movement,combat,damage,supply,morale,fog,tiers,territory,sim_index,unit_subsets}.gd`; `sim/native_core.gd`; `native/**`; `bin/**`; `tools/{build_native.sh,scale_bench.gd,bench.gd}`; `tests/{test_perf,test_perf_systems,test_hot_state,test_native,test_damage,test_thread}.gd` |
| CONTENT6 | `content/g6/defs_*.json`, `content/stages.json`, `content/factions.json`, `content/research.json`, the `advancement` block of `content/rules.json`, `tests/test_content_g6.gd`, `tests/test_stage10.gd`, `tests/test_stages.gd`, `tests/test_factions.gd` |
| ART-G6 / ART-G6b (sequential, never live together) | `tools/art/g6_*.gd` except `g6_terrain*.gd`, `tools/art/g6_art_gen.gd`, `assets/art/g6_units/**`, `assets/art/g6_bld/**`, `tests/test_art_g6.gd` |
| ARMY6 | `sim/systems/companies.gd` (new), `sim/systems/ops.gd`, `sim/systems/production.gd`, `content/g6/rules_companies.json`, `tests/test_companies.gd`, `tests/test_ops.gd` |
| MECH6a | `sim/systems/{mines,garrison,fieldworks,rail}.gd` (new), `sim/systems/{fortify,construction,g4b_mech}.gd`, `content/g6/rules_ground.json`, `tests/{test_mines,test_garrison,test_fieldworks,test_rail,test_fort,test_units_g4b}.gd` |
| MECH6c | `sim/systems/{callins,auras,mobility}.gd` (new), `content/g6/rules_support_g6.json`, `tests/{test_callins,test_auras,test_mobility}.gd` |
| MECH6b | `sim/systems/{machine_g6,strikes}.gd` (new), `content/g6/rules_machine.json`, `tests/{test_machine_g6,test_strikes}.gd` |
| NAVAL6 | `sim/systems/{naval,sonar,transport,support}.gd` (`sonar` new), `content/g6/rules_naval.json`, `tests/{test_naval_g6,test_naval,test_transport,test_support}.gd` |
| AIRDEF6 | `sim/systems/{airdef,counterdrone}.gd` (new), `sim/systems/{status,g5_mech}.gd`, `content/g6/rules_airdef.json`, `tests/{test_airdef,test_counterdrone,test_drone_team,test_units_g5}.gd` |
| ECON-AIRF6 | `sim/systems/market.gd` (new), `sim/systems/{airfield,air,economy}.gd`, `content/g5/air.json` (strip/slot/geometry keys only), `content/g6/rules_market.json`, `tests/{test_market,test_airfield_g6,test_air,test_airfield,test_air_transport,test_econ}.gd` |
| EXO6 | `sim/systems/{exo,loadouts}.gd` (new), `sim/systems/medical.gd`, `content/g6/rules_exo.json`, `tests/{test_exo,test_loadouts,test_medical}.gd` |
| MODES6 | `sim/systems/{victory,waves}.gd` (`waves` new), `sim/maps/{ridge_bastion,river_dam}.gd` (new), `content/g6/rules_survival.json`, `tests/{test_survival,test_victory}.gd` |
| ED6 | `presentation/editor/**`, `presentation/main.gd`, `sim/editor_live.gd` (new), `sim/systems/triggers.gd`, `content/scenarios/**`, `tests/test_editor_*.gd`, `tests/test_triggers.gd`, `tests/test_tutorial.gd` |
| AI7-USE | `sim/ai/**` except `sim/ai/doctrine/**`, `sim/ai/{commanders,ally_cmds,wave_ai}.gd`; `tools/soak.gd`; `tests/{test_ai,test_ai_g5,test_ai_air_naval,test_ai_g6,test_mil,test_g2_scenarios}.gd` |
| AI7-DOC | `sim/ai/doctrine/**` (new), `sim/systems/ops_missions.gd`, `tests/test_doctrine.gd` |
| AI7-CMD | `sim/ai/{commanders,ally_cmds,wave_ai}.gd` (new), `sim/systems/ai_command.gd` (new), `tests/{test_ai_commanders,test_ally_cmds,test_wave_ai}.gd` |
| ELEV-VIEW | `presentation/view/{terrain_layer,fog_layer,camera_rig,view_util}.gd`, `tools/art/g6_terrain*.gd`, `assets/art/g6_terrain/**`, `tests/test_elev_view.gd` |
| VIEW6 | `sim/render_snap.gd`, `presentation/view/{entity_layer,batch_art,batch_atlas,fx_layer,lod_icons,sim_runner,overlay_layer,g3_view}.gd`, `presentation/art/**`, `tests/{test_view6,test_view5}.gd` |
| UI6a | `presentation/ui5/kit/**`, `presentation/ui6/a/**`, `presentation/hud/{hud,hud_theme,scaled_layer,minimap,objectives,g2_alerts,g4b_alerts,g3_score,g3b_data,g3b_stage}.gd`, `presentation/menu/**`, `presentation/match_view.gd`, `tools/ui_fit_test.gd`, `tests/{test_ui_fit,test_ui6a,test_hud,test_ui3}.gd` |
| UI6b | `presentation/ui5/panels/**`, `presentation/ui6/b/**`, `presentation/hud/{g2_commands,g4b_commands,g3_faction,g2_inspector}.gd`, `presentation/view/{g4b_input,g4b_overlay,g2_input,g2_overlay}.gd`, `tests/{test_ui6b,test_ui_panels}.gd` |
| PT6 | `tools/ui_playtest.gd`, `tools/editor_playtest.gd`, `.plan/shots/PT6/**` |

The art kit `docs/g6_art_kit/` is reference material (ORCH-owned); ART-G6 copies from it.

---
## §2 Scaffold (ORCH, in place before any agent starts)
1. `sim/content.gd` merges `content/g4`, `content/g5`, then `content/g6` fragments (each sorted by name). It also accepts `"faction": "shared"` defs as buildable for every faction (§3.2).
2. **Empty system stubs**, registered in `SYSTEM_ORDER` and compiling; each has `static func tick(w)`, `validate_command`, `apply_command`.
   - **Order:** Economy, **Market**, Construction, Fortify, Airfield, Production, **Companies**, Progression, Gather, Repair, Ops, **AiCommand**, Orders, **Mines**, **Fieldworks**, **Garrison**, **Rail**, **Mobility**, Movement, Air, Naval, **Sonar**, Transport, **Airdef**, **Counterdrone**, Combat, G4bMech, G5Mech, **MachineG6**, **Strikes**, **Callins**, **Exo**, Medical, Support, **Auras**, Morale, Supply, Bridges, Fog, **Waves**, Triggers, Victory.
   - **Elevation** and **Loadouts** are libraries (no tick).
   - The stubs do nothing, so every G5 hash stays equal.
3. `COMMANDS` entries point at the owner stubs (§4). A stub's `validate_command` returns `"not_implemented"` until filled in.
4. `sim/systems/g6_hooks.gd` (§5.1) exists with neutral delegates. PERF6 wires its call sites.
5. AI stubs:
   - `sim/ai/doctrine/doctrine.gd` (`static func think(w, fid, st, ctx)`);
   - `sim/ai/commanders.gd` (`static func think_player(w, fid)`);
   - `sim/ai/wave_ai.gd` (`static func think(w, fid, st, ctx)`);
   - `sim/ai/ai_g6.gd` (`static func manage(w, fid, st, ctx)`).
   - `ai_controller.think_with` calls `G6.manage` + `Doctrine.think`. The world tick calls `Commanders.think_player` for human sides with AI commanders.
6. `content/g6/` holds one `_meta`-only file per owner (`defs_units_g6.json`, `defs_bld_g6.json`, `rules_*.json`).
7. `presentation/ui6/a/` and `presentation/ui6/b/` exist (README only).
8. `tests/pending_g6/test_*.gd` hold failing acceptance skeletons per agent (§17). The runner does not discover them until they are moved to `tests/`.
9. `rules.json victory_types` gains `survive` and `repel_waves`. `stages.json` stage 10 stays `playable_now: false` until CONTENT6 enables it.

---
## §3 IDs (fixed; art, AI, UI and tests key on these)

### §3.1 The 89 page assets (CONTENT6 defines them; art from `docs/g6_art_kit`)
**U** = unit, **S** = squad unit, **B** = building; stage in brackets. Squad sizes are fixed by the art kit (`docs/g6_art_kit/notes/`).

| Group | Human A | Human B | Machine | Shared (`s_`, faction `shared`) |
|---|---|---|---|---|
| Turrets (B) | `a_atgm_bunker`(8) `a_sam_site`(9) `a_laser_ciws`(9) `a_howitzer_pit`(8) `a_popup_turret`(9) | `b_pak_nest`(7) `b_flak_battery`(8) `b_net_post`(9) `b_mortar_pit`(7) `b_pillbox`(7) | `m_arc_pylon`(9) `m_pulse_spire2`(9) `m_jammer_obelisk`(9) `m_mass_driver`(10) `m_sentry_mine`(9) | |
| Fortifications (B) | | | `m_nanite_wall`(9) `m_phase_gate`(9) | `s_sandbags`(7) `s_trench`(7) `s_tank_traps`(7) `s_barbed_wire`(7) `s_minefield`(8) `s_garrison_bld`(7) `s_camo_decoy`(8) |
| Drones | `a_aerostat` U(8) `a_loiter_truck` U(9) `a_drone_cc` B(9) | `b_fpv_workshop` B(8) `b_jammer_team` S(9) `b_scrap_aa` S(8) | `m_hive_node` B(9) `m_swarm_queen` U(10) `m_mimic_drone` U(10) | |
| Vehicles (U) | `a_sp_howitzer`(8) `a_mlrs`(8) `a_mine_clearer`(8) `a_bridge_layer`(8) `a_command_vehicle`(8) `a_ugv`(9) | `b_landship`(9) `b_flak_halftrack`(8) `b_armored_dozer`(8) `b_salvage_crane`(8) `b_moto_scouts`(7) | `m_spider_layer`(9) `m_hover_tank`(10) `m_colossus`(10) `m_assimilator`(10) | |
| Infantry | `a_marines` S(8) `a_paratroopers` S(9) `a_eod` S(8) `a_jtac` S(9) `a_manpads` S(9) | `b_conscripts` S(7, squad 10) `b_satchel_sappers` S(7) `b_marksman` S(7) `b_propaganda_team` S(8) | `m_shield_drone` U(9) `m_stalker_synth` U(10) `m_repair_swarm2` U(9) `m_breacher_crawler` U(9) | |
| Aircraft (U) | `a_awacs`(9) `a_airlift`(9) | `b_recon_plane`(9) | `m_stealth_drone`(10) | |
| Naval (U) | `a_supply_ship_a`(8) `a_minesweeper`(8) `a_hovercraft`(9) `a_carrier`(9) `a_submarine`(9) | `b_supply_ship_b`(8) `b_mine_barge`(8) `b_aa_barge`(9) | `m_charge_tender`(8) `m_lance_cruiser`(9) | |
| Buildings | `a_radar_station` B(9) `a_fob` B(8) `a_repair_bay` B(8) `a_cruise_battery` B(9) | `b_rail_yard` B(8) `b_armored_train` U(8) `b_scrapyard` B(7) `b_propaganda_tower` B(8) | `m_nanite_forge` B(9) `m_overmind` B(10) `m_relay_lattice` B(9) | |
| Horizon (U) | `a_laser_tank`(10) `a_exo_trooper`(10) | `b_rhomboid`(**7**) | | |

The 4th-faction `x_*` ids are **not** in G6.

### §3.2 New ids not on the page (CONTENT6 defs; ART-G6b art)
- **Company HQ (B, size 3, Stage 8):** `a_company_hq`, `b_company_hq`, `m_company_hq`.
- **Commanders (U, Stage 8):** `a_commander`, `b_commander`, `m_commander`.
- **Company leaders (U, Stage 8, not producible alone; spawned with a company):** `a_captain`, `a_lieutenant`, `b_captain`, `b_lieutenant`, `m_captain`, `m_lieutenant`.
- **Exo:** `a_exo_garage` (B, size 2, Stage 9); suits `a_exo_rifle` (9), `a_exo_missile` (9), `a_exo_aa` (10).
- **Terrain:** code **14 = `RAIL`** (ELEV adds it to `Terrain`; MECH6a lays it).
- **Shared defs:** `"faction": "shared"` means buildable/producible by every faction. Shared defs keep one art set, team-tinted.

### §3.3 Research (CONTENT6, `research.json` additions; effects read by the named owner)
`g6_mines_1`, `g6_mines_2`, `g6_eod_1`, `g6_fieldworks_1`, `g6_cover_1`, `g6_garrison_1` (MECH6a) · `g6_radar_1`, `g6_sam_1`, `g6_ciws_1`, `g6_jamming_1` (AIRDEF6) · `g6_sonar_1`, `g6_torpedo_1`, `g6_carrier_1` (NAVAL6) · `g6_rail_1` (MECH6a) · `g6_armor_kits_1`, `g6_infantry_plates_1`, `g6_exo_armor_1`, `g6_exo_weapons_1` (EXO6) · `g6_company_drills_1`, `g6_command_net_1` (ARMY6) · `g6_nanite_1`, `g6_swarm_1` (MECH6b) · `g6_automation_doctrine` (Human A/B Stage 10 gate), `g6_overmind_protocols` (Machine Stage 10 gate).

### §3.4 Loadouts (EXO6, `rules_exo.json`)
- **Human A:** `standard`, `assault`, `at`, `marksman`, `breacher`, `plates`, `exo` (Stage 10).
- **Human B:** `standard`, `assault`, `at`, `breacher`, `plates`.
- **Machine:** `mod_armor`, `mod_sensor`, `mod_weapon` (crawler infantry-class units).
- `exo` renders with the `a_exo_trooper` sheet (`e.art_def`, §6). It does not change `e.def`.

### §3.5 Company templates (ARMY6, `rules_companies.json`)
- **Human A:** `a_rifle_co`, `a_mech_co`, `a_armor_co`, `a_arty_bty`, `a_air_assault_co`, `a_engineer_co`, `a_specops_det`.
- **Human B:** `b_conscript_bn`, `b_shock_co`, `b_heavy_armor_co`, `b_siege_bty`, `b_works_co`.
- **Machine:** `m_swarm_cluster`, `m_walker_phalanx`, `m_siege_array`, `m_hunter_pack`.
- Each template has sizes `platoon` | `company` | `battalion`. Custom templates use `custom:<name>`.

### §3.6 Other ids
- **Victory types:** `survive`, `repel_waves` (MODES6).
- **Maps:** `ridge_bastion_m`, `river_dam_m` (MODES6; ORCH registers them).
- **Doctrine reason tags** (AI7-DOC; soak gates grep these): `overwatch_set`, `high_ground_taken`, `flank`, `assault_phase`, `suppress`, `breach`, `reserve_commit`, `retreat`, `regroup`, `raid`, `sabotage`, `officer_hunt`, `exfil_done`, `defence_depth`.
- **AI Commander playstyles:** `defensive`, `aggressive`, `specops`, `combined`. **Stances:** `cautious`, `balanced`, `aggressive`. **Roles:** `base_defence`, `air_ops`, `logistics`, `naval`.

---
## §4 Commands (registered in `COMMANDS` by ORCH → owner stub)

| Command | Owner script | Fields |
|---|---|---|
| `market_trade` | Market | `{issuer, resource: "salvage"\|"ore"\|"fuel"\|"ammo", amount: int (>0 buy, <0 sell)}` |
| `train_company` | Companies | `{issuer, building_id (company HQ), template: id\|{custom template dict}, size}` |
| `train_commander` | Companies | `{issuer, building_id}` |
| `form_army` | Companies | `{issuer, commander_id, company_ids: [cid]}` (2-4) |
| `disband_army` | Companies | `{issuer, army_id}` |
| `set_company_refill` | Companies | `{issuer, company_id, on: bool}` |
| `set_loadout` | Exo | `{issuer, unit_ids, loadout, building_id}` (barracks or company HQ within range; Loadouts lib applies it) |
| `resuit` | Exo | `{issuer, building_id (garage), pilot_id, suit}` |
| `lay_minefield` | Mines | `{issuer, unit_ids, rect: [x0,y0,x1,y1], kind: "at"\|"ap"\|"mixed"}` |
| `sweep` | Mines | `{issuer, unit_ids, rect}` |
| `line_charge` | Mines | `{issuer, unit_id, cell: [x,y]}` |
| `garrison` / `ungarrison` | Garrison | `{issuer, unit_ids, building_id}` / `{issuer, building_id}` |
| `build_rail` | Rail | `{issuer, unit_ids, from: [x,y], to: [x,y]}` (the existing `build_line` stays for walls and fieldworks) |
| `deploy_bridge` / `pack_bridge` | Mobility | `{issuer, unit_id, cell, dir}` / `{issuer, unit_id}` |
| `airdrop` | Mobility | `{issuer, carrier_id, cell}` (paratroopers or supply pallet) |
| `designate` | Callins | `{issuer, unit_id, target_id?, cell?}` |
| `aerostat` | Callins | `{issuer, unit_id, on: bool}` |
| `strike` | Strikes | `{issuer, unit_ids, cell, target_id?}` (loiter, MLRS salvo, cruise, mass driver) |
| `assimilate` | MachineG6 | `{issuer, unit_id, wreck_id}` |
| `cloak` | MachineG6 | `{issuer, unit_ids, on}` |
| `submerge` | Sonar | `{issuer, unit_ids, on}` |
| `set_ai_commander` | AiCommand | `{issuer, slot, target: {formation: id}\|{role: id}, playstyle, objective: {type: "take"\|"hold"\|"raid"\|"escort", cell?, target_id?}, stance}` |
| `recall_ai_commander` | AiCommand | `{issuer, slot}` |
| `ally_request` | AiCommand | `{issuer, ally_fid, kind: "attack"\|"defend"\|"air_support", cell?}` |

- **Existing commands keep working.** Carriers act as fields for `sortie` / `rebase` (§11). `lay_mine` (G4 single mine) stays.
- **Production hooks** (ORCH wires them into production.gd before ARMY6 takes the file):
  - `Exo.can_produce(w, fid, def_id) -> String`;
  - `Companies.can_produce(w, fid, def_id) -> String`.

---
## §5 Cross-agent APIs (signatures fixed; post the fact when callable)

### §5.1 `sim/systems/g6_hooks.gd` (ORCH dispatcher; PERF6 wires the call sites, posts `core.g6_hooks_wired`)
Each function is neutral in the scaffold (1.0 / true / 0). It delegates to the owner functions listed; owners fill in their delegates.

| Hook | Called from (PERF6) | Delegates to |
|---|---|---|
| `damage_mult(w, src, s, t) -> float` | combat hit + splash | `Elevation.defence_mult`, `Fieldworks.cover_mult`, `Garrison.protect_mult`, `Loadouts.armor_mult`, `MachineG6.shield_mult` |
| `accuracy_mult(w, src, s, t) -> float` | combat hit roll | `Companies.cohesion_acc`, `Loadouts.acc_mult`, `Callins.designated_mult`, `Auras.acc_mult` |
| `range_mult(w, src, s) -> float` | target acquisition + fire (GD + native) | `Elevation.range_mult` |
| `los_ok(w, a, b) -> bool` | combat LOS (GD + native) | `Elevation.los` |
| `sight_bonus(w, e) -> float` | fog reveal radius | `Elevation.sight_bonus`, `Callins.sight_bonus` |
| `visible_to(w, fid, t) -> bool` | Fog.entity_visible + combat `_seen` | `Sonar.visible_to`, `Fieldworks.camo_visible`, `MachineG6.cloak_visible`, `Garrison.visible_to` |
| `speed_mult(w, e) -> float` | movement step | `Elevation.slope_mult`, `Fieldworks.wire_mult`, `Loadouts.speed_mult` |
| `passable(def, move_class) -> bool` | nav build (buildings with `passable_for`) | `Fieldworks.passable` |
| `morale_delta(w, e) -> float` | morale tick | `Auras.morale_delta`, `Companies.cohesion_morale` |
| `on_destroyed(w, e) -> void` | Damage before an entity is removed | `Exo.on_destroyed` (pilot eject), `Companies.on_destroyed` (promotion), `MachineG6.on_destroyed` (wreck registry) |

### §5.2 Facts and APIs

| Fact | Owner | API |
|---|---|---|
| `elev.api_ready` | ELEV | `Elevation.height_at(w, cell) -> int`, `ramp_at(w, cell) -> bool`, `edge_ok(w, a: Vector2i, b: Vector2i) -> bool` (false across a cliff edge; PERF6 uses it in nav), `adv(w, a: Vector2, b: Vector2) -> int` (levels a is above b), `los(w, a, b) -> bool`, `range_mult`, `defence_mult`, `sight_bonus`, `slope_mult`; `Terrain.RAIL`; move classes `rail` and `hover` in the Terrain class table |
| `elev.maps_ready` | ELEV | built-in maps carry authored height and validate; ORCH then re-baselines hash fixtures once |
| `core.g6_hooks_wired` | PERF6 | every §5.1 call site live (GD and native paths) |
| `content.g6_defs_ready` | CONTENT6 | every §3 id loads (stats provisional) |
| `art.g6_units_ready` / `art.g6_bld_ready` / `art.g6_new_ready` | ART-G6 / ART-G6b | manifest entries for every id in the group |
| `army.api_ready` | ARMY6 | `train_company`, `form_army`, ...; `Companies.company_of(w, uid) -> Dictionary`, `army_of(w, uid)`, `companies_of(w, fid)`, `templates_for(fid) -> Array`, `validate_template(fid, t) -> String`, `can_produce` |
| `mech_a.api_ready` | MECH6a | its commands; `Mines.known_to(w, fid) -> Array`, `Garrison.occupants(w, bid)`, `Fieldworks.cover_at(w, cell) -> float`, `Rail.on_rail(w, cell)`, `Callins.is_designated(w, tid)` |
| `mech_b.api_ready` | MECH6b | `strike`, `assimilate`, `cloak`; `MachineG6.wrecks(w) -> Array` |
| `naval6.api_ready` | NAVAL6 | `submerge`; `Sonar.submerged(e)`, `Sonar.detected_by(w, fid, e)`; carrier field registration through `Airfield.register_mobile_field` |
| `airdef.api_ready` | AIRDEF6 | `Airdef.radar_covers(w, fid, pos) -> bool`, `Airdef.air_picture(w, fid) -> Array`, `Counterdrone.jammed(w, pos, fid) -> bool` |
| `market.api_ready` | ECON-AIRF6 | `market_trade`; `Market.price(w, res, side: "buy"\|"sell") -> int`, `Market.limit_left(w, fid, res)` |
| `airfield6.api_ready` | ECON-AIRF6 | v2 geometry; `Airfield.slots(w, bid)`, `Airfield.register_mobile_field(w, carrier_id, slots)`; the G5 API kept |
| `exo.api_ready` | EXO6 | `set_loadout`, `resuit`; `Loadouts.loadouts_for(fid, def) -> Array`, `Loadouts.of(e) -> String`, `Exo.can_produce` |
| `doctrine.api_ready` / `doctrine.demo_ready` | AI7-DOC | `Doctrine.think`; `Doctrine.plan_for(w, fid, formation) -> Dictionary` (used by AI7-CMD); a demo replay under `.plan/shots/AI7-DOC/` |
| `aicmd.api_ready` | AI7-CMD | `set_ai_commander`, `recall_ai_commander`, `ally_request`; `AiCommand.slots(w, fid) -> Array` |
| `survival.api_ready` | MODES6 | victory types; `Waves.next_wave(w) -> Dictionary` (for UI) |
| `live.api_ready` | ED6 | `EditorLive.start(w) -> Dictionary` (snapshot), `EditorLive.stop(w, snap)`, `EditorLive.set_speed(n)` |

Until a fact is posted, callers use the stub, which returns a safe default. Calls must never crash on the stub.

---
## §6 State keys (saved, hashed)
- **`w.map.height`:** PackedByteArray, 0..3 per cell (ELEV). Absent = all plain (1) on load.
- **`w.map.terrain`** can hold code 14 RAIL.
- **`w.sys_state.companies`:** `{companies: {cid: {id, owner, template, size, captain, platoons: [gid], refill, army, losses}}, armies: {aid: {id, owner, commander, companies: [cid]}}, custom: {fid: {name: template}}, next_cid, next_aid, ver}`. Platoons are G2 `ops` groups whose officer is the lieutenant (ops gains `parent_company`).
- **`w.sys_state.<sys>`** for `market`, `mines`, `garrison`, `fieldworks`, `rail`, `callins`, `auras`, `mobility`, `machine_g6`, `strikes`, `sonar`, `airdef`, `counterdrone`, `exo`, `waves`, `ai_cmd`, each with a `ver`.
- **Entity fields** (documented in the owner's file header, G4 style):
  - `e.loadout`, `e.art_def` (render override; absent = `e.def`), `e.submerged`, `e.garrisoned_in`, `e.cloaked`, `e.company`, `e.platoon`, `e.rank_role` (`captain` | `lieutenant` | `commander`), `e.pilot_of`;
  - `e.height` is **not** stored (derived from `w.map.height`).
- **`w.ai_state[fid]`:** `.doctrine` (AI7-DOC), `.g6` (AI7-USE), `.waves` (AI7-CMD wave AI).
- **Player-side AI commanders** live in `w.sys_state.ai_cmd`.

---
## §7 Elevation (ELEV; numbers in `rules_elevation.json`)
1. **Levels:** 0 valley, 1 plain (default), 2 hill, 3 ridge.
   - **Ramp:** a cell whose level differs by exactly 1 from a 4-neighbour and is flagged in `map.ramps` (a PackedByteArray), or derived by `map_gen`.
   - **Cliff:** a level change with no ramp, impassable for ground classes.
2. **Rules (D24):**
   - per level of advantage over the target: sight +2, range ×1.10, damage taken from lower attackers ×0.85;
   - higher ground between two points blocks LOS (`Elevation.los` checks cells along the segment against the higher endpoint level);
   - climbing a ramp: speed ×0.7.
   - Air units and indirect fire ignore LOS. Indirect fire still gets the range bonus.
3. **Old terrain codes:** HILL (13) on load becomes level 2 (its old bonuses are replaced by the height rule). CLIFF (12) stays impassable and LOS-blocking. RIDGE (7) keeps its old meaning.
4. **Map file format** gains `height` + `ramps` and a version bump. Old files load as plain + HILL→2.
4a. **New move classes** (ELEV, in `Terrain`):
    - `rail`: RAIL tiles only (the armored train);
    - `hover`: land, beach, shallow, water and deep; not cliff, forest or building.

    RAIL tiles are passable for foot and vehicle like road.
5. **Built-in maps** get authored height. River Crossing (map_gen), Industrial Heartland, Valley Conquest and Coastal Front must all validate (every spawn reachable by foot and vehicle). Their hash fixtures are re-baselined **once**, by ORCH, after ELEV posts `elev.maps_ready`.

## §8 Companies and armies (ARMY6; numbers in `rules_companies.json`)
- **Template:** `{id, faction, slots: [{def, count}], leader_defs}`. Sizes scale counts: platoon ≈ 15, company ≈ 30, battalion = 45 elements MAX (squad = 1 element, vehicle = 1).
- **Custom templates:** validated against the same rules (faction, stage, 45 cap, at least one platoon).
- **`train_company`** at the faction's Company HQ:
  - cost and population = sum of members (D28, no discount); time = slowest member + 25%;
  - spawns everyone at once next to the HQ: captain + one lieutenant per platoon (a platoon = up to 15 elements) + members;
  - each platoon is an `ops` group (officer = lieutenant).
- **Hierarchy:**
  - army → companies → platoons. `Ops` missions run per platoon; the captain gives platoon missions; the Commander gives company objectives.
  - **Captain dies:** the senior lieutenant becomes captain. Confusion 10 s (no new orders) and −15 morale for the company. The promoted lieutenant's platoon gets the next-senior squad leader (element) as officer, or merges into a sibling platoon.
  - **Commander dies:** the army dissolves into its companies (`ArmySplit`).
- **Limits:** Company HQ one per player at a time (D31); Commander at most 2 alive (D30); army 2-4 companies; 2 armies per player.
- **Cohesion (D29):** within 12 tiles of its captain, +10% accuracy and +10 morale.
- **Refill:** when on, every lost element queues a replacement at the Company HQ (normal cost). It travels to its platoon.

## §9 Ground systems (MECH6a; `rules_ground.json`)
- **Minefield `s_minefield`:**
  - laid by `lay_minefield` over a rect (≤ 8×8). Spawns `mine` entities (the G4 kind, `layer: "land"`, `mine_kind: at|ap`) on a seeded pattern.
  - Owner team sees the boundary; others see mines only once detected (the G4 `seen` rule).
  - AT mines trigger on vehicles; AP mines on foot.
- **Clearing:**
  - EOD (`a_eod`) and recon detect within their radius;
  - `sweep` clears a rect at N cells/s;
  - `a_mine_clearer`'s `line_charge` clears a 2×10 lane at once.
  - Sea mines: `layer: "sea"`, laid by `b_mine_barge` / swept by `a_minesweeper` (NAVAL6 calls the Mines API).
- **Garrison:**
  - `s_garrison_bld`, `b_pillbox` and `a_fob` have `garrison_slots`;
  - squads inside fire from the building, take ×0.5 damage and are hidden from fog until they fire;
  - the building's death ejects or kills them (by rule);
  - flame and satchel weapons get `anti_garrison` ×2.
- **Fieldworks:**
  - `s_sandbags` and `s_trench` are buildable by any foot infantry (`field_buildable`), through `build_line`. Units in or behind them get `cover_mult` (sandbags 0.75, trench 0.6 vs direct fire, trench 0.5 vs splash).
  - `s_tank_traps`: `passable_for: ["foot"]`. `s_barbed_wire`: foot speed ×0.35, cleared by flame, tanks or engineers.
  - `s_camo_decoy`: the camo net hides a parked unit until it moves or fires. The decoy is a fake target, AI-priority weighted.
- **Rail:**
  - RAIL tiles are laid by `build_rail` from a Rail Yard (engineers);
  - `b_armored_train` moves only on rail (move class `rail`);
  - a destroyed rail tile cuts the line until repaired.
- **Call-ins:**
  - JTAC `designate` marks a target: friendly strikes and artillery on it get accuracy ×1.25 and −30% delay;
  - the aerostat gives +12 sight while deployed;
  - `a_drone_cc` gives drone teams in range +1 charge cap and +50% range;
  - AWACS shares the air picture (AIRDEF6 API).
- **Auras:** `a_command_vehicle`, the Commander, `b_propaganda_team` and `b_propaganda_tower` give +morale and accuracy to friendlies in radius. Propaganda also drains enemy morale.
- **Mobility:**
  - `deploy_bridge` lays a 1×N span over water ≤ 6 (passable for foot and vehicle) until `pack_bridge`;
  - `airdrop` from `a_airlift` / transport gunship lands paratroopers or a supply pallet in a 3×3 area;
  - `a_marines` unload ×2 faster from naval transports.
- **Engineering:**
  - the armored dozer removes traps, wire and wrecks;
  - the salvage crane / scrapyard turns towed wrecks into salvage income;
  - the repair bay repairs vehicles parked inside at ×3;
  - satchel sappers and the breacher crawler carry `breach` charges (G4 charge pattern, ×2 vs walls and gates).

## §10 Machine specials and strikes (MECH6b; `rules_machine.json`)
- **Self-repair:** `m_nanite_wall` regrows hp while powered; `m_nanite_forge` heals Machine units in its radius out of combat; `m_repair_swarm2` heals units in combat.
- **`m_assimilator`:** `assimilate` a wreck within 2 tiles over N s → spawns a Machine unit by wreck class (light → crawler, heavy → tracked platform).
- **Spawners:** `m_hive_node` spawns `m_micro_drone`s up to a cap; `m_swarm_queen` spawns while alive.
- **Disguise, cloak, shield:**
  - `m_mimic_drone` reads as an enemy drone to the opponent until within 3 tiles (`e.art_def` set per viewer by VIEW6 from `MachineG6.disguise_for`);
  - `m_stalker_synth`'s `cloak` makes it invisible when still (G4 conceal pattern);
  - `m_shield_drone` projects `shield_mult` 0.5 vs small arms on friendlies in a 4-tile arc.
- **Other Machine buildings:**
  - `m_relay_lattice` extends Machine build/power range along a chain;
  - `m_overmind` unlocks Stage 10 Machine tech + global Coordinator range;
  - `m_phase_gate` is a fort gate passable only to its team (the G4 gate rule).
- **Strikes:**
  - `a_loiter_truck`: launches loitering munitions (G5 drone entity pattern), 6 per load;
  - `a_mlrs`: a 12-rocket salvo over an area, long reload;
  - `m_mass_driver`: a very long-range single slug;
  - `a_cruise_battery`: a global-range cruise strike on a long cooldown, interceptable by CIWS.

## §11 Naval (NAVAL6; `rules_naval.json`)
- **Submarines (D38):**
  - submerged subs are invisible to a team unless within `sonar` range of one of its units (destroyer 10, AA frigate 8, minesweeper 6), or for 5 s after firing;
  - surfaced subs are visible and faster, and can be resupplied;
  - `submerge` toggles; torpedo weapons hit naval only.
- **Carrier (D39):** registered as a mobile field with 4 light hangar slots (strike jet / interceptor). Aircraft `rebase` to it and sortie from it. It rearms at a Supply Ship or pier.
- **Supply ships:** `a_supply_ship_a`, `b_supply_ship_b` and `m_charge_tender` run G5 Auto resupply on water (support.gd).
- **Hover:** move class `hover` crosses land and water (no deep-water stop). `a_hovercraft` carries 1 vehicle + 8 foot.
- **Sea mines and sweeping** use the Mines API (§9).

## §12 Air defence and counter-drone (AIRDEF6; `rules_airdef.json`)
- **Radar:** `a_sam_site` only fires when a friendly radar (`a_radar_station`, an AWACS within range, or a Machine `m_pulse_spire2` own radar) covers the target. Radar shows incoming aircraft on the minimap.
- **AWACS:** reveals aircraft in radius 24 for its team; +20% AA accuracy in that radius.
- **Counter-drone:**
  - `a_laser_ciws` kills launched drones, rockets and shells inside radius 6 (rate-limited);
  - `b_net_post` captures drones intact (+salvage);
  - `m_jammer_obelisk` and `b_jammer_team` drop enemy drones and guided shots in their field (`Counterdrone.jammed`);
  - `b_scrap_aa` gets `anti_drone` ×2.

## §13 Market and airfield v2 (ECON-AIRF6)
- **Market (D27):**
  - resources: salvage, ore, fuel, ammo;
  - base prices in `rules_market.json`; every unit bought by anyone +1%, sold −1%, drift back to base over 180 s; sell = 70% of buy;
  - per-player trade limit per 60 s; ledger cause `market:<res>`;
  - opened from the HQ panel (no building). AI uses the same command.
- **Airfield v2 (D25, D26):**
  - `a_airfield` / `b_aerodrome`: a 2×2 main base + tarmac apron + 1 runway of 12 tiles. `a_airstrip` 8, forward strips 6, `m_launch_rail` 6.
  - 6 hangar slots on the apron; each `extra_strip` adds 1 runway + 2 slots. `build_hangar` auto-fills the next slot.
  - The G5 flight / holding / crater / divert / engineer logic is kept on the new geometry.
  - **Migration:** G5 saves and maps load into v2 (strips re-laid, hangars re-slotted in order).

## §14 Exo-suits, loadouts, research, Stage 10 (EXO6 + CONTENT6)
- **Exo-suits (D32, Human A only):**
  - `a_exo_garage` (size 2) produces `a_exo_rifle` / `a_exo_missile` (Stage 9) and `a_exo_aa` (Stage 10);
  - a suit counts as 1 vehicle element in a company.
  - **Destroyed suit:** spawns its pilot (def `rifleman`, `wounded: true`, `pilot_of: suit_def`) under G5 medical rules; `resuit` at a garage costs 60% of the suit.
- **Loadouts (D33, D34):**
  - `set_loadout` near a barracks or the Company HQ, with a cost per loadout;
  - stat modifiers (weapon swap, armour, speed) come through `Loadouts` + G6Hooks;
  - `exo` = the Iron-Man-style tier (`a_exo_trooper` art, Stage 10, research `g6_infantry_plates_1` → `g6_exo_armor_1` chain).
  - `a_exo_trooper` is also directly producible at the barracks at Stage 10.
- **Research (D35):** the §3.3 items, each with an effect key read by its owner.
- **Stage 10 (D36):**
  - gates = the 8→9 structure ×1.5 cost + the gate research; 60 s transition;
  - `stages.json` stage 10 becomes `playable_now: true`;
  - `factions.json` stage_roles `"10"` lists the unlocks (PROGRESS item 7).

## §15 Survival and editor Live (MODES6, ED6)
- **Survival (D42):**
  - `survive {seconds}`: the defender wins at time if its HQ stands;
  - `repel_waves {count}`: the defender wins after N waves are destroyed;
  - waves spawn at map edges (or the map's `wave_spawns`) every 90 s, escalating by `rules_survival.json`, using the attacker faction's company templates;
  - the Wave AI (AI7-CMD) commands them.
  - Maps `ridge_bastion_m` (walled ridge, 2 ramps, 4 lanes) and `river_dam_m` (dam + bridges).
- **Editor Live (D43):**
  - `L` toggles Live;
  - `EditorLive.start` snapshots the full world (`SaveSystem` dict) and runs combat + AI tactics only (`cfg.live_mode = true`: Economy, Production, Construction, Progression and Market ticks are skipped);
  - speed pause / 1 / 2 / 4;
  - `stop` restores the snapshot: `state_hash` equals the pre-Live hash. Undo history is untouched.

## §16 AI (AI7-USE, AI7-DOC, AI7-CMD)
- **Fairness:** same rules as players (no map hacks, no free resources), including on the market.
- **Doctrine (D40)**, all AIs, enemy included:
  - **Strategic layer** per Commander or AI side: fronts, main effort vs fixing force, reserves, timing, retreat and regroup.
  - **Operational layer** per company: axis, formation, phase lines; combined-arms sequence recon → suppress → assault → consolidate; artillery prep; breaching.
  - **Tactical layer** per platoon: height and cover seeking (Elevation + Fieldworks APIs), bounding overwatch, flanks, garrisons, mine awareness.
  - **Missions** in `ops_missions.gd`: `raid`, `sabotage`, `recon`, `officer_hunt`, `exfil` (extract squads, wounded, pilots and VIPs to a safe point).
  - Every decision emits event `AiDecision {fid, tag, unit_ids, reason}` with a §3.6 tag. The soak logs count them.
- **AI Commanders (D41)**, player side:
  - up to 4 slots per player; each takes a formation or a role, a playstyle, an objective and a stance;
  - it plans through `Doctrine.plan_for`;
  - it never issues an order to a unit within 20 s of a player order to that unit (`e.player_order_tick`);
  - `recall` returns control at once; a badge shows which units are AI-commanded.
- **Ally AI:** `ally_request` makes an allied AI side commit a formation to attack, defend or provide air support within its means.
- **AI uses everything:** companies and armies, every new defence, mines, garrisons, subs, carriers, SAM + radar, counter-drone, market trades, airfield v2, loadouts, exo-suits, Stage 10.

## §17 Acceptance skeletons (`tests/pending_g6/`)
- One file per owner test in §1 that is new in G6. Test names = Done-when items. Each starts as `check(false, "not implemented: <item>")`.
- The owner moves its files into `tests/` at start. Done = all of its tests pass.
- **The final gate requires `tests/pending_g6/` to hold only README.md.**

## §18 Board, bus, budgets
- **Board** `.plan/board.jsonl` (agent-board):
  - status every 5 calls (`calls_used`, `tokens_used_est`, `next_action`);
  - `claim`, `fact`, `change_request`, `handoff`, `done`;
  - `.plan/hb.sh` for long runs.
- **Bus** `.plan/bus.log`: one line per finding / decision / dead end / milestone: `HH:MM:SS <ID> NOTE|FOUND|BLOCK|DONE <msg>`.
- **Budgets:** every builder 750k tokens / 140 calls unless its brief says otherwise; registered by ORCH; guarded (guard model base 303k + 2.3k/call). Hand off at 70% of the projection to `.plan/handoff/<ID>-<n>.json`.
