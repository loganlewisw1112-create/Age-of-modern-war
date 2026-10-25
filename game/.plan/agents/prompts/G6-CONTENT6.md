# G6-CONTENT6: operating guide
Read `.plan/agents/prompts/G6_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G6 §0-§2, §5, §6, §3, §14 (Stage 10, research), §9-§13 for def flags. **Plan:** PLAN_G6 §3, §7.
**Board / bus id:** `CONTENT6`. **Budget: MAX_TOKENS 750000, MAX_TOOL_CALLS 140** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g6/test_content_g6.gd`, `tests/pending_g6/test_stage10.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### CONTENT6: defs for every G6 asset, research, Stage 10
- **Role:** every §3.1 / §3.2 id as a content def with provisional balance, the 24 research items, and Stage 10 playable.
- **Owns:** see CONTRACTS_G6 §1 row CONTENT6 (`content/g6/defs_*.json`, `stages.json`, `factions.json`, `research.json`, the `advancement` block of `rules.json`, their tests).
- **Inputs:** `docs/g6_art_kit/items.json` (names, roles, stages) + `docs/g6_art_kit/notes/*.md` (squad sizes, frames); content/g5 fragments as the format model; the §9-§14 def flags (FOUND-line any flag name you settle with an owner).
- **Tasks (in order):**
  1. Defs for all units and buildings in §3.1 + §3.2:
  2.   - name, faction (`shared` for `s_*`), stage_min, cost, build_time, hp, armor, sight, speed, move_class (incl. `hover`, `rail`), squad_size, weapons + armor_mult rows, production with `facility`;
  3.   - the contract flags: `field_buildable`, `passable_for`, `garrison_slots`, `sonar`, `submersible`, `radar`, `anti_drone`, `anti_garrison`, `breach`, `cargo`, `mine_kind` ...;
  4.   - company leaders are not producible alone.
  5.   Post `fact content.g6_defs_ready` as soon as every id loads, even with rough numbers. Then refine.
  6. The Rhomboid is Human B Stage 7. `a_exo_trooper` is producible at the Human A barracks at Stage 10.
  7. The §3.3 research items, each with an `effect` key the owner reads (FOUND-line the key list).
  8. Stage 10: `stages.json` playable_now; `rules.json advancement` gate 9→10 (×1.5 cost + the gate research); `factions.json stage_roles` "10" with the PROGRESS item-7 unlocks.
  9. Make test_content_g6 + test_stage10 green; keep test_stages and test_factions green.
- **Publishes:** `content.g6_defs_ready`; FOUND lines for flag names and research effect keys.
- **Done-when:**
  - both acceptance files green
  - every G6 id appears in the right build/production list for its faction and stage
  - full suite green
- **Never:** write mechanics code or art; redefine an existing id.
