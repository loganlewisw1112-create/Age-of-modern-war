# ART10 Task 8 — approved-core bulk wave3

**Agent:** ART10 · **Branch:** g71 · **Date:** 2026-11-24

## Scope

Ship wave2 leftovers that are **not** deferred: Ghost Wing set, camo/state sheets, CLOSE AIR vehicle/drone state polish. No Humvee/safehouse/hatch redesign. No purple (Human A black kit / CLOSE AIR language).

## Wave3 delivered

| Item | Result |
|------|--------|
| Ghost Wing set | **17** Death-kit ids: base / Judge / Warden / Shade / Sergeant / Mk I–III / ace 01–09 |
| Camo states | **7** per Ghost id (rest/walk/sprint/fire/hit/battery/shield) — oil-slick, never chrome |
| CLOSE AIR states | Silent Rotor quiet→gunship; transport/drones idle+active dual-frame sheets |
| Strips | `strip_g10_ghost_set` · `strip_g10_ghost_camo` · `strip_g10_air_states` (+`_2x`); kits/facings refreshed |
| No purple | Charcoal / bone / teal / gold debt only on Ghost + shadow/EW marks |
| Deferred | **31** ids unchanged (TECHNICAL/SAFEHOUSE/HATCH) |
| Tests | `test_g10_content` **15/0** (+ ghost set + air state coverage) |

## Generator

`game/tools/art/g10_coalition.gd` — `bulk_wave: 3`.

## Still between here and `g10.lock`

1. Step 9 final contact + owner look gate (deferred-exception OK for TECHNICAL/SAFEHOUSE/HATCH)
2. Package / docs / E4 Task 23 lock ceremony
3. Optional: orphan_art audit confirmation under deferred exception

Locked look must not regress: CELL · DEATH · WALKER · CLOSE AIR.
