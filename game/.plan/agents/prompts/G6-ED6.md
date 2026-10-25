# G6-ED6: operating guide
Read `.plan/agents/prompts/G6_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G6 §0-§2, §5, §6, §15 (Live), §7 (height in the editor). **Plan:** PLAN_G6 §8.
**Board / bus id:** `ED6`. **Budget: MAX_TOKENS 750000, MAX_TOOL_CALLS 140** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g6/test_editor_g6.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### ED6: editor Live mode, height brushes, G6 placements
- **Role:** Live mode (snapshot → combat + AI tactics → exact restore), height brushes with validation, and G6 placements in the editor.
- **Owns:** see CONTRACTS_G6 §1 row ED6 (`presentation/editor/**`, `presentation/main.gd`, `sim/editor_live.gd`, `triggers.gd`, scenarios, the editor tests).
- **Inputs:** `SaveSystem` (snapshot/restore), `cfg.live_mode` (ORCH: CR if a system must skip on it), ELEV's height API + `MapGen.validate_height`, AI7-DOC/AI7-CMD for AI tactics in Live.
- **Tasks (in order):**
  1. `EditorLive.start / stop / set_speed`: `stop` restores the exact pre-Live state (state_hash equal); undo history untouched. Post `fact live.api_ready`.
  2. Live runs combat + AI tactics only: CR ORCH to make Economy / Production / Construction / Progression / Market skip while `cfg.live_mode` is on (flag default off).
  3. Editor UI: `L` toggle, pause / 1 / 2 / 4, a Live indicator; it fits the UI fit test.
  4. Height brushes: raise / lower / smooth / ramp, symmetry-aware, with validation issues shown.
  5. G6 placements: minefields, garrisons, rail, carriers, subs, Company HQ, companies as one block.
  6. Make test_editor_g6 green; keep the other editor/trigger/tutorial tests green.
- **Publishes:** `live.api_ready`.
- **Done-when:**
  - test_editor_g6 + the owned editor tests green
  - the editor playtest still passes (PT6 runs it)
  - full suite green
- **Never:** edit sim systems outside your files (CR their owners).
