# ART10 Task 8 — TECHNICAL Humvee redesign (post cycle-8 approve)

**Agent:** ART10 · **Branch:** g71 · **No commit** (ORCH locks preferred)

## Owner gate
Cycle 8 approved CELL/DEATH/WALKER/SAFEHOUSE/CLOSE AIR/HATCH. Owner exception: TECHNICAL still rejected — redesign as real US HMMWV with correct wheel occlusion.

## Scope (hard)
| Subject | Action |
|---------|--------|
| CELL / DEATH / WALKER | **UNTOUCHED** drawers (byte-identical sheets) |
| SAFEHOUSE / HATCH | **UNTOUCHED** drawers (byte-identical sheets) |
| CLOSE AIR | **UNTOUCHED** drawer (byte-identical sheet) |
| TECHNICAL | **REWRITTEN** `_draw_technical` + technical-only helpers |

## Design
Real HMMWV silhouette at sample-gate scale:
- Wide body over track, long flat hood, low greenhouse, enclosed rear box
- Flared near-flank wheel arches; far flank solid skirt (hides far wheels)
- Chassis slab broken between axles — **no through-axle sticks**
- Roof dual-tube rocket mount retained (technical weapon identity)

## Wheel occlusion
Helpers in `g10_coalition_samples.gd`:
- `_technical_near_r(a)` — camera-near lateral sign from `∂depth/∂r = cos(a)−sin(a)`
- `_technical_wheel_visible(R,f,r)` — draw only if `fdep(f,r) ≥ fdep(f,0)` (near of hull centerline)
- Far-side wheels **not drawn**; far-side arch wells **not drawn** (solid skirt instead)

Per facing: **2 visible wheels** (near-flank FL+RL or FR+RR).

## Assets / strips (overwritten in place)
- Generator: `game/tools/art/g10_coalition_samples.gd` (`revise_cycle: 9`)
- Unit sheet: `game/assets/art/g10_coalition/units/x_technical_rocket.png` (+ mask/icon)
- Checklist: `game/.plan/shots/G71_LOOK/G10_SAMPLES_OWNER.txt`
- Strips:
  - `game/.plan/shots/G71_LOOK/strip_g10_coalition_samples.png` (+ `_2x`)
  - `game/.plan/shots/G71_LOOK/strip_g10_coalition_facings.png` (+ `_2x`)
  - `game/.plan/shots/G71_LOOK/strip_g10_cell_vs_ghost.png` (+ `_2x`) — **identical** (hash match)
  - `game/.plan/shots/G71_LOOK/strip_g10_safehouse_states.png` (+ `_2x`) — **identical** (hash match)

## Hash confirmation (other subjects untouched)
Pre/post SHA-256 match for: `x_cell_rifle`, `x_death_strike`, `x_prototype_walker`, `x_patron_cas`, `x_safehouse`, `x_safehouse_hidden`, `strip_g10_cell_vs_ghost_2x`, `strip_g10_safehouse_states_2x`.

## Board
- FACT **252** `technical-reject-post-approve`
- STATUS **253** `revise-technical ready` (`g10.look.samples`)
- NEED **254** owner re-approve **TECHNICAL only**

## Explicitly not done
No CELL/DEATH/WALKER/SAFEHOUSE/CLOSE AIR/HATCH drawer edits · no bulk catalog · no `world.gd` · **no commit**
