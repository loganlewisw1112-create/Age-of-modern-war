# Task 17 Report — Human A Counter-Ghost full corps (CG10)

## Status

Complete. Interceptor/Bulwark/Seeker/Ward org, specialties, 13 per-vehicle homes + Shade Dart, detect→recover scenario, spider-killer loop. **No git commit** (ORCH). `world.gd` untouched.

## Authority

- Plan Task 17: `docs/superpowers/plans/2026-11-23-g10-shadow-coalition.md`
- Owner addendum: board FACT `g10.owner.addendum.counterghost` seq 171 + `docs/superpowers/plans/2026-11-23-faction-depth-decisions.md` § Counter-Ghost Corps
- Board: CLAIM 195 (post GHOST RELEASE 188)

## Files

| Path | Action |
|------|--------|
| `game/sim/systems/counter_ghost10.gd` | Created — corps sim, intents, scenario, spider/foam, vehicle homes |
| `game/content/g10/defs_g10_counterghost.json` | Created — operators/vehicles/buildings/production |
| `game/content/g10/rules_g10_counterghost.json` | Created — loadouts, homes, strip/recover, counters |
| `game/tests/test_g10_counterghost.gd` | Created — 5 tests |
| `game/sim/systems/exo.gd` | Extended — `counter_ghost_tick` / `is_counter_ghost_def` / `cg_home_for`; Pre-G10 + Ghost preserved |
| `game/sim/world.gd` | **Not touched** |

## Proven

- Stage 10 Human A only; weaker camo/armor/power than Death; no CN/Blackglass/Coalition prod
- 4op/6op/Ward-pair; hunt never peels Wards; specialties + legends
- 13 dedicated vehicle homes (Shade Dart Pad 4-op only; garage not a substitute)
- Sweep → intercept → EMP/net disable → under-fire strip → CG-track recover (not Research9/Coalition tech)
- Late strip + lost recovery race failures
- Spider-killer flechette/foam/ultrasonic; hardened joints mitigate exo foam, not drones/immunity
- Ghost threat counters (Judge/Warden/Shade/Sergeant/Mule/ace)

## Tests

`test_g10_counterghost` **pass=5 fail=0** · `test_g10_ghost` **15/0** · `test_exo` **4/0**

```
Godot_v4.7.2-stable_win64_console.exe --headless --path game -s res://tests/run_tests.gd -- --only=test_g10_counterghost
```

## Handoff

- ORCH: commit Task17; wire `CounterGhost10.tick` into `world.gd` at E3
