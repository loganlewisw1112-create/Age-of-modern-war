# G7-ARTCN7-5: rev3 finish (owner notes) (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first. Then docs/G7_REFERENCE.md "Look checkpoint rev3 decision" (your spec, quoted from the owner;
read every word), the earlier look decisions, section 6.5, and the handoff/report of ARTCN7-4 (board seq 762 art.scale,
962 art.dropship_sizes rev3, 963 DL7-3, 967 checkpoint) plus .plan/shots/ARTCN7/compare_today_vs_g7_rev3.png,
artcn7_side_by_side_zoom3.png and artcn7_dropship_pad_zoom3.png (look at them).

## Deliver
1. **Dropship loading, both VTOLs, all 8 facings:** remove the see-through cutaway (bay_open). Loading is shown only
   through the lowered rear ramp: a lit bay interior visible through the ramp opening, the APC driving up the ramp and
   disappearing inside, soldiers walking up in a file and disappearing inside, with frame sequences the sim can play
   (e.g. apc_load_0..N, squad_load_0..N, and the reverse for unloading). Depth must be correct in every facing: any
   part of a vehicle or soldier that is behind the hull, a wing, a fan, a nacelle or the ramp sides is hidden; nothing
   behind the aircraft is ever drawn over it. Do this with real depth (your mesh renderer's z-sorting / occlusion of
   the figure sprites against the hull), not by hand-hiding. Update art.dropship_sizes with the new frame names
   (keep aliases for old names so nothing breaks) and post it; CNFAC7-2 will build the drive-in sim from it.
2. **Clean up both VTOLs, no flaws:** check every facing at zoom 1/2/3 for depth errors (faces drawn in the wrong order,
   fans or gear showing through the body, gaps, stray pixels, broken bevel lines, shadow mismatches), fix the nose-on
   tail fins reading as ears, keep the overall design the owner likes.
3. **APC weapons:** better-looking .50 gun pods and the rocket pod (real barrels, receivers, ammo boxes/feeds, shields,
   optics), and better animations: .50 firing (muzzle flash frames, recoil, barrel/pod shake, ejected brass, smoke),
   gunner reload (box change), rocket pod raise -> fire (ripple, backblast, tube flash per tube) -> reload (canister
   swap) -> stow. Make the pale roofs read properly.
4. **Weak spots in totality:** go through every rev3 sample (soldiers too, but don't change their approved look), list
   every flaw you find with its fix, and fix them.
5. Regenerate, run test_artcn7 + test_art, rebuild the side-by-side as compare_today_vs_g7_rev4.png, plus a loading strip
   (both VTOLs, 8 facings x key load frames) and in-game shots at zoom 1/2/3 of an APC and a squad loading through the
   ramp. Look at every image yourself and judge it against the owner's words; iterate until it is flawless. Post
   `fact art.checkpoint_ready` (rev4).

Files you own: tools/art/g7_cn_*.gd (incl. g7_cn_mesh.gd and g7_cn_facility.gd), assets/art/g7_cn/, tests/test_artcn7.gd,
tools/pt7_artcn7.gd, .plan/shots/ARTCN7/. ART7B is live and draws the other G7 art with your lib/mesh renderer: if you
change a shared API in g7_cn_lib.gd / g7_cn_mesh.gd, keep it backward compatible and post it on the board.
