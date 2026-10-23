# C2-ops: officers + delegated missions, patrol/guard/formation, destructible bridge
MAX_TOKENS 600000 | MAX_TOOL_CALLS 150 | model opus (state-machine design + nav interplay)

You own `sim/systems/ops.gd`, `sim/systems/orders.gd`, `sim/systems/bridges.gd`, and `tests/test_ops.gd`. You may also edit:
- `Movement.formation_slots` in `sim/systems/movement.gd`, to read `e.formation`. Touch nothing else there. `Movement.on_terrain_changed(w)` already exists; use it.

Implement CONTRACTS_G2.md section 4 exactly. The world already has:
- commands routed: `assign_officer`, `set_mission`, `cancel_mission` → ops.gd; `patrol`, `guard`, `set_formation` → orders.gd;
- `Ops.on_direct_order(w, cmd)` called after every direct order;
- the bridge spawned as `{kind:"structure", def:"bridge_span", owner:-1, cells:[...], state:"intact"}`;
- `world.destroy()` delegating structures to `Bridges.on_destroyed(w, e, killer_owner)`;
- explicit `attack` on the bridge allowed in combat.

Details:
- **Officer missions** are a deterministic state machine run every 10 ticks per group (stagger by gid).
  - The officer issues orders to members by calling the movement/combat handler functions directly (`Movement.apply_command(w, {"type":"attack_move","issuer":fid,"unit_ids":[...],"target":p})`, etc.). It never calls `w.submit` (that would loop through `on_direct_order`).
  - Members under player override (`e.ops_override_until > w.tick`) are skipped.
  - Every phase change and every 30 s of no change emits `OfficerReport` with a specific reason sentence and progress. Keep the last 10 reports in `group.history`.
- **Missions:**
  - `secure_point`: assess, then move (attack_move to target), then secure. It succeeds when no visible enemy is within radius and ≥50% of members are inside for 100 ticks; then hold.
  - `hold_zone`: like secure, then hold position with the hold stance.
  - `attack_area`: attack_move, then engage until no visible enemies are within radius; then hold.
  - `patrol_route`: cycle points with attack_move.
  - `resupply`: when mean ammo is below `ops.resupply_ammo_frac`, move to the nearest own depot/HQ/logistics truck, then return.
  - `withdraw`: on losses past the risk bound, move to the nearest own HQ/depot; the mission ends as "failed".
  - The officer itself stays slightly behind the group's centroid.
- **Officer death** dissolves the group (`OfficerKilled`), and members lose 20 morale (field `morale` if present).
- **Orders** (orders.gd):
  - `patrol {unit_ids, points[2..6]}`: loop attack_move between points; validate the points are in bounds.
  - `guard {unit_ids, target_id}`: follow an own unit/building at about 2 tiles and engage within sight.
  - `set_formation {unit_ids, formation}`: sets `e.formation` to line, wedge or column. `formation_slots` honours the formation of the first unit in the group.
- **Bridges** (bridges.gd), on_destroyed:
  - Set the bridge cells' terrain to WATER (write `w.map.terrain`), `e.state="ruined"`, `e.kind` stays "structure" but hp = 0, and `w.map.bridge_state="ruined"`.
  - Units on those cells: `nearest_free_cell` within 3 tiles, else `w.destroy` (cause "drowned").
  - Call `Movement.on_terrain_changed(w)` and emit `BridgeDestroyed {cells}`.
  - Explicit attacks on a ruined bridge: combat's `_valid_target` should treat a ruined structure as invalid. You may edit that one line in combat.gd: if `state == "ruined"` return null.
  - Add `on_repaired(w, e)`: restore the cells to BRIDGE, hp = max, `state = "intact"`, call `on_terrain_changed`, and emit `BridgeRepaired`. Agent B2's repair system calls it.
- **Tests** (`tests/test_ops.gd`):
  - An officer with 6 riflemen and `secure_point` at the bridge reaches phase "hold" with progress 1.0 and emits ≥3 OfficerReports with reasons.
  - Withdraw triggers when you kill members past a low risk bound.
  - A player override detaches a member (the officer doesn't move it for override_ticks).
  - Officer death dissolves the group.
  - Patrol loops between 2 points (visits each ≥2 times).
  - Guard follows a moving unit.
  - Formation slots differ between line and column.
  - QA-007: destroy the bridge (set hp low, then one attack), and a vehicle ordered across now paths via a ford (path contains no ex-bridge cells and it arrives). No unit is ever in a WATER cell.
  - Repair: call `Bridges.on_repaired` and a path over the bridge works again.
  - Save round trip with an active mission and a ruined bridge gives an equal hash after 300 ticks, and the terrain is still ruined after load.

Done when `--only=test_ops` and the full suite are green (expected test_art failures for new defs belong to E2; quote them).
