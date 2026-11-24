# ART10 Task 8 — TECHNICAL scale+cleanup + CLOSE AIR gear-up

**Agent:** ART10 (fresh) · **Branch:** g71 · **No commit** · **Cycle:** 12

## CAS role (one-liner)
**CLOSE AIR = fixed-wing med-light close-air-support / attack strike aircraft** (not transport, not helo, not bomber, not drone).

## Subjects changed
| Subject | Action |
|---------|--------|
| **TECHNICAL** (`x_technical_rocket`) | Scale bump + silhouette cleanup (still owner-ref M1151) |
| **CLOSE AIR** (`x_patron_cas`) | Keep attack CAS redesign; landing gear retracted for all strip/in-air poses |
| CELL / DEATH / WALKER / SAFEHOUSE / HATCH | **UNTOUCHED** (drawers not edited) |

## TECHNICAL — scale vs units
| Unit | Scale const | Native E-facing bbox (approx) |
|------|-------------|-------------------------------|
| CELL | `FIG_SC` 2.70 | ~20×51 |
| DEATH | `DEATH_SC` 2.85 | ~soldier |
| WALKER | `WLK_SC` 3.05 | ~taller soldier |
| **TECHNICAL** | `VEH_Z` **3.90** (was 3.55) | **~66×42** — wider/longer footprint; cabin roof ≈ soldier head-height; .50+shield above |

Proportional presence: Humvee dominates infantry in **footprint** (~3× CELL width), not as a towering box. Closed-top M1151 features kept: X-doors, brush guard, roof hatch + ring, .50 + 3-sided shield, wheel occlusion (near flank + far-front peek; far-rear hidden).

## CLOSE AIR — gear behavior
- Strip / sample-gate poses call `_draw_patron_cas` → `_draw_patron_cas_pose(..., grounded=false)`.
- **In-air = gear UP:** no nose/main struts or wheels drawn.
- EO chin ball tucked high under nose (not dangling as fake nose-wheel).
- Missile hardpoints raised under wing (not runway-height blobs).
- `grounded=true` path exists for future taxi/land frames only (not used on strips).
- Palette/scale unchanged: black + dark gunmetal; `AIR_Z` 6.20 (~3× infantry strip presence).

## Assets / strips
- Generator: `game/tools/art/g10_coalition_samples.gd` (`revise_cycle: 12`)
- Ref: `game/.plan/shots/G71_LOOK/ref_humvee_owner.jpg`
- Strips regenerated: `strip_g10_coalition_samples.png` (+`_2x`), `strip_g10_coalition_facings.png` (+`_2x`), cell/safehouse companion strips
- Checklist: `game/.plan/shots/G71_LOOK/G10_SAMPLES_OWNER.txt`

## Board
- FACT `tech-scale+cas-gear` (this ship)
- STATUS `revise12 ready`
- NEED owner re-approve **TECHNICAL + CLOSE AIR** (supersedes 257)
- HANDOFF — scale comparison + gear-up behavior

## Explicitly not done
No CELL/DEATH/WALKER/SAFEHOUSE/HATCH drawer edits · no bulk catalog · no `world.gd` · **no commit**
