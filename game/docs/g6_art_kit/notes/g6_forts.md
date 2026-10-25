# g6_forts notes (art-forts-2)
All 13 are building-type assets (H.bld, rotations f0/f1), drawn in g5_bld_lib's local (u, v) frame so either rotation renders.

- s_sandbags: 1x1 line segment along u (tiles edge to edge, half-bags at the cell edges on the offset course). 3 courses of individual bags, each with a seam frame, belly line and tie ear. Team cloth on the top course. Check that each bag reads on its own.
- s_trench: 2x1 zig-zag segment on a 2-tile canvas, ends at (+-1, 0). The interior (revetted far walls, duckboards) is clipped to the cut. The far lip gets a sandbag parapet and the near lip only a low spoil ridge (chosen per rotation so the cut stays readable). Team flag on the parapet.
- s_tank_traps: 1x1 segment: 2 concrete dragon's teeth (team band) and 2 steel Czech hedgehogs, staggered.
- s_barbed_wire: 1x1 segment of triple concertina (helix coils, far halves translucent), 4 steel pickets, team rag.
- s_minefield: 2x2 area with an owner-view dashed boundary (team mask). Corner stakes carry red warning triangles, mid-edge stakes are red-tipped. AT mines are half covered by soil, there are small AP mines and one tripwire, all over disturbed-soil patches.
- s_garrison_bld: 2x2 ruined city block. One intact 2-storey half has sandbagged windows, spalled brick, a shell hole in the roof, a team flag and a team banner. The gutted half has broken wall stubs, an exposed slab and rubble. Garrison pips are a UI overlay and are not drawn.
- s_camo_decoy: 2x2 canvas holding a real MBT (VH.draw) under a draped 3-tone camo net, beside an inflatable decoy MBT. The decoy is VH.draw repainted as glossy rubber, with guy ropes, a yellow blower and a hose.
- m_nanite_wall: 1x1 Machine wall segment: graphite hex-cell panels with light panel inlays, cyan seams and a team rail. Panel 2 is breached and regrowing (holo lattice, half-printed cyan hexes, sparks).
- m_phase_gate: 1x1: two hex emitter pylons (cyan rings, crystal tips, team base panels) with a shimmering field between them (alpha < 0.6, so it gets no outline) over a chevron threshold plate.
- a_radar_station: 2x2 on a concrete slab: lattice tower with a tilted planar array (team strip), radome on a drum, olive shelter (team roof), generator and cable.
- a_fob: 3x3 compound walled with HESCO cubes and a boom gate on the +u side. Inside: canvas tent, container HQ (team roof, mast, lamp), team flag pole, crates, fuel drums and a sandbag bunker.
- a_repair_bay: 3x3: concrete workshop with 2 roll-up doors facing the pad (team band), yellow gantry crane with a hoist and hanging power pack over an MBT (VH.draw), tyres, drums and a tool cabinet.
- a_cruise_battery: 2x2 pad: 8x8 TEL with the erector raised and one cruise missile (team band, folded wings), launch-control container (team roof), and pad scorch and markings.

Plate grounds: "conc" and "rubble" are not terrain tiles (H.ground falls back to grass), so SHOW uses "building" (paved) for the conc and rubble plates.
