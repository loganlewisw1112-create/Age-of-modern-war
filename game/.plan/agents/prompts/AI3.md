You are builder agent **AI3** on a Godot 4.7.2 RTS game ("RTS: Age of Modern War"). G1 and G2 shipped, and the owner likes the gameplay. You are building part of **G3a "Factions + Skirmish"**: two new playable factions (Human B Industrial and Machine), 2–4-side skirmish with teams, and new victory types. Five other G3a builders work in the same checkout at the same time, each owning different files.

MAX_TOKENS: 600000. MAX_TOOL_CALLS: 150. Board agent id: `AI3`. Follow the budget protocol in AGENT_RULES.md exactly, including the G2 additions:
- never write more than ~250 lines in one tool call;
- post a status every 5 calls OR every 4 minutes, and before any big write;
- wrap long godot runs in `.plan/hb.sh`;
- report `tokens_used_est` as about 60k + 5k per call.

Read, in this order:
1. `D:/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare/game/.plan/AGENT_RULES.md`
2. `.../game/docs/CONTRACTS_G3a.md` (binding; your part is section 5). Skim `docs/CONTRACTS_G2.md` and section 0 of `docs/CONTRACTS.md` for the standing rules.
3. `content/factions.json`, plus the parts of `content/units.json`, `buildings.json`, `production.json` and `weapons.json` you need.
4. All of `sim/ai/*.gd` (G1/G2 AI; its headers explain the structure), `tests/test_ai.gd`, `tools/soak.gd`, `sim/ai/tools/ai_probe.gd`. S3-sim is implementing air, artillery and energy concurrently, and V3 is implementing victory and allied vision. Code against the contract fields, and re-run your soaks after they land (watch the board for their `done`).

Post your first board status right after reading. You are done when your section's tests/verification pass and the full `bash tests/run.sh` is green, apart from test_art failures for the new faction defs, which belong to the art agents until they land; quote those. End with the final report format from AGENT_RULES.md. Do not commit. Do not edit files you don't own; put cross-file needs in CHANGE_REQUESTS.
