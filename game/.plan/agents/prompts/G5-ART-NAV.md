# G5-ART-NAV: operating guide
Read `.plan/agents/prompts/G5_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G5 §1, §3.3, §8. **Plan:** Plan section 10 (art).
**Board / bus id:** `ART-NAV`. **Budget: MAX_TOKENS 600000, MAX_TOOL_CALLS 150** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g5/test_art_g5_naval.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### ART-NAV: ships and the coast
- **Owns:** `tools/art/g5_naval*.gd`, `assets/art/g5_naval/**`, `tests/test_art_g5_naval.gd`.
- **Tasks:**
  - 9 ships: wakes, bow spray, firing, sinking frames, wrecks;
  - Coastal Front decor (piers, cliffs-to-sea transitions, island details);
  - effects: shell splash, landing-ramp frames.
- **Done-when:** the art test green; every naval ID has art; crops saved.
- **Budget:** 600k / 150.
