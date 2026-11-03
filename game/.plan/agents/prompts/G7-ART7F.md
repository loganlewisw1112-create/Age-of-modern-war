# G7-ART7F: facility display fixes and finished interior art (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first (board, heartbeat via `bash .plan/hb.sh ART7F <calls> <tokens> "<label>" -- <cmd>`, status every
5 tool calls with calls_used / tokens_used_est / next_action, no git, no D:). Spec: docs/G7_REFERENCE.md **13.9c** (the
owner's new note, quoted: read every word), 13.9b, 6.2 (facility), 6.9 (dropships, helipad), and every "Look checkpoint"
decision (the owner's quality bar: "no flaws", depth that makes sense from every angle). Read the ART7E, ART7D and
BASE7 commits (git log --grep "ART7E\|ART7D\|BASE7") and look at .plan/shots/BASE7, ART7E, CNFAC7-3.
A second agent, **BASE7-2**, re-lays out the base and the facility at the same time (sim footprints, defences, pads,
garrison). Agree footprints and pivots with BASE7-2 on the board before drawing to them; re-read before any write.

## Files you own
tools/art/g7_cn_facility.gd and the facility / pad art it writes, tools/art/g7_baseprops.gd, presentation/view/
baseprops_layer.gd, presentation/view/entity_layer.gd (facility, wall and pad drawing only), new art generators
under tools/art/ if needed, presentation/art/art_catalog.gd (register sheets only), tests/test_art7f.gd (new),
tools/pt7_art7f.gd (new; ask ORCH to register "art7f").

## Deliver
1. **Flicker:** the buildings inside the counter-nanite facility flicker during play. Find the cause (draw order /
   y-sort ties, alternating sprite variants, snapshot fields toggling, fog / vision redraw, LOD switch) and fix it;
   prove it with a frame-by-frame capture over 300+ frames (no building changes sprite or order unless its state
   changes).
2. **Walls link:** facility (and base) walls join into one continuous wall: proper corner, T-join, end and gate pieces
   chosen from neighbours (autotile), no gaps or overlaps at any zoom.
3. **Interior buildings:** every facility interior building gets finished art that matches its purpose and the
   approved detail level (the owner: "a few interior buildings ... dont make sense or arent fully edited/updated/
   finalized/given true art"). Known plain slabs: planning room, drone bay, workshop, range.
4. **Dropship pads:** bigger, upgraded landing sites for the current dropship size (markings, lights, blast deflectors,
   approach lighting), matching BASE7-2's new footprints.
5. **Scale audit (display):** list every sprite whose size no longer matches the current unit / vehicle / dropship
   scale (pads, doors, garages, props, roads, gates) and fix it; post `fact art7f.scale_audit` with the list.
6. Display only: state hash identical with any of it on / off; fps gates hold. Playtest pt7_art7f windowed: shots of
   the facility and every interior building at zoom 1 / 2 / 3 and the wall joins; look at every shot yourself and
   judge it against the owner's words. If something needs the owner's call, post a `need` to orch with your default
   and carry on.
