# B2-supply: G2 supply (ammo/fuel), refinery, repair
MAX_TOKENS 500000 | MAX_TOOL_CALLS 130 | model sonnet (bounded spec)

You own `sim/systems/supply.gd`, `sim/systems/repair.gd`, `sim/systems/economy.gd` (add the refinery), and `tests/test_supply.gd`.
Implement CONTRACTS_G2.md section 3 exactly. The world already has:
- `fuel`/`ammo` ledger keys and faction stock;
- unit fields `ammo`, `fuel`, `comp` set at spawn;
- `Supply.on_shot(w, e)` called once per shot by combat;
- the `repair` command routed to `repair.gd`;
- the bridge as a neutral `kind:"structure"` entity whose ruined state (agent C2) is `e.state == "ruined"`.

Details:
- `on_shot`: `e.ammo -= 1` (never below 0) for units that have `ammo`.
- Fuel: in `Supply.tick`, compare `e.pos` with `e.supply_prev_pos` (store it; first tick just stores) and subtract `distance * fuel_per_tile`, quantized to 1/1024, never below 0. Status.move_mult already stops a vehicle at 0 fuel.
- Resupply every 20 ticks (deterministic order: entity order):
  - Applies to units within `rules.supply.radius` of an own built HQ, an own built depot, or an own `logistics_truck`.
  - Each unit gets `min(missing, refill_per_second x 1 s)` of ammo and fuel, drawn with `w.spend(fid, {"ammo": n}, "resupply")`.
  - If the stock can't cover it, take what is available (spend exactly the stock left) and emit `SupplyShortage {faction, res}` at most once per 600 ticks per resource.
  - The logistics truck is a supply point only; it carries no cargo in G2 (abstracted, as allowed by the economy profile). Document that.
- Refinery (economy.gd): per built refinery while the faction power is sufficient, every `period_s`:
  - `w.spend(fid, {"ore": ore_in}, "refinery")`, then `w.credit(fid, {"fuel": fuel_out, "ammo": ammo_out}, "refinery")`.
  - Building `status` is "NO_ORE" or "LOW_POWER" when blocked, and "" when working.
  - Keep a per-building accumulator `e.refine_acc` (int ticks).
- Repair (`repair {unit_ids, target_id}`, engineers only):
  - Valid targets: an own unit with hp < max or a damaged component; an own building with hp < max (built); or the bridge structure in `state == "ruined"`.
  - Validation reasons: "Only engineers can repair.", "Nothing to repair.", "Not your unit.", "Target not visible.".
  - Engineers path adjacent (`Movement.order_path` plus the Construction approach helpers, preload construction.gd), with order `{"type":"repair","target_id":id}`.
  - While within 1.5 tiles (footprint distance for buildings), each engineer restores `hp_per_second` per second, paying `salvage_per_100hp` per 100 hp chunk via `w.spend` before restoring that chunk. Integer-safe accounting with an accumulator.
  - Components: restore the lowest disabled component to 50 first, then hp.
  - Bridge: total cost `buildings.json bridge_span.repair_salvage`, paid in 10 equal chunks, with progress `e.repair_progress` 0..1 over `repair_time` seconds for one engineer (several engineers stack). At 1.0, call `Bridges.on_repaired(w, e)`. Agent C2 implements that function; call it directly; the stub already defines it (no-op until C2 lands).
  - Out of salvage: emit `RepairBlocked` once and set the order to idle.
- Tests (`tests/test_supply.gd`):
  - Shots consume ammo, and a unit at 0 ammo can't fire (no ShotFired).
  - Resupply near the HQ refills and the journal shows matching ammo spends (conservation).
  - Driving consumes fuel, and a vehicle at 0 fuel stops; resupply lets it move again.
  - The refinery converts ore to fuel/ammo, and with no ore its status is NO_ORE.
  - Repairing a damaged MBT restores hp and the disabled mobility component and charges the right salvage.
  - Repair with 0 salvage is blocked with a reason.
  - Bridge repair calls `Bridges.on_repaired` (stub ok) and charges `repair_salvage`.
  - Save round trip mid-resupply gives an equal hash after 200 ticks.

Done when `--only=test_supply` and the full suite are green (expected test_art failures for new defs belong to E2; quote them).
