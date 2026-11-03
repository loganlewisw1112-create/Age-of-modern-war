# G7-SENSE7: realistic senses + per-squad knowledge (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first. Spec: docs/G7_REFERENCE.md master scope section 2, the "Realistic senses" bullet (read all of
section 2), and section 3 "Per-squad knowledge" (read all of section 3), plus the brainstorm record entries that
mention senses, view cones, hearing, optics, thermals, night vision or per-squad knowledge. Read the handoffs of
SQUAD7-*, WOUND7-* and SCALE7 for the systems you plug into.

Note: this workstream was planned in wave 2 but never launched; it starts late, so other systems are already built.
Plug into them through small, marked hooks; do not rewrite them.

## Files you own
- sim/systems/fog.gd (the sim grid; G7_COMMON gives it to SENSE7 in wave 2) and sim/systems/intel.gd.
- New sim/systems/senses7.gd (+ content/g7/rules_g7_senses.json, numbers PROVISIONAL), tests/test_sense7.gd,
  tools/pt7_sense7.gd (flow "sense7" is already registered).
- Display: a view-cone / heard-contact overlay (new presentation/view/sense_layer.gd) and change_requests to ORCH for
  hud/match_view wiring.
- Anything in combat.gd, squad_ai.gd, doctrine, morale.gd, garrison.gd, movement.gd: change_request to the owner with
  exact lines (combat/morale/fog per-tick loops are also being optimised by LPPERF7, live: coordinate on the board,
  re-read before any write).

## Deliver
1. **Senses (per soldier, cheap):** a view cone from the head facing (peripheral vision spots movement only);
   spotting by movement, silhouette (posture, cover, light) and noise; gunfire and explosions heard with a direction
   and rough distance (a "heard contact" with uncertainty, not a reveal); scopes / optics narrow and lengthen the
   cone; thermals and night vision see through smoke and darkness. Vehicles, drones and buildings use simple sensor
   profiles. Machine units keep their own sensor rules (state what you do with them).
2. **Per-squad knowledge (feeds intel.gd):** each squad holds what it saw, what came over its radio net (G6.1 comms /
   command net) and what its drones saw; contacts age into last-known positions; squads cut off from the radio act on
   stale information. Targeting, suppression on last-known positions (SQUAD7) and AI decisions read this knowledge
   instead of global visibility, through a small API you post as `fact senses.api`.
3. **Player fog stays the union of what the player's units know** (grey fog + last-known markers from LOOK7 keep
   working).
4. **Cost:** this touches every soldier. Staggered cadence, per-squad batching, spatial index queries, no per-pair
   loops; the 2k/10k fps gates and the sim-cost limit must still hold (measure with tools/bench.gd before/after on a
   shared PC and report as shared-PC). A switch `rules.g7_senses.enabled` with the old behaviour when off, so you can
   A/B and so a non-G7 match can stay hash-identical if needed.

## Tests (tests/test_sense7.gd)
a soldier facing away doesn't spot a still enemy behind him but does notice movement at the edge; a scoped marksman
spots further in his cone; smoke blocks sight but not thermals; gunfire creates a heard contact with direction and
uncertainty; a squad cut off from the radio keeps stale knowledge while a connected one updates; suppression aims at
a last-known position; same seed twice = same hash; save/load round trip. Playtest flow tools/pt7_sense7.gd: view cones
shown, a flank surprise, a heard-gunfire reaction, a cut-off squad acting on stale intel; shots (look at every one).
