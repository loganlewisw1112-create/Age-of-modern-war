# G6-MECH6b: operating guide
Read `.plan/agents/prompts/G6_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G6 §0-§2, §5, §6, §10. **Plan:** PLAN_G6 §4.
**Board / bus id:** `MECH6b`. **Budget: MAX_TOKENS 750000, MAX_TOOL_CALLS 140** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g6/test_machine_g6.gd`, `tests/pending_g6/test_strikes.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### MECH6b: Machine specials and strikes
- **Role:** everything in §10.
- **Owns:** see CONTRACTS_G6 §1 row MECH6b (`machine_g6`, `strikes`, `rules_machine.json`, their tests).
- **Inputs:** the G5 drone entity pattern (`g5_mech.gd`, read-only), the G4 conceal pattern (`g4b_mech.gd`, read-only), the G4 gate (fortify, read-only), CONTENT6 defs.
- **Tasks (in order):**
  1. Self-repair: nanite wall, nanite forge, repair swarm II.
  2. `assimilate` + wreck registry (`on_destroyed`, `wrecks`); spawners (hive node to cap, swarm queen); mimic disguise (`disguise_for`), stalker `cloak` (`cloak_visible`), shield drone (`shield_mult`), relay lattice range chain, overmind unlock hook, phase gate team-only.
  3. Strikes: loitering munitions (6 per load), MLRS salvo, mass driver, cruise strike (cooldown, interceptable by Laser CIWS through AIRDEF6's API).
  4. Make both acceptance files green. Post `fact mech_b.api_ready`.
- **Publishes:** `mech_b.api_ready`.
- **Done-when:**
  - test_machine_g6 + test_strikes green
  - full suite green
- **Never:** edit g5_mech.gd, g4b_mech.gd or fortify.gd (CR their owners).
