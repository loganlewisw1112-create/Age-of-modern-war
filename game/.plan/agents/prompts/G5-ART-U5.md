# G5-ART-U5: operating guide
Read `.plan/agents/prompts/G5_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G5 §1, §3.1. **Plan:** Plan section 10 (art).
**Board / bus id:** `ART-U5`. **Budget: MAX_TOKENS 850000, MAX_TOOL_CALLS 170** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g5/test_art_g5_units.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### ART-U5: ground units and launched drones
- **Owns:** `tools/art/g5_units*.gd`, `assets/art/g5_units/**`, `tests/test_art_g5_units.gd`.
- **Tasks:**
  - sheets for all 17 new ground units: 8 facings; idle/move/fire; specials (deploy, launch, carry wounded, wounded pose, tactical stance); team masks; wrecks; icons;
  - the 4 drone types × 2 factions (Human A precision, Human B rigged) with dive/trail frames;
  - faction styles kept;
  - self-check every sheet by viewing zoomed crops; manifest entries with `lod_class`.
- **Done-when:** the art test green; every ID in `units_g5.json` has art; zoomed crops saved in `.plan/shots/ART-U5/`.
- **Budget:** 600k / 150.
