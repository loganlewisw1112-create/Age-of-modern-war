# Site Blackglass v4 layout audit

| check | what | tests | issues | result |
|---|---|---:|---:|---|
| A1 | Footprint overlaps (buildings, walls, towers, fences, masts, pads' structures) | 3430 | 0 | PASS |
| A2 | Nothing built on a road, lane, footpath or rail corridor | 2349 | 0 | PASS |
| A3 | Every door has a clear apron of the right depth, paved and connected (heavy 26m, std 12m, dead-end 18m, person 3m) | 29 | 0 | PASS |
| A4 | Lane widths and curve radii (heavy convoy: low-loader R >= 15m) | 12 | 0 | PASS |
| A5 | Swept path of the low-loader through every junction turn (R 15m, body + off-tracking) | 20 | 0 | PASS |
| A6 | Rail: no level crossings with roads or footpaths, gantry clearance >= 6.5m | 23 | 0 | PASS |
| A7 | Turrets: never over a road / door, clear field of fire (no structure masking), overlapping coverage | 140 | 0 | PASS |
| A8 | Helipads: FATO + safety clear, approach / departure surface 4:1 for 150m clear of every obstacle | 7 | 0 | PASS |
| A9 | Explosive + fuel safety distances (magazines: inhabited 50m, ops 30m, traverse if < 30m; fuel: inhabited 25m, ops 15m, ignition 25m) | 20 | 0 | PASS |
| A10 | Pipe racks / cable trays: road clearance >= 6.5m, person >= 3.0m, spans <= 18.0m, never through a building it does not serve | 226 | 0 | PASS |
| A11 | Perimeter: berm -> fence -> kill zone >= 30m -> wall; roads cross only at gates; towers <= 55m apart, gates flanked | 55 | 0 | PASS |
| A12 | Traffic flow: one-way hazard spine, every door reachable, no reversing in the hazard zone, zones meet only at the wash | 327 | 0 | PASS |
| A13 | Interior: every room on the corridor network through its blast door, zones meet only at checkpoints, >= 3.0m rock cover | 347 | 0 | PASS |
| A14 | Terrain: everything built stands on the graded platform cut into the mountain (nothing overlaps rock) | 118 | 0 | PASS |
| A15 | Airfield: stands / taxiways / FATOs / drone station on the deck, clear and connected; every parked craft fully ON its stand or pad | 69 | 0 | PASS |
| A16 | Turret doctrine: corners alike, every gate flanked by a matching pair, north / south walls mirrored, sponsons alike, galleries typed by level, summit AD symmetric | 15 | 0 | PASS |

**7187 tests, 0 issues, ALL PASS**
