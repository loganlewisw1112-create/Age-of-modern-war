# G5-ART-AIR: operating guide
Read `.plan/agents/prompts/G5_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G5 §1, §3.2, §7. **Plan:** Plan section 10 (art).
**Board / bus id:** `ART-AIR`. **Budget: MAX_TOKENS 850000, MAX_TOOL_CALLS 170** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g5/test_art_g5_air.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### ART-AIR: aircraft
- **Owns:** `tools/art/g5_air*.gd`, `assets/art/g5_air/**`, `tests/test_art_g5_air.gd`.
- **Tasks:**
  - 12 aircraft;
  - rotor/jet animations;
  - a ground shadow plus altitude offset;
  - landing-gear frames for taxi/landing;
  - a sling-load pose;
  - VTOL hover/landing frames for both versions;
  - wrecks;
  - effects: bombs, missile trails, smoke.
- **Done-when:** the art test green; every air ID has art; crops saved.
- **Budget:** 600k / 150.
