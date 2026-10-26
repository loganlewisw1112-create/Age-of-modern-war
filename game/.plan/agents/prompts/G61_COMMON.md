# Common brief for every G6.1 agent ("Field Command", owner-scoped 2026-10-26, one big drop)

G6 ("Command & Terrain") is delivered. The owner played it and asked for MASSIVE new depth in AI and everything.
Owner answers (2026-10-26):
- Q1 AI focus: **full chain of command**. Every level thinks: general > commander > captain > lieutenant > squad >
  soldier. Orders flow down, reports flow up, each level makes its own decisions. One system serves enemy AI, ally AI
  and the player's AI commanders.
- Q2 commander authority: **full general**. Runs battles AND its own war effort: plans operations on its own (strike,
  infil/exfil, attack, defend, whatever it decides), requests reinforcements, trains replacement companies from a
  budget the player gives it, calls air and artillery, manages its own logistics.
- Q3 realism: **suppression + fatigue, radio and comms, veterancy + soldier/leader traits, "EVEN MORE DEPTH"** (intel
  and belief are in too: AI acts on what it believes, not on the truth).
- Q4 controls: **both layers**. Classic RTS micro stays and gets better (formations, stances, control groups, a Teams
  panel), plus a command layer: give orders to officers and draw plans on the map (axis of advance, phase lines,
  objectives) that the chain of command carries out.
- Q5 delivery: one big G6.1 drop.
Earlier owner notes: commanders get real military training (stacking up, formations, attacking effectively, flanking,
movement across a battlefield, "EVERYTHING possible"); squads "work as a unit, not just random pieces"; more
intelligent units; new infantry ammo bearer that restocks 3 units. (ORCH does company training, market cap, fuel.)

**Read `.plan/agents/prompts/G6_COMMON.md` and follow every rule in it**, with these G6.1 changes:
- **Board:** `.plan/board_g61.jsonl`. Post with
  `AGENT_BOARD="D:/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare/game/.plan/board_g61.jsonl" node "D:/CODING/SKILLS/tools/agent-board/post.mjs" <ID> orch <type> <topic> '<json>'`
  and read directives with `read.mjs --for <ID> --type directive` on the same board. Bus log: `.plan/bus.log` as before.
- **Contract:** your brief + this file. CONTRACTS_G6 §0 hard rules still bind (determinism, saves, hashing, content
  fields over hardcoded def ids, every intermediate state compiles, keep public signatures you don't own working).
- **Cross-agent APIs:** call another G6.1 agent's API only through `sim/ai/ai_g6_lib.gd`'s `L.api(script, fn)` /
  `L.callf(script, fn, args, default)` (or an equivalent `has_method`-free guard) until they post `fact <api>` complete,
  so your code compiles and runs before theirs lands. Post `fact <api>` for your own APIs as a compiling stub within
  your first 15 tool calls, then again when complete.
- **Budget:** your brief states MAX_TOKENS and MAX_TOOL_CALLS. Status every 5 calls; at 70% write
  `.plan/handoff/<ID>-1.json` and stop. A successor continues from it.
- **Determinism and cost:** all new AI is sim-side, seeded only through `w.rng` or pure functions of state, thinks on a
  staggered cadence (e.g. `(w.tick + id) % N == 0`), and stays cheap: total sim cost at 2k units may rise at most 20%
  over G6 (ORCH measures). Sorted iteration where order matters. New state is saved and hashed. A match that never
  uses your feature should stay as cheap as before.
- **Hashes change on purpose:** never edit a golden (test_hot_state GOLD, fixed-hash tests, soak references). Report
  which moved and why, with two identical runs showing the new value is stable; ORCH re-baselines.
- **Player control comes first:** AI never overrides an order the player gave a unit within the AiCommand override
  window (20 s), never moves a unit on Hold Position. Smarter behaviour fills the gaps; it never fights the player.
- **Playtest flow:** `tools/pt61_<flow>.gd` = RefCounted with `func run(pt) -> void`; pt is the ui_playtest harness
  (`pt._log(step, ok, detail)`, `pt._shot(name)`, `pt._click_named(node)`, `pt._click_button(text)`, `pt._g5_select(id)`,
  `pt._g5_select_many(ids)`, `pt._w()`, `pt._mv()`, `pt._wait(s)`, `pt._wait_until(callable, s)`). Run windowed, one at a
  time, timeout 900: `"$G" --path . -- --ui-playtest="<abs shot dir>" --ui-playtest-<flow>`. It must print
  `PLAYTEST RESULT` all ok with 0 `SCRIPT ERROR`. ORCH already added the flow names to tools/ui_playtest.gd.
- **Hotkeys:** new player commands get rebindable hotkeys in presentation/ui5/panels/hotkeys.gd (owned by SQUAD61;
  others send a change_request with action name, default key, label).
- **UI fit:** any new panel must pass tools/ui_fit_test.gd at all resolutions (ORCH runs it; check yours with
  `--only=test_ui_fit` once, it is a heavy job).
- **Report:** AGENT_RULES final report format. No commits. No GENESIS/postflight offer.

## Who owns what (G6.1)
| Agent | Owns (write) |
|---|---|
| CHAIN61 chain of command, comms, intel | new sim/systems/command_net.gd, new sim/systems/intel.gd, new content/g6/rules_g61_command.json, tests/test_chain61.gd, tools/pt61_chain61.gd |
| GEN61 AI generals | sim/ai/commanders.gd, sim/systems/ai_command.gd, sim/ai/ally_cmds.gd, sim/ai/wave_ai.gd, sim/ai/doctrine/doc_strategic.gd, sim/ai/doctrine/doc_specops.gd, presentation/ui6/a/commanders_panel.gd, tests/test_gen61.gd, tools/pt61_gen61.gd |
| OFF61 officers, battle drills | sim/ai/doctrine/doctrine.gd, doc_operational.gd, doc_tactical.gd, doc_util.gd, doctrine_rules.json, sim/systems/ops.gd, sim/systems/ops_missions.gd, sim/ai/ai_army.gd, sim/ai/ai_tactics.gd, tests/test_officers61.gd, tools/pt61_officer61.gd |
| SQUAD61 squads, smart units, classic controls | sim/systems/squad_ai.gd (stub registered after Orders; commands set_stance, regroup), sim/systems/orders.gd, the `formation_slots` function in sim/systems/movement.gd (only it and new helpers right below it), presentation/hud/g2_commands.gd, presentation/ui5/panels/hotkeys.gd, new presentation/ui6/teams_panel.gd, minimal hook lines in presentation/hud/hud.gd, tests/test_squad61.gd, tools/pt61_squad61.gd |
| REAL61 suppression, fatigue, veterancy, traits | sim/systems/morale.gd, new sim/systems/veterancy.gd, new sim/systems/fatigue.gd, new content/g6/rules_g61_realism.json, inspector lines via a new presentation/ui6/realism_info.gd (ORCH hooks it), tests/test_real61.gd, tools/pt61_real61.gd |
| PLAN61 command layer (plans on the map) | new sim/systems/plans.gd, new presentation/ui6/command_layer/*, tests/test_plans61.gd, tools/pt61_plan61.gd |
| BEARER61 ammo bearer | sim/systems/ammo_bearer.gd (stub registered after Supply; commands join_squad, leave_squad), new content/g6/defs_g61_bearer.json, the bearer art via the G6 art pipeline, tests/test_bearer61.gd, tools/pt61_bearer61.gd |
| ORCH | world.gd (SYSTEM_ORDER, COMMANDS, preloads: ask by change_request), companies.gd, market.gd, supply/fuel, economy.gd, content/*.json outside your own new fragment, tools/ui_playtest.gd, g6_hooks.gd, README/PROGRESS/PLAY_ME, packaging |

Layering (who decides what): GEN61 decides the operation and the war effort; CHAIN61 carries orders down and reports
up (delay, range, jamming, initiative when cut off) and holds each side's belief of the enemy; OFF61 turns an order into
company/platoon battle drills; SQUAD61 executes at squad/soldier level (targets, spacing, cover, return fire); REAL61
supplies the human factors every level reads (suppression, fatigue, experience, traits); PLAN61 lets the player issue
the same orders by drawing on the map. New systems need a world.gd SYSTEM_ORDER slot and COMMANDS entries: post a
change_request to ORCH with the exact position and command names; ORCH registers a compiling stub of yours within minutes.
