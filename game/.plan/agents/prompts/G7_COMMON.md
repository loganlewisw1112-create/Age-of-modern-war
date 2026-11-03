# Common brief for every G7 agent ("Last Protocol", owner-approved 2026-10-26, one big drop, branch `g7`)

> **G7 RUNS ON THE C: DRIVE (owner, 2026-10-26).** The D: USB drive has hardware read errors. Project root for G7:
> `C:/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare/game` (bash: `/c/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare/game`).
> Agent-board tools: `C:/CODING/SKILLS/tools/agent-board/`. **Never read or write anything under D:** during G7. If an older
> doc, handoff or script names a `D:/CODING/...` or `/d/CODING/...` path, use the same path on C: instead.

G6 and G6.1 are delivered. The owner approved G7 after a long design pass. **The spec is the "G7 MASTER SCOPE"
section of `docs/G7_REFERENCE.md` (sections 0–13). Read section 0 (ground rules) and every section your brief names,
in full.** The roster and waves are in `docs/PLAN_G7.md`; the frozen Done-when is in `PROGRESS.md` (Active goal G7).
Where a scope line says "set in the plan" and your brief doesn't settle it, pick a sensible value, mark it PROVISIONAL
in your content JSON, and say so in your report.

**Read `.plan/agents/prompts/G6_COMMON.md` and follow every rule in it**, with these G7 changes:
- **Branch:** `g7`. Never switch branches. Never run git add/commit/stash/reset/checkout/switch (ORCH commits).
- **Board:** `.plan/board_g7.jsonl`. Post with
  `AGENT_BOARD="C:/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare/game/.plan/board_g7.jsonl" node "C:/CODING/SKILLS/tools/agent-board/post.mjs" <ID> orch <type> <topic> '<json>'`
  and read directives with `read.mjs --for <ID> --type directive` on the same board. Bus log: `.plan/bus.log` as before.
  `bash .plan/hb.sh` already defaults to board_g7.
- **Contract:** your brief + this file. CONTRACTS_G6 §0 hard rules still bind (determinism, saves, hashing, content
  fields over hardcoded def ids, every intermediate state compiles, keep public signatures you don't own working).
- **Cross-agent APIs:** call another G7 agent's API only through a guard (`sim/ai/ai_g6_lib.gd`'s `L.api` / `L.callf`,
  or a `has_method`-free check) until they post `fact <api>` complete. Post `fact <api>` for your own APIs as a
  compiling stub within your first 15 tool calls, then again when complete.
- **Pre-registered systems (ORCH, done):** `sim/systems/wounds.gd` (after Combat; commands treat_casualty,
  evacuate_casualty), `sim/systems/drone_pilot.gd` (before Air; drone_take, drone_steer, drone_release, drone_detonate,
  drone_return), `sim/systems/convoy.gd` (after SquadAI; convoy_form, convoy_move, convoy_disband). They are stubs with
  `tick`, `validate_command`, `apply_command`; the owner fills them in and keeps those three signatures. Need another
  system slot or command name: `change_request` to ORCH with the exact position and names.
- **Determinism and cost:** sim-side logic seeded only through `w.rng` or pure functions of state, thinking on a
  staggered cadence (`(w.tick + id) % N == 0`), sorted iteration where order matters, new state saved and hashed.
  Expensive work (rays, gait choice, sensor checks, formation spacing) is budgeted by the sim detail level
  (`sim/systems/tiers.gd`): full detail in close fights, cheaper approximations with the same rules in huge fights.
  Total 2k-unit sim cost may rise at most 20% over G6.1 for the whole of G7: keep your share small and measure it.
  A match that never uses your feature stays as cheap as before.
- **Display never writes the sim:** anything purely visual lives in presentation/ and reads the render snapshot or
  events; the view-on/off hash check must stay identical.
- **Hashes change on purpose:** never edit a golden (test_hot_state GOLD, fixed-hash tests, soak references). Report
  which moved and why, with two identical runs showing the new value is stable; ORCH re-baselines.
- **Player control comes first:** AI never overrides a fresh player order (AiCommand override window) and never moves
  a unit on Hold Position.
- **Art style:** upgraded pixel art through the existing generators under `tools/art` (team-colour `*_mask.png`
  files). No 3D. The G7 "new detail level" is set by ARTCN7 (posted as `fact art.detail_level`); new art follows it.
- **Playtest flow:** `tools/pt7_<flow>.gd` = RefCounted with `func run(pt) -> void`, same harness API as the G6.1
  `pt61_*` flows. Run windowed, one at a time, timeout 900: `"$G" --path . -- --ui-playtest="<abs shot dir>" --ui-playtest-<flow>`.
  It must print `PLAYTEST RESULT` all ok with 0 `SCRIPT ERROR`. ORCH already registered: scale7, wound7, squad7, drone7,
  look7, artcn7, sense7, creep7, cnsim7, cnops7, cnfac7, turret7, threat7, lpmode7, lpmap7, opsui7, audio7, cine7.
- **Tests:** your own `tests/test_<x>7.gd` (create it; there is no pending skeleton for G7). Iterate with
  `bash tests/run.sh --only=<file>`. Never run the full suite (ORCH does).
- **Hotkeys:** new player commands get rebindable hotkeys in presentation/ui5/panels/hotkeys.gd (owned by SQUAD7;
  others send a change_request with action name, default key, label).
- **UI fit:** any new panel must pass tools/ui_fit_test.gd at all resolutions (check yours once with `--only=test_ui_fit`).
- **Report:** AGENT_RULES final report format. No commits. No GENESIS/postflight offer.

## Who owns what (G7; later waves get their files when they start)
| Agent | Owns (write) |
|---|---|
| SCALE7 512×512+ maps | sim/map_io.gd, sim/terrain.gd, sim/map_gen.gd, sim/systems/sim_index.gd, sim/systems/fog.gd (sim grid only; moves to SENSE7 in wave 2), every part of sim/systems/movement.gd EXCEPT `formation_slots` and the helpers right below it (SQUAD7), presentation/view/terrain_layer.gd, presentation/hud/minimap.gd, presentation/view/camera_rig.gd, new sim/maps/lp_test512.gd, tools/bench.gd, native/ via tools/build_native.sh (stage/swap), tests/test_scale7.gd, tools/pt7_scale7.gd |
| WOUND7 soldier realism | sim/systems/wounds.gd, sim/systems/damage.gd, sim/systems/combat.gd, sim/systems/morale.gd, sim/systems/medical.gd, new sim/systems/shrapnel.gd, new content/g7/rules_g7_wounds.json, new presentation/ui7/wound_card.gd, tests/test_wound7.gd, tools/pt7_wound7.gd |
| SQUAD7 tactics, formations, convoys | sim/systems/squad_ai.gd, sim/systems/orders.gd, sim/systems/convoy.gd, `formation_slots` + helpers right below it in sim/systems/movement.gd, new sim/systems/formations7.gd, sim/systems/garrison.gd, presentation/hud/g2_commands.gd, presentation/ui5/panels/hotkeys.gd, new content/g7/rules_g7_tactics.json, tests/test_squad7.gd, tools/pt7_squad7.gd |
| DRONE7 drone piloting | sim/systems/drone_pilot.gd, sim/systems/strikes.gd, new content/g7/defs_g7_drones.json, new presentation/view/drone_cam.gd (+ .gdshader), new presentation/hud/drone_input.gd, new tools/art/g7_drones.gd, tests/test_drone7.gd, tools/pt7_drone7.gd |
| LOOK7 battlefield look + port animations | presentation/view/fog_layer.gd, fx_layer.gd, fx61_*.gd, entity_layer.gd, batch_art.gd, batch_atlas.gd, motion.gd, veh_anim61.gd, lod_icons.gd, sim/render_snap.gd (others request snapshot fields by change_request), new presentation/view/decal_layer.gd, the infantry drawers and anim builders in tools/art (g61_anim.gd, g6_infantry.gd, g5_units_inf_a.gd, g5_units_inf_b.gd, g4_units_inf.gd, faction_b_inf.gd, g3b_human_a.gd, g3b_human_b.gd; claim by name), tests/test_look7.gd, tools/pt7_look7.gd |
| ARTCN7 look-checkpoint samples | new tools/art/g7_cn_*.gd, new tools/art/g7_turrets.gd, new tools/art/g7_threats.gd, new tools/art/g7_lookcheck.gd, new assets/art/g7_*/, .plan/shots/ARTCN7/, tests/test_artcn7.gd |
| SQUAD7-2 | successor of SQUAD7: same files |
| CREEP7 Machine creep, cores, escalation (wave 2) | sim/systems/creep.gd, sim/systems/cores.gd, sim/systems/machine_g6.gd, new sim/systems/machine_ew7.gd, new sim/ai/machine_react7.gd, new presentation/view/creep_layer.gd, new content/g7/rules_g7_machine.json, tests/test_creep7.gd, tools/pt7_creep7.gd |
| CNSIM7 counter-nanite units (wave 2) | sim/systems/counter_nanite.gd, sim/systems/apc7.gd, new content/g7/defs_g7_cn.json, tests/test_cnsim7.gd, tools/pt7_cnsim7.gd |
| CNFAC7 facility, dropships, base state (wave 2) | sim/systems/cn_facility.gd, sim/systems/base_state7.gd, sim/systems/transport.gd, new content/g7/defs_g7_facility.json, tests/test_cnfac7.gd, tools/pt7_cnfac7.gd |
| TURRET7 8 Human A turrets (wave 3) | new content/g7/defs_g7_turrets.json, new sim/systems/turrets7.gd, new tools/art/g7_turrets2.gd (+ its assets/art/g7_turrets2/), tests/test_turret7.gd, tools/pt7_turret7.gd |
| THREAT7 Machine threat units (wave 3) | sim/systems/threats7.gd, new content/g7/defs_g7_threats.json, new tools/art/g7_threats2.gd (+ assets/art/g7_threats2/), sim/systems/cores.gd (walker pathing only), tests/test_threat7.gd, tools/pt7_threat7.gd |
| LPMODE7 Last Protocol rules (wave 3) | sim/systems/last_protocol.gd, new content/g7/rules_g7_lastprotocol.json, new presentation/ui7/lp_hud.gd, new presentation/ui7/lp_menu.gd, tests/test_lpmode7.gd, tools/pt7_lpmode7.gd |
| LPMAP7 Last Protocol map (wave 3) | new sim/maps/last_protocol.gd, new presentation/view/world7_layer.gd, tests/test_lpmap7.gd, tools/pt7_lpmap7.gd |
| CNSIM7-3 counter-nanite combat (wave 3) | CNSIM7's files (counter_nanite.gd, apc7.gd, defs_g7_cn.json, test_cnsim7.gd, pt7_cnsim7.gd) |
| ARTCN7-2 art rework | ARTCN7's files |
| ORCH | sim/world.gd, tools/ui_playtest.gd, content/*.json registries outside your own new fragment, research.json, factions.json, README/PROGRESS/PLAY_ME, packaging, commits |

Layering: WOUND7 resolves what a hit does to a soldier; SQUAD7 decides how soldiers and squads move and act (gait,
bounding, formations, clearing, grenade decisions; it calls WOUND7/combat APIs to throw or fire); DRONE7 owns drones
that the player flies; LOOK7 draws all of it (it reads states others put in the render snapshot); SCALE7 makes the
engine hold up on 512×512+ maps; ARTCN7 sets the new art detail level and makes the checkpoint samples.

## Screenshots to the owner (owner rule, 2026-10-27: "i need fresh screenshots of all new additions as theyre added")
Whenever something visible lands (a building, unit, effect, fix the owner asked for), take fresh in-game shots, LOOK at
them (Read the PNG), and immediately post them to the board, not only in your final report:
`node post.mjs <ID> orch fact shots.best '{"paths":["C:/.../a.png","C:/.../b.png"],"caption":"one plain sentence: what the owner is looking at"}'`
(absolute C:/ paths, 1-6 best shots, only shots you looked at, captions in plain words). ORCH forwards them to the owner.
