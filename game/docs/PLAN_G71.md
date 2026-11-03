# PLAN_G71: "Tide Line"

Scope authority: `docs/G71_SCOPE.md` (parts A–J, Pre-start decisions, frozen Done-when, build order). Goal block:
`PROGRESS.md` "Active goal (G7.1 ...)". Branch `g71`, cut from `g7` at 3a66ffc. Working copy on C: only (D: still erroring
2026-11-02; sync after a clean D: health check at the end, else tell the owner).

## 1. How it runs
- Six waves in the scope's build order. Waves are an order of start: an agent starts as soon as a slot frees and its
  inputs exist. **6 agents live at most.** Owner check-ins: the wave-5 look checkpoint and the end only (plus Stop-if).
- Every agent: brief `.plan/agents/prompts/G71-<ID>.md` + `G71_COMMON.md`. Board `.plan/board_g71.jsonl`, guard armed by
  ORCH. Default budget MAX_TOKENS 750000, MAX_TOOL_CALLS 140 (successors continue from handoffs).
- Model per agent: Opus for diagnosis / design / perf; Sonnet for bounded specs; Haiku for mechanical checks.
- After every wave: ORCH runs the full suite + determinism + perf gates (scope rule) and commits.

## 2. Start state (ORCH, 2026-11-02)
- A5 done: `rules.g71_speed_mult` 1.2 applied at load to every units-table speed (`Content._apply_g71_speed`).
- Goldens re-baselined for A5 (two identical `.plan/gold61.gd` runs, `.plan/regold71/`).
- Flow names registered: airfix71, airops71, flow71, control71, perfsim71, perfdraw71 (`tools/pt71_<flow>.gd`).
- Perf bars to beat (best past figures, idle PC): fps 2k p10 **85.2** (G6.1), 10k p10 **262.5** (G6.1); LP cases:
  measured fresh by PERFDRAW71 on G7 (`g7` worktree) and must be beaten; sim 2k ms/tick <= **G6** (branch `g6`
  worktree), measured in the same session. Last recorded: G7-final 1.42x G6.1, G6.1 1.18x G6 => G7 ~1.67x G6.

## 3. Wave 1 (A1–A5 + E2)
| ID | Workstream | Model |
|---|---|---|
| AIRFIX71 | A1 home-pad registry + AIRFIX matrix (Done-when 2), then A2 endurance / hot-pit / FARP / patrol loops | Opus |
| FLOW71 | A3 one-click send / attack, auto logistics, mission templates, <= 3 clicks | Opus |
| CONTROL71 | A4 hitboxes, hover outline, roster, edge scroll, pan, zoom-to-cursor, bigger minimap | Sonnet |
| PERFSIM71 | E2 sim: profile, exact fast paths, native moves; 2k sim <= G6; LP-peak bench case | Opus |
| PERFDRAW71 | E2 render: LP zoomed-out / panning, GPU-batched swarms, invisible LOD; fps above every past build | Opus |

## 4. Later waves (briefs written as each starts)
- Wave 2: B, G1–G3, I2, D4–D5, D7 + H8, J1–J3, J6, J10.
- Wave 3: F, C, I6–I7, H4–H6, J4, J5, J8.
- Wave 4: D1–D3, D6, H1–H3, H7, I1, G4–G6, H9, H11, J9, J11–J14.
- Wave 5: E1, E3, H10, H12, I3–I5, I8, J7, gore art; **look checkpoint (frame strips + showcase map) before any full
  art roll-out.**
- Wave 6: E4 animation in full depth; final perf, soak, package (INTEG71).

## 5. Order of risk
1. **Sim cost <= G6** while adding everything (PERFSIM71 first; Stop-if: can't be met -> stop and ask the owner).
2. **1,000+ machines + ~150 robots at p10 >= 60 fps** on the LP map (PERFDRAW71 + PERFSIM71).
3. AIRFIX: aircraft hovering over building centres (owner-visible bug, Done-when 2).
4. Determinism across gore, infection, save/resume (Done-when 7, 9).

## 6. Done-when mapping
| # | Who proves it |
|---|---|
| 1 suite + determinism | every agent (own suites), ORCH full runs after every wave |
| 2 AIRFIX matrix | AIRFIX71 (headless + packaged flow) |
| 3 perf | PERFSIM71 / PERFDRAW71 (wave 1), final perf agent (wave 6) |
| 4, 6, 8 LP soaks | wave 3–4 agents + INTEG71 |
| 5 package + look checkpoint | wave 5 art agent -> ORCH -> owner; INTEG71 |
| 7 save / resume | wave 4 session agent |
| 9 gore | wave 2 gore agent + perf agent |
| 10 infection + gas | wave 2 / 3 agents |
| 11, 12 war-mind + Blackglass | wave 4 agents |
