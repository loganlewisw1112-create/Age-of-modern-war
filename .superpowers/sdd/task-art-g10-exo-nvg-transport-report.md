# ART10 — G10 exo NVG + laser + transport redesign (post-`g10.lock`)

**Agent:** ART10 · **Branch:** g71 · **Date:** 2026-11-24  
**Kind:** Post-lock art polish (owner demand after anim/air overhaul)

## Owner asks

1. Exo NVGs — flipped **UP** daytime; **DOWN** dusk/night with readable green lenses  
2. Green laser on exo weapons  
3. More realistic shooting / weapon hold on anim boards  
4. Full redesign of `x_stealth_transport` (“TRANS”) — keep stealth insert/transport role  

Deferred unchanged: TECHNICAL / SAFEHOUSE / HATCH.

## Done

### 1. NVG day / night

- `g7_cn_gear.gd`: binocular NVGs on kits with `nvg: true` (or `head: "nvg"`).
- **`nvg_down: false`** (default sheets) = flipped **UP** on crown (day).
- **`nvg_down: true`** = flipped **DOWN** over visor with green lens glow (dusk/night).
- DEATH / WALKER / Ghost templates + CELL get readable NVGs.
- Proof strip: `strip_g10_exo_nvg.png` (+`_2x`) — columns **NVG UP DAY** | **NVG DOWN NIGHT**.
- **Runtime flip intent:** set `kit.nvg_down` from TOD / ambient light (`Night71` / `Senses7` light): day → false, dusk/night → true. Catalog sheets bake day (UP).

### 2. Green laser

- Kit flag `laser: true` on DEATH / WALKER (Ghost clones Death template).
- Under-barrel module + visible green beam along bore past muzzle (`g7_cn_gear._green_laser`).

### 3. Fire / carry hold

- `g7_cn_fig._hands`: aim = stock into shoulder, RH grip, LH on foregrip along bore; carry = two-hand low-ready.
- Regenerated CELL / DEATH / WALKER / Ghost anim boards.

### 4. Stealth transport redesign

| Id | New identity |
|----|----------------|
| `x_stealth_transport` | **Faceted stealth tilt-rotor insert craft** — long box cargo fuse, stub high-wing, twin tip nacelles, twin-boom H-tail, rear ramp, tricycle gear |

Distinct vs CAS (delta jet), silent (main-rotor helo), stealth drone (diamond), shock (X-rotor), recon (tiny boom EO). Other air ids unchanged.

### Boards / strips (`game/.plan/shots/G71_LOOK/`)

- `board_g10_anim_cell/death/walker/infantry/air_fleet.png` (+`_2x`)
- `strip_g10_exo_nvg.png` (+`_2x`) — NEW
- `strip_g10_air_unique.png` (+`_2x`)
- `strip_g10_air_facings.png` (+`_2x`)
- Ghost / bulk strips refreshed via `g10_coalition.gd` (bulk_wave 5)

### Wiring

- Generators: `g7_cn_gear.gd`, `g7_cn_fig.gd`, `g10_coalition_samples.gd`, `g10_coalition_air.gd`, `g10_coalition.gd`
- Catalog: `game/assets/art/g10_coalition/` regenerated
- `test_g10_content` **15/0**

## Self-critique (`_2x`)

- DEATH board: crown NVG UP readable; green laser clear on weapon; fire pose improved vs prior one-hand hold.
- NVG strip: UP vs DOWN contrast obvious (green lenses only when DOWN).
- TRANS: reads as Osprey-class tilt-rotor cargo (tube + tip nacelles + H-tail), not prior flying-wing blob.

## Lock note

**`g10.lock` amend needed** — FACT topic `g10.lock.amend.exo_nvg_transport` (ORCH). Post-lock owner art polish; approved-core grammar kept; TECHNICAL / SAFEHOUSE / HATCH still deferred.

## Commit / remote

- **Commit:** `39a00063` — *Polish G10 exo NVGs, green lasers, fire holds, and redesign stealth transport.*
- Board FACT `ship.art.g10.exo_nvg_transport` (see `board.jsonl`)
- Remote: `github/g71`
