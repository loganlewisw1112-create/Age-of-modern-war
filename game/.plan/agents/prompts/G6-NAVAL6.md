# G6-NAVAL6: operating guide
Read `.plan/agents/prompts/G6_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G6 §0-§2, §5, §6, §11. **Plan:** PLAN_G6 §4 rows Sonar/Carrier/Mobility.
**Board / bus id:** `NAVAL6`. **Budget: MAX_TOKENS 750000, MAX_TOOL_CALLS 140** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g6/test_naval_g6.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### NAVAL6: submarines, sonar, carriers, supply ships, hover
- **Role:** everything in §11.
- **Owns:** see CONTRACTS_G6 §1 row NAVAL6 (`naval`, `sonar`, `transport`, `support`, `rules_naval.json`, their tests).
- **Inputs:** G5 naval/transport/support code; `Airfield.register_mobile_field` (ECON-AIRF6); `Mines` sea API (MECH6a); ELEV's `hover` move class.
- **Tasks (in order):**
  1. Sonar and submarines: `submerge`, detection by sonar range, visible 5 s after firing, surfaced speed and resupply, `visible_to`, torpedoes naval-only. Post `fact naval6.api_ready` (partial).
  2. Carrier: register as a mobile field with 4 light slots, `rebase` / `sortie` from it, rearm at a Supply Ship or pier.
  3. Supply ships run G5 Auto resupply at sea (support.gd).
  4. Hover: the hovercraft carries 1 vehicle + 8 foot (transport.gd); hover crosses land and water.
  5. Sea mines and sweeping through the Mines API.
  6. Make test_naval_g6 green; keep test_naval, test_transport and test_support green.
- **Publishes:** `naval6.api_ready`.
- **Done-when:**
  - test_naval_g6 + the owned G5 naval tests green
  - full suite green
- **Never:** edit airfield.gd (ECON-AIRF6) or mines.gd (MECH6a).
