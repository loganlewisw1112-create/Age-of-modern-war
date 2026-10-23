# A2-damage: G2 damage pipeline, cover, components, suppression/morale, LOS, concealment
MAX_TOKENS 600000 | MAX_TOOL_CALLS 150 | model opus (combat feel + determinism judgement)

You own `sim/systems/damage.gd`, `sim/systems/morale.gd`, `tests/test_damage.gd`. You may also edit:
- `sim/systems/fog.gd`, for concealment only;
- `sim/systems/combat.gd`, beyond the ORCH hooks already wired (`Status.can_fire`, `Damage.line_clear`, accuracy mult, `Damage.apply_hit`).

Implement CONTRACTS_G2.md section 2 exactly. Read section 1 (status.gd) first; it reads the fields you set.

Key decisions (provisional numbers come from content/rules.json):
- `apply_hit` is called for every shot. On a hit, damage = base_damage x facing mult (vehicles) x cover mult (infantry in cover), quantized to 1/1024. Component rolls (vehicles), suppression and morale effects follow. On a miss, only near-miss suppression applies, and only to infantry within 1.5 tiles of the intended target.
- Keep the G1 hp quantization and `last_attacker`/`last_hit_tick` fields. Every random draw uses `w.rng`, in a fixed order, to stay deterministic.
- `ComponentDisabled` fires once per component per disable. Repaired components (agent B2) can be disabled again later.
- Morale (`morale.gd` tick, in SYSTEM_ORDER after Combat):
  - Update `in_cover` every 4 ticks; it is cheap.
  - Decay suppression per second. `pinned` from the threshold.
  - Squadmate deaths reduce morale for living units sharing `squad` within 8 tiles. Watch `EntityDestroyed` events in `w.events`.
  - Break: order `{"type":"retreat"}`, path home with `Movement.order_path` (preload movement), emit `UnitBroken`. Combat must not auto-acquire for broken units; `Status.can_fire` already blocks firing.
  - Rally when morale >= `rally_at`: idle, emit `UnitRallied`.
  - Engineers and officers have morale too. Vehicles have no morale.
- `line_clear`: supercover/DDA line over cells. Any RIDGE cell blocks. Buildings do not block in G2.
- Concealment (`fog.gd`): an infantry unit standing on FOREST is excluded from `visible_enemies(fid)` and `entity_visible` when no fid unit/building is within `rules.concealment_range` of it, unless `w.tick - e.get("last_fired_tick", -9999) < 60`. Set `last_fired_tick` in `combat._fire`, which you may edit. Keep fog cheap: do the check in the query, not in the stamp.
- Performance: `bench.gd` at 256 units must stay under 15 ms avg/tick (G1 was 11.9). Measure with `"$G" --headless --path . -s tools/bench.gd` (wrap in hb.sh) and report the numbers.

Required tests (`tests/test_damage.gd`):
- A rear hit on an MBT does more damage than a front hit (same shooter, same rng seed path).
- An infantry target in forest takes less small-arms damage than one in the open.
- MIL-02/QA-008: a vehicle whose mobility is disabled cannot move (stays put over 100 ticks of a move order) but still fires and kills a target in range. A vehicle whose weapon is disabled never fires.
- Sustained fire pins infantry (`pinned=true`, slower), and the unit recovers after fire stops.
- Squad casualties can break a unit: it retreats toward HQ, then rallies.
- A shot across a ridge is blocked (no ShotFired).
- A concealed forest unit is not in `visible_enemies` beyond `concealment_range`, but is after it fires.
- Determinism: two identical 600-tick fights have an equal `state_hash`.
- Save round trip: `bytes_to_var(var_to_bytes(to_dict()))` mid-fight, then 200 more ticks, gives an equal hash.

Done when `bash tests/run.sh --only=test_damage` and the full `bash tests/run.sh` are green (test_art failures for new defs belong to E2 and are expected until it lands; quote them) and the bench numbers are reported.
