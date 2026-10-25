# G5-AIRSYS: operating guide
Read `.plan/agents/prompts/G5_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G5 §1-§7. **Plan:** Plan section 3 (Workstream B).
**Board / bus id:** `AIRSYS`. **Budget: MAX_TOKENS 900000, MAX_TOOL_CALLS 220** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g5/test_air.gd`, `tests/pending_g5/test_airfield.gd`, `tests/pending_g5/test_air_transport.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### AIRSYS: airfields, hangars, flight model, air transport
- **Role:** the whole air sim.
- **Owns:**
  - `sim/systems/air.gd` (flight: hover, sorties, holding, fuel/ammo return, air-vs-air targeting);
  - `sim/systems/airfield.gd` (strips, hangars, upgrades, runway queue, craters, diverts, engineer assignment hooks);
  - `sim/systems/transport.gd` (adds sling, `cargo_size` and mixed cargo for the VTOL);
  - `content/g5/air.json`;
  - `tests/test_air.gd`, `tests/test_airfield.gd`, `tests/test_air_transport.gd`.
- **Inputs:** plan §3, contract §AIR, `core.hot_api_ready`.
- **Tasks:**
  1. Content for every air unit and air building with fixed IDs (Human A/B/Machine), including the Airstrip variant and the Drone Launch Rail/Bays.
  2. Hangar gating: production of an aircraft fails with `no_free_hangar` unless a free hangar of the right class exists. Post `fact air.gating_ready`.
  3. Runway ops:
     - deterministic taxi → roll → airborne;
     - approach → touchdown → taxi → hangar;
     - one aircraft per strip;
     - a holding-pattern queue with low-fuel priority.
  4. Sorties, rearm/refuel timed by hangar level. Helicopters `land_at` any open ground (landing-zone check). Helipad service (rearm/refuel/repair) is automatic with assigned engineers; low helicopters return to the nearest free friendly pad.
  5. Craters close a strip; `Airfield.repair_crater` is the engineer API; diverts and crashes when no field is left; a destroyed hangar kills the aircraft parked in it.
  6. Air transport: troops, sling vehicles, VTOL 2 vehicles + 8 troops, and landing-zone validation.
  7. `air_low`/`air_high` targeting rules plus the `anti_air_low` flag.
  8. Save/load mid-flight and mid-holding.
- **Publishes:** `air.api_ready` (commands: `build_hangar`, `upgrade_hangar`, `upgrade_airfield_strip`, `sortie`, `rebase`, `land_at`, `assign_engineers`), `air.gating_ready`.
- **Done-when:** the 3 test files green (sortie cycle, holding, craters + repair, gating, VTOL cargo, air-vs-air, save mid-flight) and the full suite green.
- **Budget:** 900k / 220.
- **Never:** touch `movement.gd`; ground units keep their nav. Aircraft use their own flight model in `air.gd`.
