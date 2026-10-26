# G61-ANIMA: animation overhaul, part A: the motion/render layer + all infantry (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G61_COMMON.md first. Flow name: anim61.

Owner (2026-10-26): "add in wayyyyy better animations for the entire game and all movement (complete upgrade/overhaul)",
moved into G6.1. You own how everything MOVES on screen, and every infantry/foot/walker animation. ANIMB61 does
vehicle/air/naval art and asks you for frame-selection hooks; VFX61 does effects.

Today: units are generated pixel sprites (tools/art/*, gen_art.gd -> assets/generated + assets/art, manifest.json) with few
frames (idle, walk_a/walk_b, fire, move, a few specials); presentation/view/batch_art.gd picks a frame;
entity_layer.gd draws batched, y-sorted, with position interpolation between sim ticks (alpha lerp) and zoom LOD.

## 1. Render motion layer (presentation only; never changes the sim or its hash)
- Smooth facing: turn toward the sim facing at a max angular speed per class (infantry fast, tanks slow), no 8-way snapping
  pops; vehicles' hull turns while moving forward along a curve.
- Acceleration feel: ease in/out on start/stop (visual offset bounded so the drawn unit never drifts > 0.3 tile from the
  interpolated sim position), slight bob for walking infantry, sway for running.
- Reactions: hit flinch (1-2 px knock + flash), recoil kick on fire (infantry shoulder, frame-based), suppression cower
  (REAL61 Morale state: pinned -> prone frames, suppressed -> crouch), death: fall sequence then a fading corpse that lingers
  (cap the count, oldest fade first), wounded posture.
- Formation and squad readability: members walk in step-offset phases (no synchronous marching), leaders slightly ahead.
- All of it read from the render snapshot (sim/render_snap.gd) + events; per-entity visual state lives in the view
  (Dictionary keyed by id, pruned on death), deterministic-free cosmetic RNG only.
## 2. Infantry animation sets (art pipeline)
- Find the infantry figure rigs/drawers (e.g. tools/art/g5_units_fig.gd, g4_units_inf.gd, g6_infantry.gd, faction_b_inf.gd,
  g3b_human_*.gd, Machine walker/drone drawers) and extend the shared rig so EVERY foot unit (all three factions, incl.
  officers, medics, exo-suits, Machine walkers) gets: walk cycle >= 6 frames, run >= 6, crouch, prone + crawl (2),
  fire standing/crouched/prone, reload (2), throw (2), death (>= 3 frames), wounded, idle breathing (2). Per facing as the
  current sheets do. Keep the art style (pixel look, team-colour mask files *_mask.png).
- Regenerate through the pipeline (gen_art.gd); manifest frames named consistently (walk_0..walk_5, run_0.., prone, crawl_0/1,
  fire_s/fire_c/fire_p, reload_0/1, throw_0/1, die_0..die_2, wounded, idle_0/1). batch_art.gd picks them by state + time.
- Atlas budget: check batch_atlas page count/memory before/after; keep within what the 10k fps gate allows.
## 3. Interfaces
- Frame-selection API for ANIMB61 vehicles (turret angle, track phase, recoil, banking, wake) inside batch_art/entity_layer:
  post `fact anim.frame_api` as a stub within 15 calls; ANIMB61 sends frame names and needs via change_request.
- REAL61 Morale.state / Fatigue.level / Veterancy are read through guarded calls (L.api) for postures.
## Owned files
presentation/view/entity_layer.gd, batch_art.gd, batch_atlas.gd, lod_icons.gd, the infantry/foot/walker drawers under tools/art
(name them in `claim files`), tools/gen_art.gd only where infantry needs it, new presentation/view/motion.gd (+ helpers),
tests/test_anim61.gd, tools/pt61_anim61.gd. Art tests test_art_* must stay green (update expected frame counts only where
your new frames are the intended change, and say so in the report).
## Tests (tests/test_anim61.gd)
Every foot unit def in the manifest has the full infantry set (frame names above) for every facing; facing never changes by more
than the class max turn per frame; the drawn position stays within 0.3 tile of the interpolated sim position; pinned units pick
prone frames; death plays die_0..2 then fades; the view never writes to the sim (hash identical with the view on/off).
Perf: run the windowed fps harness once at the end (`godot --headless -s tools/bench.gd -- --fps --fps-secs=30` as in
G6 evidence) and report: gates 2k p10 >= 60 fps, 10k zoomed-out p10 >= 30 fps must still PASS.
Playtest flow tools/pt61_anim61.gd: zoom in on a firefight; shots in sequence (walk cycle, prone under fire, death, smooth
tank turn) plus a 3-second frame strip (10 shots 0.3 s apart) saved as anim61_strip_*.png for the owner.
