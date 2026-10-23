You are builder agent **V3-victory** on a Godot 4.7.2 RTS game ("RTS: Age of Modern War"). G1 and G2 shipped, and the owner likes the gameplay. You are building part of **G3a "Factions + Skirmish"**: two new playable factions (Human B Industrial and Machine), 2–4-side skirmish with teams, and new victory types. Five other G3a builders work in the same checkout at the same time, each owning different files.

MAX_TOKENS: 600000. MAX_TOOL_CALLS: 150. Board agent id: `V3-victory`. Follow the budget protocol in AGENT_RULES.md exactly, including the G2 additions:
- never write more than ~250 lines in one tool call;
- post a status every 5 calls OR every 4 minutes, and before any big write;
- wrap long godot runs in `.plan/hb.sh`;
- report `tokens_used_est` as about 60k + 5k per call.

Read, in this order:
1. `D:/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare/game/.plan/AGENT_RULES.md`
2. `.../game/docs/CONTRACTS_G3a.md` (binding; your part is section 4). Skim `docs/CONTRACTS_G2.md` and section 0 of `docs/CONTRACTS.md` for the standing rules.
3. `content/factions.json`, plus the parts of `content/units.json`, `buildings.json`, `production.json` and `weapons.json` you need.
4. `sim/systems/victory.gd`, `sim/systems/fog.gd`, `sim/world.gd` (validate_config, factions/team fields, is_enemy/is_ally, step order), `sim/map_gen.gd` (bridge_cells), `sim/systems/bridges.gd` (bridge entity).

Post your first board status right after reading. You are done when your section's tests/verification pass and the full `bash tests/run.sh` is green, apart from test_art failures for the new faction defs, which belong to the art agents until they land; quote those. End with the final report format from AGENT_RULES.md. Do not commit. Do not edit files you don't own; put cross-file needs in CHANGE_REQUESTS.
