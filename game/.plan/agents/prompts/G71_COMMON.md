# Common brief for every G7.1 agent ("Tide Line", owner-LOCKED 2026-10-31, execution ordered 2026-11-02, branch `g71`)

> **G7.1 RUNS ON THE C: DRIVE.** The D: USB drive still logs bad blocks / hardware I/O errors (re-checked 2026-11-02).
> Project root: `C:/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare/game`
> (bash: `/c/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare/game`). Agent-board tools:
> `C:/CODING/SKILLS/tools/agent-board/`. **Never read or write anything under D:.** If an older doc, handoff or script
> names a `D:/...` or `/d/...` path, use the same path on C: instead.

**The spec is `docs/G71_SCOPE.md`.** Read its header, the "Pre-start decisions" section, the "Done-when" section, and
every part your brief names, **in full**. The owner's own words in the scope are the authority; [PROPOSED] items are
approved and get built as written. Plan + roster: `docs/PLAN_G71.md`. Where a scope line leaves a number open and your
brief doesn't settle it, pick a sensible value, mark it PROVISIONAL in your content JSON, and say so in your report.

**Read `.plan/agents/prompts/G7_COMMON.md` and follow every rule in it** (and, through it, G6_COMMON.md /
CONTRACTS_G6 §0), with these G7.1 changes:
- **Branch:** `g71`. Never switch branches. Never run git add/commit/stash/reset/checkout/switch/restore (ORCH commits).
- **Board:** `.plan/board_g71.jsonl`. Post with
  `AGENT_BOARD="C:/CODING/PROJECTS - CURRENTLY WORKING ON/RTS Age of Modern Warfare/game/.plan/board_g71.jsonl" node "C:/CODING/SKILLS/tools/agent-board/post.mjs" <ID> orch <type> <topic> '<json>'`
  and read directives with `node .../read.mjs --for <ID> --type directive` on the same board (same AGENT_BOARD).
  `bash .plan/hb.sh` defaults to board_g71.
- **Status every 5 tool calls** (the guard stops silent agents): `status progress
  '{"calls_used":N,"tokens_used_est":N,"next_action":"<exact next step>","done_so_far":"<short>"}'`. Long single
  commands (godot > 60 s, soaks, bench) go through `bash .plan/hb.sh <ID> <calls> <est> "<label>" -- <cmd>`.
  On `budget.handoff_now`, or when `max(est + 90k, 312k + 2.3k x calls) >= 0.7 x MAX_TOKENS`, or calls >= 0.7 x
  MAX_TOOL_CALLS: stop new work, write `.plan/handoff/<ID>-<gen>.json` (done, not done, exact next step, files touched,
  uncommitted state), post `handoff {"file":...}`, end with status "recycled".
- **New content:** fragments go in `content/g71/` (merged after content/g7; new ids only). Rules keys are prefixed
  `g71_`. **A5 is already in:** every unit's `speed` is x1.2 at load (`rules.g71_speed_mult`, `Content._apply_g71_speed`);
  never multiply speed again anywhere.
- **Goldens:** test_hot_state GOLD / GOLD_FLAT were re-baselined by ORCH for A5 at the start of G7.1. Never edit a golden.
  If your work moves a hash on purpose, say which and why, with two identical runs showing the new value; ORCH re-baselines.
- **Determinism + cost:** as G7_COMMON. The G7.1 sim-cost bar is **stricter** than G7's: sim ms/tick on the 2k benchmark
  must end the slice at or below **G6** (`git worktree` of branch `g6`) on the same PC. So every sim feature must
  cost ~nothing when unused and be budgeted by `sim/systems/tiers.gd` when used. Measure your share.
- **No visible quality trades** (owner: "no trades"): never lower art, effect or animation quality to gain speed. LOD is
  allowed only where it is invisible at that zoom.
- **Tests:** your own `tests/test_<x>71.gd`; iterate with `bash tests/run.sh --only=<file>`. Never run the full suite.
- **Playtest flows:** `tools/pt71_<flow>.gd`, same `func run(pt) -> void` contract as pt7_*. ORCH registered: airfix71,
  airops71, flow71, control71, perfsim71, perfdraw71. Need another name: change_request.
- **Last Protocol only** where the scope says so: gate LP-only features on the LP mode so skirmish stays unchanged.
- **Screenshots:** the owner rule in G7_COMMON applies unchanged (post `fact shots.best` as visible things land).
- **Report:** AGENT_RULES final report format. No commits. No GENESIS/postflight offer.

## Who owns what (G7.1 wave 1; later waves get their files when they start)
| Agent | Owns (write) |
|---|---|
| AIRFIX71 A1 + A2 air pads + air ops | sim/systems/air.gd, sim/systems/airfield.gd, sim/systems/vanta7.gd (return / landing / fuel / service paths only), new sim/systems/pads71.gd (home-pad registry), new content/g71/defs_g71_air.json (FARP building, fuel/service rules), the pad-registration lines in cn_facility.gd and drone_bay7.gd (registration calls only: post `fact pads71.register` first), new presentation/ui71/patrol_draw.gd, tests/test_airfix71.gd, tests/test_airops71.gd, tools/pt71_airfix71.gd, tools/pt71_airops71.gd |
| FLOW71 A3 fewer steps to battle | new sim/systems/flow71.gd (send-to-front, auto logistics, mission templates; commands `flow_send`, `flow_auto`, `flow_template_save`, `flow_template_launch`), new content/g71/rules_g71_flow.json, presentation/ui7/cardbar8.gd, card8b_base.gd, building_card8c.gd, ops_card8.gd (one-click buttons), new presentation/ui71/flow_*.gd, tests/test_flow71.gd, tools/pt71_flow71.gd |
| CONTROL71 A4 clicking + camera | presentation/view/camera_rig.gd, presentation/hud/minimap.gd, presentation/view/view_util.gd (picking), the selection / hover / picking parts of presentation/match_view.gd (claim the functions by name on the board first), new presentation/ui71/roster.gd, new presentation/view/hover_outline.gd, tests/test_control71.gd, tools/pt71_control71.gd |
| PERFSIM71 E2 sim side | sim/systems/movement.gd except `formation_slots` + helpers below it, sim/systems/sim_index.gd, sim/systems/tiers.gd, sim/systems/combat.gd + accuracy8.gd + stray8.gd + morale.gd + fog.gd (perf-only, exact, hash-identical changes; behaviour changes need a change_request), native/ via tools/build_native.sh (stage/swap), tools/bench.gd + tools/scale_bench.gd (new LP-peak case), new tools/perf71_*.gd, tests/test_perfsim71.gd |
| PERFDRAW71 E2 render side | presentation/view/entity_layer.gd, batch_art.gd, batch_atlas.gd, lod_icons.gd, motion.gd, fx_layer.gd, fx61_*.gd, terrain_layer.gd, fog_layer.gd, world7_layer.gd, decal_layer.gd, sim/render_snap.gd (snapshot fields; others request by change_request), new presentation/view/swarm_batch71.gd (+ .gdshader), tests/test_perfdraw71.gd, tools/pt71_perfdraw71.gd |
| ORCH | sim/world.gd, sim/content.gd, tools/ui_playtest.gd, content registries outside your own fragment, tests/test_hot_state.gd goldens, README / PROGRESS / PLAY_ME, packaging, commits |

Anyone needing an edit in a file they don't own: `change_request` to the owner (or ORCH) with the exact function and
change. Camera panning speed is CONTROL71's; PERFDRAW71 makes panning cheap, not faster.
