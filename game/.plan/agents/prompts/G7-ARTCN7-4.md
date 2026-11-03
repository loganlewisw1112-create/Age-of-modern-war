# G7-ARTCN7-4: art rev3 (owner rejected rev2) (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first. Then docs/G7_REFERENCE.md: "Look checkpoint decision", **"Look checkpoint rev2 decision"
(your spec, quoted from the owner; read every word)**, section 6.5 (APC incl. the pop-out 6-tube rocket pod) and the
C-17-style loading line in the dropship section. Then .plan/agents/prompts/G7-ARTCN7.md and the handoffs
.plan/handoff/ARTCN7-2.json, and ARTCN7-3's results: board seq 696 (art.dropship_sizes), 697, and
.plan/shots/ARTCN7/compare_today_vs_g7_rev2.png + artcn7_side_by_side_zoom2.png (look at both: that is what the owner
rejected).

## Deliver, in this order
1. **One real-world scale.** Measure the existing game: tile 64x32 isometric; today's buildings and vehicles. Decide
   metres-per-tile and pixels-per-metre that make a ~1.8 m soldier, a ~8 m x 2.7 m APC, the dropships and the facility
   all correct against the tile grid and each other. Post it as `fact art.scale` before drawing. Show it in a scale
   strip (soldier, APC, dropship, tile diamond, a building) and look at it yourself.
2. **Soldiers resized to that scale** with the rev2 kit detail and quality kept (plate carrier, pouches, NVG / sealed
   hood + faceplate, armbands both arms, role weapons). Smaller must still read: use clean silhouettes, value contrast
   and a crisp outline rather than shrinking the rev2 pixels. Make the 7 strike-team roles tell apart at idle.
3. **APCs: complete design overhaul**, dynamic and realistic: real modern 8x8 wheeled-APC proportions and silhouette
   (sloped faceted hull, wheel arches, visible suspension travel, optics, smoke dischargers, antennae, stowage, tow
   points), shielded .50 gunner pods with seated gunners, and the pop-out 6-tube rocket pod (top rear right, behind the
   gunner pod) clearly readable when raised. Motion: wheel turn, suspension bob, gunner traverse. Both the strike APC
   and the tactical APC, distinct from each other.
4. **Stealth dropship: complete redesign as a true VTOL** (sleek faceted stealth fuselage, cockpit, wings, tail,
   tilting/ducted lift rotors or fans that visibly tilt between hover and forward flight, landing gear) with the rear
   cargo ramp the strike APC drives up (C-17-style loading kept: APC + 10 soldiers inside, proportionate at the new
   scale). Frames: flight, transition, hover/descend, landed, ramp_down, apc_ramp, bay_open (or a cutaway that still
   reads as an aircraft), squad_in, drones. The regular XL VTOL dropship gets the same quality redesign (distinct, less
   stealthy, still a real VTOL with an internal bay). Resize the helipad to fit, and re-post `fact art.dropship_sizes`
   (CNFAC7-2 will build the drive-in sim from it).
5. Regenerate assets, run test_artcn7 (update its size expectations to the new scale, with the owner quote as the
   authority; never weaken anything else) and test_art; build `.plan/shots/ARTCN7/compare_today_vs_g7_rev3.png`
   (same format as rev2, plus the scale strip) and an in-game shot at 1x and 2x/3x with soldiers standing next to the
   APCs and a dropship on its pad. **Look at every image yourself and judge it against the owner's words before you
   report**; iterate until you'd show it to the owner without excuses. Post `fact art.checkpoint_ready` (rev3).

Files you own: tools/art/g7_cn_*.gd, g7_threats.gd, g7_turrets.gd, assets/art/g7_cn*, the sample outputs those write,
tests/test_artcn7.gd, tools/pt7_artcn7.gd, .plan/shots/ARTCN7/. Do NOT roll the style out to other units (that waits
for the owner). Other generators (g7_turrets2.gd, g7_threats2.gd, g7_growths.gd) are not yours; if your new scale
changes what they must do, post it on the board.
