# G5-ART-BLD: operating guide
Read `.plan/agents/prompts/G5_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G5 §1, §3.4, §3.5. **Plan:** Plan section 10 (art).
**Board / bus id:** `ART-BLD`. **Budget: MAX_TOKENS 850000, MAX_TOOL_CALLS 170** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g5/test_art_g5_bld.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### ART-BLD: all new buildings and command icons
- **Owns:** `tools/art/g5_bld*.gd`, `assets/art/g5_bld/**`, `tests/test_art_g5_bld.gd`.
- **Tasks:**
  - airfield (4 rotations, 1–4 strips, crater overlays);
  - Light/Heavy hangars with 3 upgrade looks;
  - helipad, control tower, Forward Airstrip, Airstrip variant;
  - Machine Launch Rail + Drone Bays;
  - shipyard (shore art), Supply Pier, Coastal Battery × 3 factions;
  - Hospital and Field Hospital × 2 human factions;
  - damaged states;
  - icons for every new unit, building and command.
- **Done-when:** the art test green; every new building ID has art; crops saved.
- **Budget:** 600k / 150.
