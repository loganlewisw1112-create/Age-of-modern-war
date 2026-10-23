# B-mil: simulation military (Movement, Combat, Fog, Victory)
MAX_TOKENS 600000 | MAX_TOOL_CALLS 150 | model opus (pathing/steering/fog fairness need judgement)

You own `sim/systems/movement.gd`, `combat.gd`, `fog.gd`, `victory.gd`, `tests/test_mil.gd`.
Implement CONTRACTS.md section 5 exactly. Keep every public function the world and other agents call:
`Movement.rebuild_nav/on_footprint_changed/order_path/is_passable/nearest_free_cell/tick/validate_command/apply_command`,
`Fog.init_faction_fog/tick/is_visible/visible_enemies`, `Combat.tick/validate_command/apply_command`, `Victory.tick`.

Details and decisions:
- Nav: one AStarGrid2D per move class in `w.nav`. It is runtime-only: `rebuild_nav` must fully reconstruct it from the
  map plus building entities, because it is called after save/load. Use diagonals only if no obstacles. Paths are arrays of cell-centre
  Vector2s (drop the start cell). Cap new path computations per tick (e.g. 40) and queue the rest
  deterministically. Store that pending queue in `w.sys_state.movement` so it survives a save. Group moves share a goal grid.
- Building footprints are solid for both classes. Units standing inside a newly placed footprint should be
  nudged out to `nearest_free_cell`.
- Steering: avoid jitter. Use separation via a spatial hash in `w.cache` (rebuilt each tick), and push only along passable
  directions. Never leave a unit inside an impassable cell (assert this in tests by scanning all units after a long run).
- Combat target choice is deterministic (nearest; ties go to the lower id). Weapons come from Content.weapon(unit.weapon). Building
  weapons (guard_tower) fire only if `built`. Small random dispersion uses `w.rng` only. An explicit `attack` on an
  unseen target is rejected with the reason "Target not visible.". Engineers only return fire (document this in a comment).
- Performance target: 256 mixed units fighting at <= 4 ms average tick on this machine. Measure it by timing `w.step()` in a
  test and printing the number. Don't fail tests on timing.
- Fog: visible is recomputed every 4 ticks from all own units + buildings (`sight` from content). Explored is sticky. Keep
  memory of enemy buildings (last-seen). `visible_enemies(w,fid)` returns entity dicts (units AND buildings) on visible
  cells only. Replace the stub's all-visible behaviour: the initial state has only the own sight circles visible/explored.
- Victory: CONTRACTS section 5. Emit `SideEliminated {faction}` and `MatchEnded {winner, reason}` once each.
- Required tests (tests/test_mil.gd):
  - MIL-01: a group move of 8 riflemen across the bridge arrives (all within 3 tiles of the goal), and no unit ever stands in an impassable cell.
  - Vehicles path around forests (never in a FOREST cell).
  - Dead units are removed and never act again.
  - Armor table: rifle vs MBT does <= 5% of rifle-vs-infantry damage.
  - AI-02 core: enemy units in non-visible cells are not in visible_enemies, and an attack order on them is rejected.
  - Explored stays set after units leave.
  - HQ destruction ends the match with the correct winner. Endless does not end.
  - A `to_dict/from_dict` save/restore mid-fight keeps hashes equal after 200 more ticks (proves the nav rebuild + pending path queue).

Spawn test units with `w.spawn_unit` directly. Clear the area near test positions of other sides' units if needed.
