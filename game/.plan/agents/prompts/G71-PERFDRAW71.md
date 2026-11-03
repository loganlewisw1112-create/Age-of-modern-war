# G71-PERFDRAW71: smoother than any past build (E2, render side)

You are PERFDRAW71. Read `G71_COMMON.md` first and follow it. Budget: MAX_TOKENS 750000, MAX_TOOL_CALLS 140.
Scope: `docs/G71_SCOPE.md` part E2 and Done-when 3 in full. **No visible quality trades** (owner: "no trades").

## The gates (fps p10, idle PC, `tools/bench.gd -- --fps --fps-secs=30`)
Above every past build in each case, and >= 60:
- 2k on screen: beat **85.2** (G6.1); 10k zoomed out: beat **262.5** (G6.1).
- LP zoomed out, LP panning, LP peak with 1,000+ machines: measure G7 first (`g7` branch worktree, same PC, same
  session) and beat it, and >= 60. Today the owner calls LP zoomed out / panning **choppy**.
Post `fact perfdraw71.baseline` (G6.1 / G7 / g71 per case, method, raw numbers) before changing anything. Add the LP
zoomed-out and LP panning cases to the bench if missing (coordinate: PERFSIM71 adds the LP-peak sim case,
`fact bench.lp_peak`; until it exists, build a temporary one in tools/perf71_draw_*.gd).

## Allowed
- **GPU-batched swarm drawing** (presentation/view/swarm_batch71.gd + .gdshader: MultiMesh / instanced sprites for
  Machines, robots and later gore decals, atlas-based), batching settled static things (wrecks, bodies, craters later).
- **LOD for far units only where it's invisible at that zoom** (prove with side-by-side screenshots at each zoom:
  post them as `fact shots.best` and look at them yourself).
- Cutting redraw / per-frame work: dirty rects, culling, snapshot diffing, fewer draw calls, avoiding sim joins.
- Panning: cheap terrain / fog / decal redraw while the camera moves (CONTROL71 owns the camera itself).

## Not allowed
Any visible downgrade of art, effects, animation or resolution. If a gate can't be met without one, stop and report.

Tests `tests/test_perfdraw71.gd` (view on/off hash identical, batch draws the same set of entities as the old path),
flow `tools/pt71_perfdraw71.gd` (windowed LP pan / zoom with an fps log and screenshots).
