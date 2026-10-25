# G6-VIEW6: operating guide
Read `.plan/agents/prompts/G6_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G6 §0-§2, §5, §6, §3, §6 (art_def), §9-§12 (visible states). **Plan:** PLAN_G6 §10.
**Board / bus id:** `VIEW6`. **Budget: MAX_TOKENS 750000, MAX_TOOL_CALLS 140** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g6/test_view6.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### VIEW6: drawing every new thing
- **Role:** load the g6 art groups, entity height offsets, art_def / mimic overrides, the conscripts frame size, new effects and overlays.
- **Owns:** see CONTRACTS_G6 §1 row VIEW6 (`render_snap`, entity/batch/fx/lod/overlay layers, `presentation/art/**`, test_view6, test_view5).
- **Inputs:** ART-G6 / ART-G6b manifests, ELEV-VIEW's offset rule, MECH/NAVAL/AIRDEF states (mines owner view, garrison, sonar, radar, cohesion, AI-command badge).
- **Tasks (in order):**
  1. ArtCatalog loads `g6_units` / `g6_bld` (+ `g6_new`); every G6 id renders real art (no placeholder); per-def squad frame size (conscripts 64×44); `e.art_def` override; mimic disguise per viewer (`MachineG6.disguise_for`).
  2. Entities drawn at their cell's height offset; correct ordering across levels.
  3. New effects: laser beam, nets, jamming field, sonar ping, mine blasts, line charge, train smoke, airdrop chutes, cloak shimmer, nanite repair, assimilate stream.
  4. Overlays: mines (owner view), garrison pips, sonar range, radar range, cohesion ring, AI-command badges.
  5. Make test_view6 green; keep test_view5 green; 6+ playtests stay green (PT6).
- **Publishes:** `view.g6_ready`.
- **Done-when:**
  - test_view6 + test_view5 green
  - probe screenshots per new state
  - full suite green
- **Never:** draw art (ART-*) or terrain (ELEV-VIEW).
