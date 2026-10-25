# G5-UNITS5: operating guide
Read `.plan/agents/prompts/G5_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G5 §1-§6, §9. **Plan:** Plan section 5 (Workstream D).
**Board / bus id:** `UNITS5`. **Budget: MAX_TOKENS 700000, MAX_TOOL_CALLS 170** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g5/test_units_g5.gd`, `tests/pending_g5/test_drone_team.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### UNITS5: 17 new ground units and the Drone Team
- **Role:** every new human ground unit's sim behaviour, plus the burnt-ground save fix.
- **Owns:**
  - `content/g5/units_g5.json`;
  - `sim/systems/g5_mech.gd` (new: Drone Team, HMG deploy, Special Forces concealment/charges, Grenadier/Shock bonuses, ambulance carry slots);
  - `sim/systems/g4b_mech.gd` (burnt cells become a saved, hashed sim set);
  - `tests/test_units_g5.gd`, `tests/test_drone_team.gd`.
- **Inputs:** plan §5, contract §UNITS; `core.hot_api_ready`; the transport API for ambulance slots.
- **Tasks:**
  1. Content for all 16 human units and the Machine Maintenance Swarm (stats, weapons, armor, production links, stage gates).
  2. **Drone Team:**
     - one squad entity of 3;
     - `launch_drone {type, target}` command;
     - 4 charges;
     - 4 drone types as short-lived `air_low` entities (strike dive, frag, recon reveal/mark, EMP/jam), shootable by AA and jammable by EW;
     - auto-switch to **tactical mode** at 0 charges (infiltrate, takedown, breach, stack-up, armored attack);
     - restock at a supply source returns it to drone mode.
  3. HMG deploy/pack, Special Forces concealment + charges + air-drop flag, Grenadier/Shock bonuses, Mobile AA targeting `air_high`.
  4. Burnt cells as sim state, kept through save/load.
- **Publishes:** `units5.api_ready` (commands: `launch_drone`, `tactical_*`, `deploy`/`pack`).
- **Done-when:**
  - tests green: each unit's special, drone launch per type, the 4 → tactical switch, restock back to drone mode, burnt ground saved and reloaded;
  - full suite green.
- **Budget:** 700k / 170.
- **Never:** write the wounded/medical logic (SUPPORT) or the art.
