# PERF10K: 10,000 units within budget
Read G4_COMMON.md first. Contract: CONTRACTS_G4 §0, §1. Background: `perf/PERF_REPORT_G3b_2026-10-24.md` and handoffs `.plan/handoff/N1-core-4.json`, `PERF4-4.json`.
Quiet-machine baseline: 10k valley avg 86.7 / p95 124 ms; movement gather ≈3.7 µs/unit in GDScript; victory/territory spikes.
**Owns:** `sim/systems/tiers.gd`, `sim_index.gd`, `territory.gd`, `fog.gd`, `supply.gd`, `morale.gd`, `tools/scale_bench.gd`, `tests/test_perf.gd`. Movement/native changes only after NAT posts `done` (then you own `movement.gd`, `native/**`, `bin/**`; announce it on the board).

Tasks:
1. Add a **10k all-fighting** scenario to scale_bench (the armies meet; not all REDUCED).
2. **Native-held positions + moving flags**, synced only on change: only units that changed are touched in GDScript per tick. Writers outside movement (bridges rescue, spawns, transport unload, tests) go through one API.
3. Spread the tier-recompute decision loops across ticks, save-exact.
4. Incremental territory occupancy; check the victory spikes with MAPIO (victory.gd is theirs: send a CR).
5. Keep results identical (hash-equal A/B against HEAD) or prove equivalence by test.
6. Report a before/after table for 2k rc_s fighting, 10k valley marching, and 10k valley fighting.

**Target:** 10k p95 < 50 ms, or as close as you get, with honest numbers.
Done when: tasks 1-6 are done and the full suite is green. MAX_TOKENS 700000, MAX_TOOL_CALLS 170, board id `PERF10K`.
