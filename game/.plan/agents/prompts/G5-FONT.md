# G5-FONT: operating guide
Read `.plan/agents/prompts/G5_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G5 §1, §5. **Plan:** Plan section 7 (typeface, D19).
**Board / bus id:** `FONT`. **Budget: MAX_TOKENS 400000, MAX_TOOL_CALLS 100** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g5/test_font.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### FONT: the game's own typeface
- **Role:** design and build an original military-modern typeface.
- **Owns:** `tools/font/**` (an outline-based builder that writes a TTF via fontTools), `assets/fonts/rts_mil_{bold,regular}.ttf`, `assets/fonts/specimen.png`.
- **Tasks:**
  1. Glyph design rules: angular stencil cuts, squared counters, clear 0/O and 1/l/I.
  2. Full Latin A–Z/a–z, digits, punctuation, symbols used in the UI (● × % + − / : arrows).
  3. Build the TTF in 2 weights, with kerning pairs for common pairs.
  4. A specimen sheet (UI sizes 12–48 px, light/dark backgrounds, numbers in tables). Post `fact font.specimen_ready`. **ORCH shows it to the owner for approval.**
  5. Apply the owner's fixes and post `fact font.final`.
- **Done-when:** both TTFs load in Godot; the specimen is approved; licence note: original work, no third-party outlines.
- **Budget:** 400k / 100.
- **Never:** copy or trace an existing font.
