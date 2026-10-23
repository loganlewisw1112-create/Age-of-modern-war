# D-view: presentation core (match view, rendering, camera, input, build ghost)
MAX_TOKENS 600000 | MAX_TOOL_CALLS 150 | model opus (multi-file integration, rendering perf)

You own `presentation/match_view.gd` and `presentation/view/**`. Implement the MatchView and Input parts of CONTRACTS.md section 7.
Keep the stub's public API, and add everything the contract lists.

Details:
- Sim ticking: a fixed 20 Hz accumulator in `_process` (at most 5 steps per frame), with `speed` (0.5/1/2/4) and `paused`.
  After each step, emit `world_events(world.events)`. For render-side interpolation, keep the previous and current pos per
  entity id and lerp by the accumulator fraction.
- Terrain: 96x96 iso, drawn efficiently. Recommended: bake the terrain into chunk textures once at match start
  (e.g. 16x16-cell chunks, rendered with a SubViewport or with Image blits from `ArtCatalog.terrain_texture`). Put
  decor (trees/rocks) and entities together in one y-sorted layer (Node2D with y_sort_enabled), with sprites pooled by entity id and freed on
  EntityDestroyed. Animating water with a few chunk frames or a shader is optional.
- Fog overlay: driven by the player's `w.fog[0]` visible/explored arrays. Unexplored is opaque near-black, and explored-not-visible
  is dimmed. Draw enemy units only when their cell is visible to the player. Enemy buildings and wrecks show their
  last-seen state from `w.memory[0]` when not visible. Update when fog changes (every few ticks), not every frame.
- Effects from events: `ShotFired` gets a tracer line + muzzle flash (cosmetic RNG is fine), and `EntityDestroyed` gets an explosion
  + smoke. Draw selection rings and HP bars on selected or damaged units, a construction progress bar, and a rally line for the selected building.
- Camera: Camera2D, fixed iso. WASD/arrows/edge pan (bounded to the map), wheel zoom 0.5x-2.5x keeping the point under
  the cursor fixed, middle-drag pan. Start centred on the player's HQ. Keep it pixel-art friendly (nearest filtering is on).
- Input: per CONTRACTS section 7 (selection, smart right-click, A attack-move, S stop, H hold, Ctrl+1-9/1-9 groups with
  double-tap to jump, Esc).
  - Build placement shows a ghost footprint coloured by `Construction.placement_error` (preload res://sim/systems/construction.gd). It is a stub returning an error until agent A lands, so show the red ghost + reason text meanwhile.
  - Left click issues `build` with the selected engineers. Shift keeps placing.
  - Expose `get_hover_info()` for the HUD (entity under cursor + placement error). Do not draw HUD panels; agent E does that.
  - Selection must ignore clicks that land on HUD Controls (use `_unhandled_input`).
- ArtCatalog (agent C, concurrent) may still be a stub returning magenta. Integrate against the API anyway, and the art
  will appear as C lands it. Never crash on missing art.
- Perf: measure fps with a default match running plus 200 extra spawned units (debug flag `--spawn-test=200`,
  handled in match_view) and report the number. Target 60 fps at 1600x900.
- Verification: take autoshot screenshots (see AGENT_RULES) of (1) the start view, (2) zoomed out, (3) a selection with
  marquee/rings and (4) a build ghost. View each with the Read tool and save them under `.plan/shots/D-view/`. To script input for the shots, add a debug arg
  `--demo-script=<name>` in match_view that performs scripted selection/placement after load. Keep it, because the
  orchestrator reuses it.
