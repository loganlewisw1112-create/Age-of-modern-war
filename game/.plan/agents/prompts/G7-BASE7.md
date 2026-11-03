# G7-BASE7: base layout that makes logistical sense (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first. Spec: docs/G7_REFERENCE.md **13.9b** (the owner's new amendment, quoted there; read every word),
section 10 (Last Protocol's 3-ring base: outer defence ring, middle economy ring, core military ring around the
facility; what each ring holds), 6.2 (the Counter-Nanite facility and its areas/flows), 6.9 (helipad, C-17 loading),
7 (turrets). Read the handoffs / commits of LPMAP7 (c535c3b, 350d4d7), LPMODE7-3 (9f9d264), LPPERF7 (0db3c3e: inert
walls), CNFAC7 / CNFAC7-2 / CNFAC7-3 (0824f0e, 576739e). Look at the current base in .plan/shots/LPMAP7-2b/*.png and the
facility in .plan/shots/CNFAC7-3/sheet_pad.png and .plan/shots/ART7C/ingame/art7b_compound_zoom2.png.

## Files you own
sim/maps/last_protocol.gd (ring sizes, plots, roads, gates, facility site in map.lp), sim/systems/lp_setup.gd (what is
pre-built where), the facility layout in sim/systems/cn_facility.gd (zone placement only) + content/g7/defs_g7_facility.json,
tests/test_lpmap7.gd / test_lpmode7.gd / test_cnfac7.gd (extend; never weaken), new display props (street lights,
floodlights, cameras on walls) in a new presentation/view/baseprops_layer.gd fed from map.lp / building data (wire it
via a change_request to ORCH for match_view), new art for small props in a new tools/art/g7_baseprops.gd. A security
camera that really watches its sector is a sim building/attachment with sight: use an existing def or add one in
content/g7 (cheap: few of them, inert for Inert7 except its sight). ART7E (live) is redrawing the facility garages,
helipad, gate, decon and loading pad in tools/art/g7_cn_facility.gd: agree footprints with it on the board first (it
keeps cells/pivots; if you change a zone's footprint, tell it before it finishes). Map validation, reachability and
the 2-sided fairness rules in sim/maps/last_protocol.gd validate() must still pass.

## Deliver
1. Last Protocol base: compact rings, functional grouping, a real road network (gate roads, ring roads behind walls,
   service roads), floodlights + street lights + lit pads (display), cameras with real sight on walls/gates/key
   buildings, auto turrets at gates, corners and approaches. Remove dead open ground; keep everything reachable by
   foot and vehicle, gates working (breach/seal still works: test_lpmode7), power/pop still secure at start.
2. Counter-nanite facility interior (every match, not only Last Protocol): zones packed in the order a team moves
   (gate -> decon -> staging -> garages -> pad / helipad), roads between them, no empty yard; C-17 ramp loading and
   garages must still work (test_cnfac7, pt7_cnfac7).
3. Perf: the Last Protocol step must stay well under 50 ms (LPPERF7 got it to ~30 ms on a shared PC; measure before /
   after with .plan/lpperf7/cost harness) and fps gates hold; lights are display-only.
4. Tests green: test_lpmap7, test_lpmode7, test_cnfac7, test_maps, test_lpperf7. Playtest: pt7_lpmap7 and pt7_cnfac7
   windowed (wrap in hb.sh) plus a before/after overview of the base and the facility at zoom 1/2; look at every shot
   yourself and judge it against the owner's words ("too many open spaces", "make more logistical sense").
