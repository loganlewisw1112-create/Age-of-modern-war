# G6-MECH6a: operating guide
Read `.plan/agents/prompts/G6_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G6 §0-§2, §5, §6, §9 (mines, clearing, garrison, fieldworks, rail). **Plan:** PLAN_G6 §4.
**Board / bus id:** `MECH6a`. **Budget: MAX_TOKENS 750000, MAX_TOOL_CALLS 140** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g6/test_mines.gd`, `tests/pending_g6/test_garrison.gd`, `tests/pending_g6/test_fieldworks.gd`, `tests/pending_g6/test_rail.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### MECH6a: mines, garrisons, fieldworks, rail
- **Role:** the ground-warfare systems in §9 except call-ins, auras and mobility (MECH6c).
- **Owns:** see CONTRACTS_G6 §1 row MECH6a (`mines`, `garrison`, `fieldworks`, `rail` + `fortify`, `construction`, `g4b_mech`, `rules_ground.json`, their tests).
- **Inputs:** G4 mines in `g4b_mech.gd` (mine entity, seen, triggers), `fortify.gd` `build_line`, `construction.gd`; ELEV's RAIL tile + `rail` move class; CONTENT6 def flags.
- **Tasks (in order):**
  1. Minefields: `lay_minefield` over a rect (≤ 8×8, seeded pattern of G4 mine entities with `mine_kind`), owner-visible boundary, AT vs AP triggers; `sweep`, `line_charge`; EOD/recon detection; the sea-mine API for NAVAL6 (`Mines.lay_sea(w, owner, cell)`, `Mines.sweep_cells(w, fid, cells)`). Post `fact mech_a.api_ready` (partial).
  2. Garrison: `garrison` / `ungarrison`, slots, fire from the building, `protect_mult` 0.5, hidden until firing (`visible_to`), eject/kill on building death, `anti_garrison`.
  3. Fieldworks: infantry-buildable sandbags and trench through `build_line` (`field_buildable` in construction), `cover_mult`, tank traps `passable` for foot only, wire `wire_mult` + clearing, camo (`camo_visible`) and decoys (AI target weight flag).
  4. Rail: `build_rail` lays RAIL tiles from a Rail Yard; the armored train moves only on rail; a destroyed tile cuts the line until repaired.
  5. Make the four acceptance files green; keep test_fort and test_units_g4b green. Post `mech_a.api_ready` (complete).
- **Publishes:** `mech_a.api_ready`.
- **Done-when:**
  - test_mines, test_garrison, test_fieldworks, test_rail green
  - test_fort + test_units_g4b green
  - full suite green
- **Never:** edit combat/fog/movement (hooks are wired by PERF6; ask through a CR), or write call-ins, auras or mobility (MECH6c).
