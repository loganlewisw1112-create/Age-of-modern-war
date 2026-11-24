# ART10 Task 8 — TECHNICAL Humvee owner-ref + CLOSE AIR full redraw

**Agent:** ART10 · **Branch:** g71 · **No commit**

## CAS role (one-liner)
**CLOSE AIR = fixed-wing med-light close-air-support / attack strike aircraft** (not transport, not helo, not bomber, not drone).

## Subjects changed
| Subject | Action |
|---------|--------|
| **TECHNICAL** (`x_technical_rocket`) | Owner-ref M1151 HMMWV redraw |
| **CLOSE AIR** (`x_patron_cas`) | **FULL REDRAW** — new geometry (not recolor/scale of prior blob) |
| CELL / DEATH / WALKER / SAFEHOUSE / HATCH | **UNTOUCHED** (SHA-256 match) |

## TECHNICAL — feature checklist vs `ref_humvee_owner.jpg`
| Feature | Status |
|---------|--------|
| Four-door armored body, flat/slant rear | yes |
| X-reinforced door panels | yes |
| Vertical-slat grille | yes |
| Tubular brush guard | yes |
| Recessed headlights | yes |
| Dual flat windshield panes + wipers | yes |
| Side mirrors on brackets | yes |
| Hood raised center + tie-down loops | yes |
| Roof ring + .50-cal HMG + 3-sided gun shield | yes (rockets removed) |
| Chunky black tires, tan rims | yes |
| Wheel occlusion (far rear hidden; near + far-front peek) | yes |
| Desert tan/khaki body | yes |
| DL7 filled polys / hard edges (not photo paste) | yes |

## CLOSE AIR — redesign confirm
- **Full redraw:** new swept trapezoid wings, pointed nose + chin gun, bubble canopy, side scoop intakes, underwing hardpoints, twin verticals + horizontal stab — **not** a patch of the prior tube/BRUISE blob.
- Palette: black + dark gunmetal only (`BLK`/`VOID`/`STEEL` family) — **no purple / BRUISE / gold**.
- Scale: `AIR_Z = 6.20` (~3× ground-unit strip presence vs `FIG_SC` 2.70).
- Self-critique `_2x` / facings: aircraft dominates cell vs CELL/DEATH; reads as attack CAS.

## Assets / strips
- Generator: `game/tools/art/g10_coalition_samples.gd` (`revise_cycle: 10`)
- Ref provenance: `game/.plan/shots/G71_LOOK/ref_humvee_owner.jpg`
- Unit sheets: `units/x_technical_rocket.png`, `units/x_patron_cas.png` (+ masks/icons)
- Checklist: `game/.plan/shots/G71_LOOK/G10_SAMPLES_OWNER.txt`
- Strips: `strip_g10_coalition_samples.png` (+`_2x`), `strip_g10_coalition_facings.png` (+`_2x`)
- Locked strips byte-identical: `strip_g10_cell_vs_ghost_2x`, `strip_g10_safehouse_states_2x`

## Board
- FACT **255** `technical-ref-match`
- STATUS **256** `revise-tech+cas ready`
- NEED **257** owner re-approve **TECHNICAL + CLOSE AIR**
- HANDOFF **258** — CLOSE AIR confirmed **full redraw** (not patch)

## Explicitly not done
No CELL/DEATH/WALKER/SAFEHOUSE/HATCH drawer edits · no bulk catalog · no `world.gd` · **no commit**
