# G5-AI6-AN: operating guide
Read `.plan/agents/prompts/G5_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G5 §1, §4, §5, §7, §8. **Plan:** Plan section 8 (Workstream G).
**Board / bus id:** `AI6-AN`. **Budget: MAX_TOKENS 900000, MAX_TOOL_CALLS 220** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g5/test_ai_air_naval.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### AI6-AN: air and naval AI
- **Owns:** `sim/ai/ai_air.gd`, `sim/ai/ai_naval.gd`, `tests/test_ai_air_naval.gd`.
- **Inputs:** `air.api_ready`, `naval.api_ready`, `map.coastal_front_ready`.
- **Tasks:**
  1. **Air:** pick an airfield site, buy then upgrade hangars, assign engineers, AA cover, air assaults (gunship/VTOL lands troops + vehicles behind lines), helicopters landing in the field, jet strikes on clusters/artillery, bombing enemy airfields, AA on contact.
  2. **Naval:** a shipyard on water maps, contest the water, bombardment, amphibious landings when the land route is blocked or long.
  3. Hand soak requests to AI6's soak lane via the board.
- **Done-when:** test_ai_air_naval green; AI6's soaks show sorties on every map and at least 1 amphibious landing on Coastal Front; think time stays under budget.
- **Budget:** 900k / 220.
