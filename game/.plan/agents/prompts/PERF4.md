# PERF4: fidelity tiers + native combat + per-system costs (wave 2)
Read G3B_COMMON.md first. Your files: `sim/systems/combat.gd`, `supply.gd`, `morale.gd`, `fog.gd`, `economy.gd` (after STG4's counter edits; keep them), plus `tests/test_perf.gd`. Coordinate with N1-core's successor if movement.gd needs changes (CHANGE_REQUEST).

Target (Done-when #3, this PC): **2,000 FULL fighting units with total tick p95 < 50 ms; 10,000 units on `valley_conquest_l` with total tick within budget**, measured with `tools/scale_bench.gd` (N1's). Report native on/off.

Order:
1. Baseline with scale_bench at 1k/2k/5k/10k; per-system breakdown (time each system in SYSTEM_ORDER plus AI).
2. Combat: target acquisition through `RtsGrid` (native) via `sim/native_core.gd`, with a GDScript fallback. Stagger scans by tier. Keep the damage/armor/facing/cover/suppression/EW rules identical.
3. **Fidelity tiers** (CONTRACTS_G3b §0):
   - FULL: any enemy within the contact radius (e.g. 14 tiles, from the spatial grid).
   - REDUCED: no contact. Moves on a stride (every 4th tick with a 4x step; collision rules still hold), with no target scan except every 8 ticks, and staggered supply/morale/fog updates.
   - Promote to FULL immediately on contact.
   - Tiers are a pure function of sim state (never the camera), so determinism holds. Expose `w.tier_counts()` for the perf report.
4. Make supply, morale, fog and economy loops tier-aware or staggered. Fog at 256×256: incremental stamping of only moved units.
5. tests/test_perf.gd: tier promotion on contact; no resource or ammo duplication across tier changes; determinism with tiers; results match FULL-only for a small fight (same winner, similar losses).
6. Publish the scale_bench tables (1k/2k/5k/10k) in your report.
MAX_TOKENS 700000, MAX_TOOL_CALLS 170, board id `PERF4`.

## State when you start (orchestrator)
- STG4 is done and committed: its combat.gd diff (lines marked "G3b STG4": guided, Status.damage_mult) and its economy.gd counters (`power_ok_ticks`, `ore_refined`) must be kept. `Status.ew_tick` loops EW units × all units every 10 ticks in GDScript; make it use the grid too.
- N1-core is still finishing `tools/scale_bench.gd` and owns `movement.gd` + `sim/native_core.gd` + `native/**`. The facade and `RtsGrid` exist and pass tests; read `sim/native_core.gd` for the real API. If you need a new native function (e.g. a batched nearest-enemy with team masks and range per unit), post a CHANGE_REQUEST to N1-core on the board. Do not edit native/** yourself while N1-core is live; check the board for its `done`.
- If scale_bench.gd is not there yet, write your own harness at `tools/perf_tiers.gd` and switch to scale_bench when it lands.
