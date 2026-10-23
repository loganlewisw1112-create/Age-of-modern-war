# Integration contracts: G2 "Smart Warfare"

Extends `docs/CONTRACTS.md`. Every rule in §0 of that file (pure sim, determinism, commands only, ledger only, serializable state, no class_name on systems, ownership, no commits, UTF-8, ≤250 lines per write) still applies. All new numbers live in `content/*.json` and are PROVISIONAL fixtures.

Source requirements:
- First Playable §7 (combat: directional armor, cover, suppression/morale, ammo/fuel, component disablement, wrecks/bridges, correct targeting under fog).
- Roadmap G2 ("Groups, officer mission, suppression/cover, armor/component damage, supply, smarter AI. Proof: orders persist and AI attacks without scripted trigger").
- Bundle C, MIL-02, QA-007, QA-008.

## 1. Shared status hooks (`sim/systems/status.gd`, ORCH-owned)
Every system asks status.gd, never re-derives:
- `move_mult(w, e) -> float`: 0 when a vehicle has `comp.mobility <= 0`, when a vehicle has `fuel <= 0`, or when the unit is `broken` and retreating (then 1.2: running). `pinned` gives 0.5. Otherwise 1.0.
- `can_fire(w, e) -> String`: "" or a reason: "WEAPON_DISABLED", "NO_AMMO", "BROKEN".
- `accuracy_mult(w, e) -> float`: pinned 0.5, suppression > 25 gives 0.8, sensors disabled 0.7.
- `sight_mult(w, e) -> float`: sensors disabled gives 0.5.

Movement multiplies speed by `move_mult`. Combat checks `can_fire` before firing and multiplies accuracy. Fog multiplies sight. The ORCH wired these calls in the scaffold. The agents below only set the entity fields that status.gd reads.

## 2. Damage pipeline (`sim/systems/damage.gd`, agent A2)
`combat._fire` calls `Damage.apply_hit(w, shooter, target, s, hit:bool)` for EVERY shot, hit or miss. A miss still suppresses. damage.gd owns:
- **Directional armor (vehicles only):** use the angle between the target's `facing` and the vector target→shooter. Front ±45° ×1.0, side ×1.35, rear ×1.7 (`rules.armor_facing`). Emit `hit_side` in a `Damage` event.
- **Cover (infantry):** a target standing on FOREST, or within 1.0 tile of a wreck/building footprint, takes ×0.6 damage from small_arms and autocannon (`rules.cover`). `e.in_cover:bool` is updated each tick by A2's tick so the UI can show it.
- **Components (vehicles):** `e.comp = {mobility, weapon, sensors}`, each 0..100 and initialized lazily from `units.json` `components`. On an AT/autocannon hit, roll `w.rng` against `rules.component_hit_chance`. A hit component loses damage × `rules.component_damage_mult`. At ≤0 the component is disabled. Emit `ComponentDisabled {id, component}` once per disable. A mobility kill leaves the weapon firing (MIL-02/QA-008).
- **Suppression/morale (infantry):** `e.supp` 0..100, raised by incoming hits and near misses (`rules.suppression`), decaying per second when not under fire. `e.pinned = supp >= 60`. `e.morale` 0..100 (start 100) drops when nearby squadmates die and while pinned, and recovers out of combat. At `morale < rules.morale.break_at`: `e.broken = true`, the unit retreats to its own HQ or nearest depot via `Movement.order_path` (order `{"type":"retreat"}`), emits `UnitBroken`, and rallies (`broken=false`, order idle) once morale recovers above `rally_at`.
- **Line of fire:** `Damage.line_clear(w, from, to) -> bool`. False if the segment crosses a RIDGE cell. Combat must not fire without it (ORCH hook calls it).
- **Concealment:** infantry on FOREST is visible to enemies only within `rules.concealment_range` unless it fired in the last 60 ticks. A2 owns this edit in `fog.gd`.
- A2 owns: `sim/systems/damage.gd`, `sim/systems/morale.gd` (tick: cover flags, suppression decay, morale, break/rally), `fog.gd` (concealment), and the small integration edits inside `combat.gd` beyond the ORCH hook. Tests: `tests/test_damage.gd`.

## 3. Supply, repair, refinery (agent B2)
- New ledger keys `fuel` and `ammo` (world.LEDGER_KEYS, ORCH). Faction stock starts from `rules.start_package.stock`.
- Units: `e.ammo` (rounds, from `units.json` `ammo_max`). Every shot costs 1 round; with 0 the unit can't fire ("NO_AMMO"). Vehicles: `e.fuel` (from `fuel_max`), consumed per tile moved (`fuel_per_tile`).
- **Resupply** (`sim/systems/supply.gd` tick): every 20 ticks, a unit within `rules.supply.radius` of an own built HQ, depot, or a `logistics_truck` refills up to `supply.refill_per_second`. It draws exactly that amount from faction stock via `w.spend(fid, {"ammo": n}, "resupply")`, so the ledger journal proves conservation. Empty stock means no refill, and `faction.status_supply = "NO_AMMO_STOCK"`.
- **Refinery** (new building): while built and powered, converts `rules.refinery.ore_in` ore into `fuel_out` fuel + `ammo_out` ammo every `period_s`. It uses `w.spend` then `w.credit`, cause "refinery". If ore is short, the building status is "NO_ORE".
- **Repair command** `repair {unit_ids (engineers), target_id}` on an own damaged vehicle, an own building, or a ruined bridge (see section 4):
  - The engineer moves adjacent and restores `rules.repair.hp_per_second`.
  - It costs salvage at `rules.repair.salvage_per_100hp`, paid per 100 hp chunk via `w.spend`.
  - It also restores components, mobility first.
  - It stops when the target is full or the money runs out (event `RepairBlocked {reason}`).
- B2 owns `sim/systems/supply.gd`, `sim/systems/repair.gd`, `economy.gd` (refinery), `production.gd` (nothing, unless needed), `tests/test_supply.gd`.

## 4. Officers, missions, orders, bridge (agent C2)
- **Officer** unit (barracks): `assign_officer {officer_id, unit_ids}` creates/updates a formation in `w.sys_state.ops.groups[gid] = {id, owner, officer, members[], mission:{}, phase, reason, progress, history[]}`. A unit is in at most one group. Members dying are removed. When the officer dies, the group dissolves (`OfficerKilled`), and members take a morale hit (−20) via `w.cache` hooks or direct field edit.
- `set_mission {officer_id, mission, target:Vector2, radius:float=6, risk:"low"|"medium"|"high"}`. Missions: `secure_point`, `hold_zone`, `attack_area`, `patrol_route` (target plus `points[]`).
  - Phases: `assess → move → secure → hold`, plus `resupply` (if group mean ammo < 30%) and `withdraw` (losses exceed the risk bound low 25% / medium 50% / high 75% of starting strength).
  - The officer issues ordinary commands to members (move/attack_move/hold) via internal helpers that bypass `submit` only through the same handler functions (call `Movement.apply_command` style helpers directly, deterministic). Every phase change emits `OfficerReport {gid, phase, reason, progress}` with a human-readable reason ("Secured bridge east bank; holding.", "Losses 52% > medium risk; withdrawing.").
  - `secure_point` succeeds when no visible enemies are within radius and ≥50% of members are inside radius for 5 s. Progress is 0..1.
- **Player override:** a direct move/attack/stop/hold command on a member detaches that member from mission control for `rules.ops.override_ticks` (it stays in the group). `cancel_mission {officer_id}` → group idle.
- **New direct orders:** `patrol {unit_ids, points[]}` (loop, attack-moving between points), `guard {unit_ids, target_id}` (follow own unit/building, engage within sight), `set_formation {unit_ids, formation:"line"|"wedge"|"column"}` (stored per unit as `e.formation`; Movement.formation_slots reads it, and C2 owns that small edit).
- **Bridge:** at match start the ORCH scaffold spawns one neutral `structure` entity `bridge_span` covering `map.bridge_cells` (hp from `buildings.json`).
  - It is attackable by an explicit `attack` from any side. It is not auto-targeted.
  - At hp ≤0: bridge cells become `Terrain.WATER`, `map.bridge_state = "ruined"`, `Movement.on_terrain_changed(w)` runs, the entity becomes `kind:"ruin"`, and `BridgeDestroyed` is emitted. Units standing on the cells are nudged to the nearest free cell, or die if none exists within 3 tiles.
  - Repair (B2's `repair` command on the ruin) restores the cells to BRIDGE and the entity to structure, then emits `BridgeRepaired`.
  - Paths re-route automatically. Pending paths through dead cells must be re-requested (QA-007).
- C2 owns `sim/systems/ops.gd`, `sim/systems/orders.gd`, `sim/systems/bridges.gd`, the `formation_slots` edit in `movement.gd`, and `tests/test_ops.gd`.

## 5. Presentation (agent D2) and art (agent E2)
- **D2 (view + HUD):** surface everything above.
  - **Unit inspector:** ammo/fuel bars, component status chips (MOB/WPN/SEN green/amber/red), PINNED/BROKEN/IN COVER tags.
  - **Overlay:** a small suppression/pinned marker, a disabled-vehicle smoke loop, retreat arrows.
  - **Top bar:** fuel and ammo stock.
  - **Commands:** Patrol (P is used by pause, so use Shift+click waypoints with the Q hotkey), Guard (G only when units are selected; engineers keep G for generator), Formation (F cycles), Repair (engineers, right-click own damaged target = smart repair), Assign Officer (select officer + units → button), Mission panel (mission type, click target, risk), and an Officer card showing group, phase, reason, progress and history.
  - **Bridge:** damaged and ruined visuals, an alert on BridgeDestroyed/Repaired.
  - Alerts for ComponentDisabled, UnitBroken, OfficerReport, supply shortages.
  - D2 owns `presentation/**` except `presentation/art/**`.
- **E2 (art):**
  - A detail pass on all vehicles and buildings: more panel lines, hatches, tracks/wheels, antennas, crates, pipes, windows, rooftop clutter, stronger shading and ambient occlusion. Keep silhouettes and pivots stable so D2's offsets stay valid.
  - New sprites: `officer` (cap and radio, 8 facings), `logistics_truck` (8 facings), `refinery` (3x3, 4 build stages), `bridge_span` intact/damaged/ruined overlay sprites, a disabled-vehicle smoke/fire loop, a pinned marker, and icons for the new items/commands.
  - E2 owns `tools/gen_art.gd`, `tools/art/**`, `assets/generated/**`, `presentation/art/**`, `tests/test_art.gd`.

## 6. AI (agent G2-ai, wave B) and QA (agent Q2, wave B)
- **AI:** use officers for attack groups (secure_point on the crossing, attack_area on the enemy base), pull back broken or low-ammo units, build a refinery and keep ammo/fuel stock, bring a logistics truck with the army, prefer AT/MBT against seen vehicles, flank to rear arcs when possible, repair a ruined bridge or re-route via fords. Fairness rules unchanged.
- **QA:** cross-system scenario tests (`tests/test_g2_scenarios.gd`), soak invariants (ammo/fuel ≥0, ledger conservation including refinery, no unit inside water after a bridge collapse), and a bench re-run.

## 7. Event fields (documented for the HUD)
Every event carries `type` and `tick`.
- `Damage {shooter, target, amount, hit_side, in_cover}`
- `ComponentDisabled {id, owner, component}`
- `UnitBroken {id, owner}`, `UnitRallied {id, owner}`
- `OfficerReport {gid, owner, officer, phase, reason, progress}`, `OfficerKilled {gid, owner}`
- `BridgeDestroyed {cells}`, `BridgeRepaired {cells}`
- `RepairBlocked {unit_id, target_id, reason}`
- `SupplyShortage {faction, res}`
- `ConstructionCompleted {building_id, def, owner}`, `ProductionBlocked {building_id, owner, reason}`, `ProductionCompleted {building_id, owner, item, unit_ids}`. These are G1 events with their fields now documented.
