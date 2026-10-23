# A-econ: simulation economy (Economy, Construction, Production, Gather)
MAX_TOKENS 600000 | MAX_TOOL_CALLS 150 | model sonnet (bounded spec, clear contract)

You own `sim/systems/economy.gd`, `construction.gd`, `production.gd`, `gather.gd`, `tests/test_econ.gd`.
Implement CONTRACTS.md section 4 exactly. Replace the stubs fully, keeping the function signatures the world calls:
`tick`, `validate_command`, `apply_command`, and `Construction.placement_error`.

Details and decisions:
- Agent B is replacing `sim/systems/movement.gd` concurrently. Right now its stub follows `e.path` in a straight line.
  Use ONLY the contract helpers `Movement.order_path(w, e, goal)`, `Movement.is_passable` and `Movement.nearest_free_cell`
  (preload `res://sim/systems/movement.gd`). Your tests must pass with both the stub and real pathing. Use generous
  tick budgets and assert outcomes (delivered amounts, building completed), not exact positions or timings.
- Engineers building: move each to the nearest passable cell adjacent to the footprint (`nearest_free_cell`). They
  contribute only while within 1.0 tile of the footprint's edge. Several engineers stack (sum of build_power).
- Gather arrival: an engineer harvests when within 1.2 tiles of the resource pos, and delivers when within (size*0.5 + 1.2)
  of the drop building's pos. Use integer harvest accounting: accumulate fractional progress in `e.gather_acc` and
  transfer whole units only.
- Fog dependency for placement: use `w.fog[fid].explored` (PackedByteArray, idx y*w+x). Fog is currently
  all-explored (stub). Write a test that manually zeroes a cell's explored flag to prove the rule.
- Production spawn: place squad members on free passable cells around the building edge nearest the rally point,
  spaced >= 0.7 tiles apart (deterministic order). Increment `stats.trained` per unit.
- Emit these events: `ConstructionStarted {building_id, def, owner}`, `ConstructionCompleted`, `ProductionQueued`,
  `ProductionCompleted {building_id, item, unit_ids}`, `ProductionBlocked {building_id, reason}` (only when the status
  changes, not every tick), `ResourceDepleted`, `Delivered {unit_id, res, amt}`.
- Economy.tick recomputes power and pop at the start of each tick. Production reads them.
- Required tests (tests/test_econ.gd, `extends "res://tests/test_base.gd"`):
  - ECON-01: double spend is impossible. Two queue commands in the same tick when only one is affordable: exactly one succeeds.
  - Journal conservation: the sum of journal deltas equals the final minus initial balance, per resource.
  - Harvest conservation: the resource amount removed equals delivered + carried.
  - ECON-02: a LOW_POWER stall shows its status reason. Then build a generator and see recovery, with exactly one unit produced per paid item.
  - SUPPLY_CAP block.
  - cancel_unit gives an exact refund. cancel_building follows the refund rule.
  - BUILD-01: placement errors (overlap, water, unexplored, missing prereq, too far), each with a distinct reason.
  - Full happy path: engineers build a barracks, then queue rifle_squad, and 4 riflemen spawn with a shared squad id.
