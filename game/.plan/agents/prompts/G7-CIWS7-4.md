# G7-CIWS7-4: CIWS "BRRRT" sound, straight-line fire from the barrel, spread with range (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board; status DIRECTLY every 5 tool calls with calls_used / tokens_used_est / next_action, also
before/after every long run; no git, no D:). Spec: docs/G7_REFERENCE.md **13.9c-32a** (new owner note, every word), plus
13.9c-32 (the mount), 13.9c-30 (traverse before firing), 13.9c-28 (muzzle flash from the barrels). Owner verbatim:
"CIWS turrets need to have that signatture phlanx BBRRRRTTTTTTTTTT shooting sound + shooting in a strait line wherever
the barrel is point w realistic bullet spread the further they shoot".
Handoffs: .plan/handoff/CIWS7-2.json and the CIWS7-3 board posts (seq 7746-7904): sim sim/systems/ciws7.gd (bursts,
drum, Traverse7 lay, ShotFired {ciws7 true, rounds}), art tools/art/g7_ciws7.gd (cw<k>_<el>[_s|_fire] states), muzzle
points assets/art/muzzle7.json (tools/art/muzzle7.gd + muzzle7_gen.gd), fx in presentation/view/fx_layer.gd (the
"laser", "ciws" tracer branch ~line 904) and fx61_core.gd, playtest tools/pt7_ciws7.gd (now starts a Machine-foe match).
## Build
1. Sound (original synthesis, no sampled recording): add to tools/audio/synth_g7.py a rotary-cannon burst: a very high
   rate of fire whose individual reports fuse into one tearing buzz (fundamental in the ~60-80 Hz rate range, harsh
   upper harmonics, a little jitter so it is not a pure tone), a short electric/hydraulic spin-up whine before the
   rounds and a spin-down after; plus a far version. Wire it through the audio catalog (audio_catalog.gd / catalog7 /
   audio_g7.gd) so a CIWS burst plays it positionally for the burst's length (a loop started at burst start and stopped
   at burst end, or a burst one-shot sized to the burst: your call, no per-round spam of one-shots), with the existing
   voice limits / far + fog culling. Regenerate the audio7 manifest (tools/audio/build_manifest_g7.py). Extend
   test_audio7 (or pt7_audio7) so a CIWS burst is proven to start that sound and stop it.
2. Straight-line stream: tracers leave the measured barrel tip (muzzle7) and travel along the mount's CURRENT bearing /
   elevation (the lay state Traverse7 holds: e.tf / tfh / tfa, render tb), straight, never bending to the target.
   While laying (not yet on target) there is no fire (already the sim rule).
3. Dispersion cone: per-burst deterministic spread (seeded by tick/mount id, never randf in the sim): a PROVISIONAL cone
   half-angle in defs (e.g. a few mrad, game-scaled so it is visible); the visual rounds fan inside that cone, so the
   group is tight close and wide far; rounds outside the target's radius fly past / kick up ground strikes. Sim: the hit
   share of a burst = the fraction of the cone that covers the target (target radius vs spread x distance), clamped, the
   same rule for air intercepts and ground fire, so long-range bursts hit less and close bursts hit almost all.
   Report the hit share at 3 ranges. Keep test_ciws7 green (extend it: the hit share falls with range; same inputs ->
   same hash twice). NOTE BAL7 (live) may tune ciws7 numbers in content/g7/defs_g7_ciws.json: post a fact and wait for a
   BAL7 reply before editing that json, or put the new spread keys in a new block BAL7 does not touch.
4. cw5_0_fire muzzle point: the only measured-fallback state (barrels hidden behind the radome at facing 5): derive it
   (e.g. the el1 tip plus the el0 offset of the neighbouring yaws, ~(-1,-186)) in tools/art/muzzle7.gd, regenerate,
   test_muzzle7 green.
5. Windowed playtest pt7_ciws7 (timeout 900): 0 fail; frame-exact shots of a burst at close and at long range showing
   the straight stream and the wider spread far; post fact shots.best (absolute paths, plain caption, read them first).
   Note in the caption that the sound cannot be shown in a still; report the sound's length / rate numbers.
Files: sim/systems/ciws7.gd, tools/pt7_ciws7.gd, tests/test_ciws7.gd, tools/art/muzzle7.gd (+ assets/art/muzzle7.json
regen), tools/audio/synth_g7.py + generated audio7 + manifest, presentation/audio/* (CIWS hooks only),
presentation/view/fx_layer.gd + fx61_core.gd (CIWS tracer branch only), tests/test_audio7.gd / tools/pt7_audio7.gd.
Post a claim fact naming each file before editing; check live claims (BAL7, PERF7G, DROP7).
