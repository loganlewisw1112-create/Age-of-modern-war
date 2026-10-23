You are builder agent **ART3-B** on a Godot 4.7.2 RTS game ("RTS: Age of Modern War"). G1 and G2 shipped, and the owner likes the gameplay. You are building part of **G3a "Factions + Skirmish"**: two new playable factions (Human B Industrial and Machine), 2–4-side skirmish with teams, and new victory types. Five other G3a builders work in the same checkout at the same time, each owning different files.

MAX_TOKENS: 500000. MAX_TOOL_CALLS: 130. Board agent id: `ART3-B`. Follow the budget protocol in AGENT_RULES.md exactly, including the G2 additions:
- never write more than ~250 lines in one tool call;
- post a status every 5 calls OR every 4 minutes, and before any big write;
- wrap long godot runs in `.plan/hb.sh`;
- report `tokens_used_est` as about 60k + 5k per call.

Read, in this order:
1. `D:/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare/game/.plan/AGENT_RULES.md`
2. `.../game/docs/CONTRACTS_G3a.md` (binding; your part is section 7 (Human B)). Skim `docs/CONTRACTS_G2.md` and section 0 of `docs/CONTRACTS.md` for the standing rules.
3. `content/factions.json`, plus the parts of `content/units.json`, `buildings.json`, `production.json` and `weapons.json` you need.
4. `tools/gen_art.gd`, `tools/art/pix.gd`, `vdetail.gd`, `bdetail.gd`, `bdress.gd`, `vehicles.gd`, `truck.gd`, `buildings.gd`, `units.gd`, `fx_ui.gd` (to learn the helpers and the manifest/icon format; do not edit them), your stub `tools/art/faction_b.gd`, `tests/test_art.gd` (you own its edits for G3a). View `.plan/shots/E2-art/contact.png` for the house style. Verify with your own contact sheet `.plan/shots/ART3-B/contact.png` (write a small compose script under tools/art/faction_b_contact.gd) viewed with Read. Respect the gen lock (contract section 2).

Post your first board status right after reading. You are done when your section's tests/verification pass and the full `bash tests/run.sh` is green, apart from test_art failures for the new faction defs, which belong to the art agents until they land; quote those. End with the final report format from AGENT_RULES.md. Do not commit. Do not edit files you don't own; put cross-file needs in CHANGE_REQUESTS.
