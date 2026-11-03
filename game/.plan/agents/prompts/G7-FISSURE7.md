# G7-FISSURE7: creep fissures, canyons and growths (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first. Flow name: fissure7. **Owner amendment, added mid-G7 (2026-10-26):** "the creep should open
up large fissures/valleys/canyons in the ground with varying different complex 'growths' sprouting and rising from
the creep and the fissures/openings." Spec: G7_REFERENCE master scope **13.9a** (read in full), plus 13.9, section 8
(creep) and section 10 (Last Protocol). Read the handoffs .plan/handoff/CREEP7-*.json and LPMAP7-1.json first.

## Files you own
- New `sim/systems/fissures7.gd` (state, growth, terrain changes, growth entities, commands). No new system slot:
  call it from `Creep.tick` (you may edit `sim/systems/creep.gd` for that hook and for the stop/kill hooks in
  purge/burn/barrier; CREEP7 is finished and ORCH owns that file now; keep edits small and marked `# G7 FISSURE7`).
- `presentation/view/world7_layer.gd` (LPMAP7 is finished; you own it now) and/or a new
  `presentation/view/fissure_layer.gd`; `presentation/view/creep_layer.gd` only if you must.
- New `content/g7/defs_g7_fissures.json` (all numbers PROVISIONAL), new art generator `tools/art/g7_growths.gd` +
  `assets/art/g7_growths/` (the Machine's CURRENT art style).
- New `tests/test_fissure7.gd`, `tools/pt7_fissure7.gd`.
- Anything else (world.gd COMMANDS, render_snap keys, match_view wiring, art catalog group, hud): change_request to
  ORCH with exact lines.

## Deliver
1. **Sim**: deterministic (w.rng streams only, staggered cadence, no per-tick full-map scans at 512+). Long-held dense
   creep cells crack; cracks widen into fissures; the oldest creep tears open into long branching valleys/canyons (not
   round blobs: line/branch networks that follow creep age and terrain). Stages: crack (ground slow), fissure
   (vehicles blocked, infantry slow crossing), canyon (all ground blocked; air unaffected). Terrain changes go through
   the existing terrain-change path (`Movement.on_terrain_changed`, see bridges.gd / g4b_mech.gd usage): **batch**
   changes so path rebuilds stay rare and cheap at 512x512, and measure it.
2. **Rules**: never open under buildings, walls, gates, bridges, sterile or barrier cells; never cut a player's base
   off from the map (check each player base's connectivity to the map before committing a canyon segment; cheap,
   bounded). Purge/burn/seal stops growth and kills growths there; purged fissures scar and, held long enough, close
   back to rough ground. Engineers can lay a span across a fissure/canyon (a command; reuse the bridge/repair
   patterns if they fit).
3. **Growths**: many varied complex shapes (at least 8 kinds: spires, crystal lattices, tendril stalks, rib arches,
   pulsing pods, antenna masts, etc.) rising slowly out of creep and the openings, larger and denser in canyons. The
   largest kinds are destructible sim entities (Machine-owned, targetable, feed the spread and cracking nearby;
   numbers PROVISIONAL); the rest are display-only scenery derived from sim state (no sim cost).
4. **Look**: canyons read as deep openings (dark walls with depth shading, crumbling edges, glowing nanite floor, haze
   rising out), cracks spidering out ahead of them; growths animate rising out of the ground, sway/pulse, shatter when
   killed. Simplified when zoomed out, culled to the screen.
5. **Perf**: the Last Protocol map (`--map=last_protocol`, registered now) stays inside the fps targets (2k on screen
   p10 >= 60, 10k zoomed out p10 >= 30) with fissures and growths at a late-run creep level; report your system's
   sim cost per tick. The PC is shared with other agents: report numbers as shared-PC, not gate numbers.

## Tests (tests/test_fissure7.gd)
cracks -> fissures -> canyons with creep age; each stage's movement rule (slow / vehicles blocked / all ground blocked
/ air free); never under buildings/bridges/barriers; a base is never cut off; purge stops growth and kills growths;
scar closes; engineer span; big growth destructible and feeding the spread; same seed twice = same hash; a match with
no creep is hash-identical. Playtest flow tools/pt7_fissure7.gd: a creep field cracking open into a canyon with
growths rising, a convoy rerouting, an engineer span, a purge closing it; shots (look at every one yourself).
