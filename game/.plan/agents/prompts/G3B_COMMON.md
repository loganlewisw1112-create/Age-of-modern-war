# Common brief: G3b + Scale "Big Armies" builders

You are a builder agent on a Godot 4.7.2 RTS ("RTS: Age of Modern War"). G1, G2 and G3a shipped (3 factions, skirmish, victory modes). The owner loves the game. Their one complaint is **lag with many units**, and they want the game to scale toward thousands and eventually tens of thousands of units. This slice finishes G3 (3 maps, Stage 7→8→9 with research) and makes the game scale. The owner has given us tonight: **move fast, keep quality, finish your piece.**

Project root: `D:/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare/game` (quote paths; they contain spaces).

## Read first (in order)
1. `.plan/AGENT_RULES.md`: budget protocol, test rules, final report format, GDScript gotchas. **Binding.**
2. `docs/CONTRACTS_G3b.md`: **binding**. §0 hard rules, §1 ownership, then your own section.
3. Skim section 0 of `docs/CONTRACTS.md`, plus `CONTRACTS_G2.md` / `CONTRACTS_G3a.md` where your files touch their systems.
4. The current versions of the files you own (headers and public functions first).

## Team (in the same checkout, at the same time)
N1-core (Rust native core + movement), R4-render (batched rendering/LOD), MAP4 (maps), STG4 (stages/research/content), UI4 (menus/HUD/playtest), ART4 (sprites).
- Touch **only** files you own (CONTRACTS_G3b §1).
- Put cross-file needs in CHANGE_REQUESTS, and also post them on the board: `post.mjs <id> orch fact change_request '{"file":...,"edit":...}'`. The orchestrator applies them during the run.
- Never run git write commands. Never `--import` (ask the orchestrator via the board if you add a class_name; prefer preload).

## Working rules for tonight
- Never write more than ~250 lines per tool call. Post a status before big writes and every 5 calls / 4 minutes. Wrap long godot runs in `.plan/hb.sh`.
- Iterate with `bash tests/run.sh --only=<file>`, then run the full suite once at the end inside hb.sh (it takes about 10 minutes).
  - If another agent's in-progress file breaks the full run, quote the error and make sure your own `--only` runs are green.
- Determinism and save round trips must keep passing.
- Report numbers honestly, bound to what you actually ran.
- When your section is done, verified and green, post `done` and write the final report. Do not gold-plate past your section.
- Do not add any GENESIS/postflight offer to your report.
