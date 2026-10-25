# G6-ART-G6: operating guide
Read `.plan/agents/prompts/G6_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G6 §0-§2, §5, §6, §3, §1 (art). **Plan:** PLAN_G6 §3.
**Board / bus id:** `ART-G6`. **Budget: MAX_TOKENS 750000, MAX_TOOL_CALLS 140** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g6/test_art_g6.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### ART-G6: integrate the art kit into the game
- **Role:** move the 89 kit drawers into the game art pipeline as `assets/art/g6_units` + `assets/art/g6_bld`, with buildings at all 4 rotations plus damaged and build stages.
- **Owns:** see CONTRACTS_G6 §1 row ART-G6 (`tools/art/g6_*.gd` except `g6_terrain*`, `tools/art/g6_art_gen.gd`, `assets/art/g6_units/**`, `assets/art/g6_bld/**`, `tests/test_art_g6.gd`).
- **Inputs:** `docs/g6_art_kit/` (drawers in `gd/`, notes, README; run its `run.sh` for reference renders, output git-ignored); the G5 modules as the structure model (`tools/art/g5_units*.gd`, `g5_units_gen.gd`, `g5_bld*.gd`, `g5_bld_gen.gd`).
- **Tasks (in order):**
  1. Port the kit drawers (drop every `x_*` id) into `tools/art/g6_*.gd` modules + `tools/art/g6_art_gen.gd` (SceneTree runner like g5_units_gen) that writes `assets/art/g6_units/` (units, squads, wrecks, icons, manifest.json) and `assets/art/g6_bld/` (buildings with states built / damaged / build_0..2 for rotations 0-3, like g5_bld).
  2. Icons for every id (G5 icon helpers).
  3. Polish from the art pass: hovercraft cargo contrast, supply-ship crane load, fuel-tender smoke. `b_conscripts` keeps its 64×44 squad frame: FOUND-line it for VIEW6.
  4. Post `fact art.g6_units_ready` / `art.g6_bld_ready`. CR VIEW6 to load the g6 groups in ArtCatalog.
  5. Make test_art_g6 green except `new_pieces_*` (ART-G6b's). Self-check each sheet by eye at 8 facings (Read the PNGs).
- **Publishes:** `art.g6_units_ready`, `art.g6_bld_ready`.
- **Done-when:**
  - test_art_g6 green (except new_pieces, which ART-G6b owns)
  - the manifest covers every §3.1 id
  - full suite green
- **Never:** draw terrain (ELEV-VIEW), edit presentation code, or run concurrently with ART-G6b.
