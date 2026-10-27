# G7-LPMAP7: the Last Protocol map + world reaction (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first. Flow name: lpmap7. Spec: G7_REFERENCE master scope section 10 (map size LOCKED: **minimum
512×512 tiles**), 13.3 (dam, bridges, old power grid), 13.8 (4 secrets), 13.9 (a world that reacts), plus brainstorm
B10, B16. SCALE7 proved 512 and 768 maps (lp_test512 generator, bench, flow-field limits; read its handoff
.plan/handoff/SCALE7-1.json). LPMODE7 builds the mode rules in parallel: agree the placement interface on the board early.

## Deliver
1. **The map** (`sim/maps/last_protocol.gd`, hand-authored layout generated deterministically; register in map_gen and
   content/maps.json by change_request to ORCH): **at least 512×512**; your 3-ring base on one side (outer defence ring
   ~140 tiles across, middle economy ring ~110, core military ring ~70 around a ~32×32 Counter-Nanite facility site, with
   the airfield, artillery parks and Company HQ in the core ring); urban areas, forest, tunnels, rivers for firebreaks,
   dead zones; forward bases you can retake; seed nests (CREEP7 `Creep` seeds/nests); scanner relays; 3 doomsday core
   zones (CREEP7 `Cores.place`); the dam + valley, key bridges, the derelict power station; the 4 secret sites (prototype
   cache bunker, lost squad, Machine origin site, buried mech factory); Machine creep pre-spread over much of the map at
   start. Map must pass the existing map validation and fairness checks that apply (1v1 vs Machine).
2. **Base layout data** LPMODE7 uses to pre-build everything (ring walls, gates, tower/turret slots, economy plots,
   military plots, facility site, airfield and helipad positions).
3. **World reaction** (display side, cheap at 512+; `presentation/view/world7_layer.gd` or extend creep_layer by
   change_request to CREEP7's file owner = ORCH now): creep-warped terrain (trees calcify into metal lattices, rivers
   darken, buildings sprout nanite growths where creep has sat long), purged ground slowly recovering colour; sky and
   light shifting darker/colder with a haze as the creep meter climbs (pushed back by purging); wildlife and civilian
   traces (fleeing animals, abandoned vehicles, empty camps, distress beacons) that react to fighting and creep.
4. Perf: the full map with the pre-built base must stay inside the fps targets (2k on screen p10 >= 60, 10k zoomed out
   p10 >= 30); use bench.gd `--map=last_protocol` and report.

## Tests (tests/test_lpmap7.gd)
size >= 512; layout features present and reachable; ring/plot data consistent; creep, nests, cores placed; same seed =
same map bytes; existing maps unchanged. Playtest flow tools/pt7_lpmap7.gd: overview at full zoom-out, each ring, each
core zone, the dam, a warped area vs a recovered one; shots.
