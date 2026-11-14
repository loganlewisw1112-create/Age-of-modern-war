# SWARM_NATIVE71: native machine-drawing builder for the Last Protocol peak (G7.1 E2, owner "Cache now, native later")

Owner: SWARMNAT71 (grants: native/ via tools/build_native.sh stage/swap, presentation/view/entity_layer.gd, motion.gd,
sim/render_snap.gd snapshot fields). Gate (unchanged): LP peak (1,000+ machines, zoom 0.5) fps p10 >= 60 and above G7's
LP figures; 2k and 10k must not regress. Owner rule: no visible quality trades; LOD only where invisible.

## 1. Where the LP-peak frame goes (step 1, SWARMNAT71-1)

Harness: `tools/swarmnat71_frame.gd` (extends `tools/perf71_draw_lp.gd`, same scene and bench.lp_peak placement:
1000 machines + 150 robots, zoom 0.5, windowed, --no-vsync, --prof). Per frame it timestamps the start of the process
step (the MainLoop script's `_process` runs first in `SceneTree.process`), `RenderingServer.frame_pre_draw` and
`frame_post_draw`, and samples the root viewport's measured render time (CPU / GPU) and frame-setup time. Windows
(seconds after the camera is placed): A 8-16 normal, B 16-20 entity layer hidden (its `_draw` and canvas commands gone,
`refresh()` still runs), C 20-24 normal again, D 24-28 sim paused, E 28-32 paused + entity layer hidden, F 32-36 paused
normal, G 36-40 paused + every CanvasItem child of MatchView hidden (world layers + overlays; HUD and engine left).
Runner: `.plan/swarmnat71/m1.sh` (quiet-gated, 2 runs), raw: `.plan/swarmnat71/m1.out`, `m1_r{1,2}.log`.

Note on Godot's own timer: `Performance.TIME_PROCESS` is the MAX process time over the last second (the FPS lines'
`proc_ms` of 68-880 ms at LP peak are spikes, not the average), so the per-frame split below comes from the
timestamps, not from that monitor.

**Run m1u (LOADED PC, 2026-11-09 05:45Z: load 100%, 7 other godot test runs had started at once).** CPU-side figures
are ~2.4x the quiet ones (frame 99.8 ms vs 41.45 quiet in seq 532; p_e2u_units 26.6 vs 11.2), so read the CPU rows as
ratios; the render rows barely move with CPU load. A quiet-gated rerun is queued (`.plan/swarmnat71/m1.sh` -> `m1.out`).

| Window (ms / frame) | frame | process step | RenderingServer draw | rest | vp GPU | draw calls |
|---|---|---|---|---|---|---|
| A normal | 99.8 | 87.7 | 11.6 | 0.5 | 8.3 | 1494 |
| B entity layer hidden | 102.1 | 91.4 | 10.4 | 0.4 | 7.1 | 1182 |
| C normal | 95.5 | 82.6 | 12.3 | 0.6 | 7.5 | 1638 |
| D sim paused | 126.9 | 113.5 | 13.1 | 0.2 | 7.4 | 1647 |
| G paused, all world layers hidden (HUD + engine) | 71.2 | 64.5 | 6.5 | 0.2 | 6.3 | 132 |

(D / F are slower than A because the other agents' test load rose during the run, not because of the pause.)

**What the quiet LP-peak frame is made of** (quiet seq 532 / 626 + the ratios above): ~41.5 ms = process step ~30
(entity layer 18.6, terrain + world7 / creep / props 3.4, fx ~2, overlay `_draw`s ~3.3, unmeasured scripts ~3) +
RenderingServer draw ~10-11 (GPU-bound: GPU 7-8 ms). The "13.7 ms other" of seq 532 is therefore ~10-11 ms render +
~3 ms of scripts that no PROF key covers.

Findings:
1. The render part is ~10-12 ms and not CPU-bound; the entity layer's canvas commands are only ~1.2 ms of it (B vs
   A / C), so a native item builder can cut the render part by ~1 ms at most.
2. With every world layer hidden, the HUD + engine alone cost 6.5 ms render / 6.3 ms GPU at 132 draw calls: a fixed
   floor of ~39% of the 16.6 ms budget (unlocated: HUD / minimap / lp_hud or the iGPU present cost).
3. Even with the whole entity layer free, the frame is ~23 ms (~43 fps). **60 fps at LP peak is out of reach from the
   entity layer alone**, native or not. Per the brief this stops the build: `owner.lp_peak.ask2` (section 6).

## 2. Per-unit work today (motion layer ON at LP peak: ~605 units drawn <= MOTION_CAP 700)

PERFDRAW71-8 split (seq 626, PD71_RC=0): p_e2_ents 18.3 ms = unit loop 11.2 (visibility / G6 / live 1.1, art cache
1.0, motion.step block 2.9, frame cascade 1.3, VehAnim61 0.6, row / lift / drawn7 / x7 1.4, push + post 2.1) + statics
4.8 (990 statics, 441 items) + corpses 1.1. Re-measured here (rc8 logs, LP peak, PD71_RC=0 vs 1): p_e2_ents minus the
unit loop is 6.4-6.5 ms with the GDScript static records off and 4.1-4.6 ms with them on (they are exact at LP: 0 diffs,
seq 698), so ~2 ms of the statics block is already removable in GDScript.

The unit loop at LP peak is ~18.5 us per drawn unit. Per NATIVE_COMBAT71 section 8, a native read of one Dictionary
field costs ~150-250 ns: a native builder saves only by deleting GDScript statements and by reading packed arrays.
What the per-unit loop reads:
- packed, already in the snapshot: ids, pos, prev, facing, def (index into defs), owner, flags, hp, sq7f / sq7a / sq7h,
  terrain, the fog `visible` bytes, the height-lift table;
- Dictionaries: art._ec[id] (the per-id art cache Array, 41 slots incl. the a61 / v61 column Dictionaries and three
  PackedVector2Array frame tables), motion.vs[id] (PackedFloat32Array(23) per unit), _post / _fat / _chev / _pips /
  _mcls, g7u / g6u / air / squad / sling / x7 side tables (sparse; machines have almost none), ents[id] (vis_units),
  drawn7[id] (written: one new Array per motion unit per frame).

## 3. Design

Built only if the owner picks option (a) in section 6. The unit of work is the per-frame entity list of "plain" units.

**Native class `RtsSwarmDraw` (native/rts_core/src/swarm_draw.rs, rts_core 0.6.3).**
- *Art records.* When `BatchArt.cache_unit` builds an `_ec` entry, GDScript registers what the frame choice needs as one
  native record (page, src origin, frame size, pivot, c[7] fire, c[8]-c[11] walk / move, c[30] cmd, c[35] split, the
  c[38] / c[39] / c[40] block-B PackedVector2Array tables, the a61 column lists, the v61 recoil / bank / move / track /
  burner / damaged / pulse columns) and gets an index; native keeps id -> (record, def, owner, squad), so today's
  per-frame `ec.get(id)` + validity check becomes a packed compare.
- *Motion store.* Native owns the Motion state (23 f32 per id, same S_* layout) of the ids it steps: `step` is a
  line-for-line port of motion.gd `step` (Vector2 math in f32, scalars in f64, stores rounded to f32, Godot's wrapf /
  lerp / limit_length / posmod; the per-class exp() factors stay computed in GDScript and are passed in, so exp has no
  libm divergence). motion.gd keeps its API (speed / recoil / turn_rate / track_phase / on_shot / kill / forget / prune /
  aim_row / row_h / mark_screen) and routes natively held ids to the store; `vs` keeps the GDScript-stepped ids. A unit
  that changes path hands its state over (take / give), so the smoothing never resets. Readers of `motion.vs` outside
  my files (tools/pt61_anim61.gd, pt61_animb61.gd, pt7_look7.gd, path7_measure.gd, tests/test_anim61.gd) need a
  `motion.state_of(id)` accessor via change_request before the toggle can default on.
- *Kernel.* One call per frame: `units(snapshot packed arrays, alpha, t, view rect, fog bytes, ally fog, raise / lift
  tables, per-frame class factors, posture bits, item base index)` writes the items of every plain unit into its own
  packed buffers (same layer / depth / index key layout; page, src, size, dst, dsz, mod), the drawn7 rows, the
  vis-unit indices and the counter deltas, and returns at the first unit it cannot draw exactly; GDScript draws that one
  through today's path and calls again from the next index, so push order and sort keys are unchanged. GDScript appends
  each native block with `append_array` (memcpy) and fills `vis_units` from the indices.
- *Plain* = not FLAG_ABOARD / HID / S7 / G6 / WOUNDED / EVAC / SLUNG / SHIP / LANDED air, no g7u / air / sling / x7 /
  wall-walk / craft / squad-alive entry, no BAY_ART / XL remap, art page >= 0, no turret / APC gun. Everything else stays
  GDScript (exact by construction). At LP peak that is nearly every machine (no wounds, no G7 states).
- *Stays GDScript:* `_refresh_post` (Morale / Fatigue / chevron / bearer reads of the live sim for 1/8 of the units per
  frame; native gets the bits as a packed array), statics / corpses / decor / fire / ghosts (later pieces), the sort,
  `_draw_body`.
- Toggle `EntityLayer.SWARM_NAT` (env `SWARMNAT71=1`), default off until the proof in section 4 is clean.

## 4. Exactness proof

1. **Record-for-record, every frame** (`SWARMNAT71_VERIFY=1`, the PD71_RC_VERIFY pattern): each refresh runs today's
   GDScript path, restores the motion state (vs + native store), runs the native path, and compares every pushed item
   (key, page, src, size, dst, dsz, mod), the sorted list, vis_units / vis_sp / vis_air (identity), every g5 / g6 / g61
   counter, drawn7, and the full motion state of every stepped id (all 23 floats, bitwise). Gate: 0 diffs on LP peak,
   LP pan, LP zoomed out, 2k on screen and 10k (refreshes where the native path did not engage counted separately).
2. **Pixels you look at:** same-frame A/B with the tree paused (tools/perf71_draw_rcab.gd pattern): GDScript shot vs
   native shot, max diff + x10 diff image at LP peak zoom 0.5 / 1.0, posted as shots.best only after looking.
3. **Sim untouched:** test_hot_state 17/0 and test_perfsim71 after every DLL swap (rts_core is shared with the sim);
   view on/off hash test in test_perfdraw71.
Float semantics to match: GDScript float is f64, Vector2 is f32 (every Vector2 op rounds to f32), PackedFloat32Array
stores round to f32; sin / cos come from different libms (Godot's build vs Rust's) and may differ by 1 ulp, which only
survives the f32 rounding with probability ~2^-28 per value; the per-frame verify is what proves it.

## 5. Estimate per part (honest) and measured

Quiet LP peak today: frame ~41.5 ms, p10 ~22-24. PROVISIONAL estimates (ms per frame), assuming ~0.2 us per remaining
native Dictionary read and ~1 us of kept GDScript per drawn unit:

| Piece | Today | After | Saved | Generations |
|---|---|---|---|---|
| unit kernel (motion + frame choice + push, plain units) | 11.2 | 1.5-2.5 | ~9 | 2-3 |
| statics (GDScript records exist, exact at LP; native cull from a per-snapshot packed pos array) | 4.8 | ~1 | ~3.5 | 1 |
| corpses + decor + sort | 2.1 | ~0.5 | ~1.6 | 1 |
| entity canvas commands (render side) | ~1.2 | ~1 | ~0.2 | - |
| **entity layer total** | **18.6** | **~4-5** | **~14** | **4-5** |

Best case with all of it: frame ~27.5 ms -> ~36 fps avg (p10 ~33): about 2x G7's LP peak (13.3-15.4 p10, loaded rounds,
seq 368), **not 60**. Left without any entity layer (~23 ms): render ~10-11 (GPU 7-8, of which the HUD / engine floor
6.3), terrain-group refresh 3.4, fx ~2, overlay `_draw`s ~3.3, unmeasured scripts ~3. 60 fps needs those cut to ~12 ms
together (render <= ~8 with the 6.3 ms floor explained), which is outside this agent's grant.

Measured vs estimate: nothing built (stopped by the brief's rule, section 6).

## 6. Decision: stopped, owner asked (fact owner.lp_peak.ask2)

Options put to the owner:
- (a) Build the native entity builder anyway (sections 3-4): LP peak ~33-36 fps p10 PROVISIONAL, ~2x G7, 4-5
  generations, exact by the per-frame verify.
- (b) (a) + a whole-frame program: locate the 6.3 ms HUD / engine GPU floor (cheap probe first), terrain-group refresh on
  change only, fx / overlay cuts (PERFDRAW71-successor / CONTROL71 files): 60 possible only if every part lands; unverified.
- (c) New LP-peak bar: beat G7 by >= 2x and >= 30 fps p10, smooth; 60 stays the bar for 2k / 10k.
- (d) Quick GDScript win now, independent of a-c: turn on the PERFDRAW71-8 static records alone (exact at LP: 0 diffs,
  seq 698; unit records stay off) after a statics-only verify on 2k / 10k: ~2 ms at LP peak.
Recommendation: the GPU-floor probe and (d) now; then (a) + (c), unless the probe shows (b) is reachable.

## 7. Also done here
- `sim/render_snap.gd` g71 provider hook for wave 2 (`RenderSnap.register_g71(key, provider)`, provider.call(w, snap)
  once per build, result at snap.g71[key]; nothing registered = no work): fact render_snap.g71_hook, test
  tests/test_swarmnat71.gd test_g71_hook 1/0.
