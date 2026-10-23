# Q2-qa: G2 cross-system scenario tests + soak invariants + bench
MAX_TOKENS 500000 | MAX_TOOL_CALLS 130 | model sonnet (bounded test spec)

You own `tests/test_g2_scenarios.gd`, `tools/soak.gd` (extend the invariants only; keep its output format), `tools/bench.gd` (extend only), and `perf/**`. Read `docs/CONTRACTS_G2.md` (all of it) and each G2 system header (`sim/systems/damage.gd`, `morale.gd`, `supply.gd`, `repair.gd`, `ops.gd`, `ops_missions.gd`, `orders.gd`, `bridges.gd`, `status.gd`) before writing tests. Agents A2 (damage) and G2-ai (AI) may still be editing their files. Your tests target the documented contract and must not depend on AI behaviour (use `make_world()`, which gives an inert side 1, and spawn units directly).

Scenario tests (`tests/test_g2_scenarios.gd`). Each one crosses at least two systems:
1. **MIL-02 / QA-008 combined:** an MBT loses mobility from AT fire, still kills an IFV in range, and is then repaired by engineers. It moves again and the salvage spent matches the repair rule.
2. **QA-007 + supply:** the bridge is destroyed while a logistics truck is mid-crossing (it is nudged ashore or killed, never left in water). The route then goes via a ford, and fuel is consumed along the longer route.
3. **Officer + supply:** a secure_point mission with low ammo enters the "resupply" phase, refills at a depot (ledger journal shows the resupply spends), and returns to the objective.
4. **Morale + officer:** killing the officer dissolves the group, and members lose morale. Further losses break a unit, which retreats, then rallies.
5. **Conservation under everything:**
   - Run a 3000-tick scripted brawl (two armies, refinery running, repairs, resupply, bridge destroyed mid-way).
   - Then assert, for every faction and ledger key, that the sum of the journal deltas equals the final stock minus the start stock.
   - Assert no negative stock, no unit inside WATER/RIDGE cells, and no duplicate ids.
6. **Save/load in the middle of 5:** at tick 1500, save via `sim/save_system.gd` to `user://test_g2/…` and continue in both worlds. The state_hash must be equal at 3000 (SAVE-01 with G2 state).
7. **Determinism:** two runs of 5 give an equal hash.

Soak invariants (`tools/soak.gd`), checked every 600 ticks:
- ammo/fuel ≥ 0 on every unit;
- faction fuel/ammo stock ≥ 0;
- journal conservation for all 5 ledger keys;
- no unit inside WATER after a bridge collapse;
- every officer group's members exist and belong to the officer's owner.

Print `INVARIANT FAIL …` on violation, as in G1.

Bench (`tools/bench.gd`): add a `--g2` scenario variant that includes officers with missions, forest cover and logistics trucks. Write `perf/BENCH_G2_<date>.md` with the 64/128/256/512 table (wrap in hb.sh). The orchestrator compares this with G1: 3.2 / 5.2 / 11.9 / 75.3 ms avg.

Done when `bash tests/run.sh --only=test_g2_scenarios` is green, the full suite is green (quote other agents' failures), and one soak plus the bench ran with output pasted raw.
