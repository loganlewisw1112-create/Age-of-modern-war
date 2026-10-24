# TRANS: transport system (all carriers: land now, air/sea later)
Read G4_COMMON.md first. Contract: CONTRACTS_G4 §0, §1, §2.1, **§7** (yours; the rules block `rules.transport` already exists).
**Owns:** `sim/systems/transport.gd`, `sim/systems/ops.gd` + `ops_missions.gd` (cargo-aware prune + a "transport to point" officer mission), `sim/systems/economy.gd` (pop counts cargo; keep every PERF/STG change), `content/g4/transport.json`, `tests/test_transport.gd`.
**Carrier units:** `a_apc` and `b_halftrack` are defined by UNITS in `units_g4b.json`. You define the cargo fields contract and add `cargo_slots`/`cargo_accepts` to UNITS' defs via a CR, or put carrier fields on existing defs only through your own fragment if a future carrier is yours. Also give `b_carrier` (existing Armored Carrier) transport capacity: it's a base content def, so post a CR to ORCH with the exact fields.
**Downstream:** UI4B (cargo panel), AI5, G4c/G4d later. Post `fact trans.api_ready` early.

Tasks:
1. **Commands** `load`, `unload`, `unload_all` (§7):
   - units path to the carrier, or the carrier paths to them (use the Movement API);
   - capacity check by `cargo_size`/`cargo_class`;
   - loaded dicts move into `carrier.cargo` (ascending id) and leave `w.entities`;
   - `w.cache.cargo_of` rebuilt on load;
   - events `UnitLoaded`/`UnitUnloaded`.
2. **Unload:** reinsert at free passable cells around the target, deterministically ordered; the same ids are kept.
3. **Carrier destroyed:** apply the `rules.transport.on_destroyed` rules through the normal destroy path (ground ejects at 50% hp; air/naval rules for later carriers). Ledger and pop stay consistent.
4. **Keep systems consistent:**
   - economy pop includes cargo;
   - Ops.prune keeps group members that are in cargo;
   - fog/tiers/sim_index never see cargo, because cargo is not in entities;
   - Victory: a side with only cargo units left is still alive.
5. **Officer mission** "transport to point": load the group, move, unload, then secure.
6. **Tests:** load/unload, capacity, carrier death (eject/kill), pop/ledger consistency, save mid-transport (same hash), the officer mission, determinism.
Done when: tasks 1-6 are green and the full suite is green. MAX_TOKENS 600000, MAX_TOOL_CALLS 150, board id `TRANS`.
