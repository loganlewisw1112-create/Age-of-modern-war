# ART10 Task 8 — TECHNICAL Humvee LAST CHANCE (enclosed slant-back)

**Agent:** ART10 · **Branch:** g71 · **No commit** · **Cycle:** 13

## Owner gate
TECHNICAL rear still rejected as open box. This pass rewrites `_draw_technical` rear/cabin to match owner-ref v2 enclosed fastback. CLOSE AIR / CELL / DEATH / WALKER / SAFEHOUSE / HATCH locked — zero drawer edits.

## Before → After (rear)

| | Before (revise12) | After (revise13 last-chance) |
|--|-------------------|------------------------------|
| Rear volume | Read as open cargo / pickup bed (flat high cabin then drop; dark cavity cues) | **Enclosed fastback** — continuous bright slant roof from cabin join → short vertical tail |
| Side walls | Tall box walls + tiny cut corner | Continuous quads with **diagonal top edge** flush to cabin |
| Tail | Large glass-looking panel (cavity cue) | Solid short vertical tail + thin latch only |
| Cab-back | Vertical bulkhead cue (pickup cab wall) | **No cab-back bulkhead** — volume filled by slant plates |
| Wheels | Near flank + far-front peek | **Far-side wheels fully hidden** |
| Ref | `ref_humvee_owner.jpg` | `ref_humvee_owner_v2.jpg` (owner photo copied) |

## Design (owner-ref v2)
- Wide low HMMWV stance, desert tan, dual windshield, hood loops, tubular brush guard
- X-doors (high-contrast emboss), mirrors, whip antenna
- Roof circular turret center-front + .50 + 3-sided gun shield
- Rear: flat cabin roof stub → steep enclosed slant → short vertical tail; recessed near-side panel (tan, not void)
- Scale: `VEH_Z` **3.90** unchanged (revise12 ballpark)

## Scope
| Subject | Action |
|---------|--------|
| **TECHNICAL** (`x_technical_rocket`) | **REWRITTEN** `_draw_technical` + wheel helpers |
| CLOSE AIR / CELL / DEATH / WALKER / SAFEHOUSE / HATCH | **UNTOUCHED** (SHA-256 identical sheets) |

## Hash confirmation (locked subjects)
Pre/post SHA-256 match: `x_patron_cas`, `x_cell_rifle`, `x_death_strike`, `x_prototype_walker`, `x_safehouse`, `x_safehouse_hidden`.

## Self-critique vs ref
- Regenerated samples + facings strips (1x+2x).
- Read `_critique_tech_3x.png` + `_critique_tech_facings.png` + per-facing `_face_tech_*.png` against `ref_humvee_owner_v2.jpg`.
- Roof-height profiles across all 4 facings show **continuous descending slope** aft of cabin (not flat bed plateau).
- Compared strip TECHNICAL rear to attached owner ref: enclosed slant-back / fastback — **not** open cargo box.
- Redrew once mid-pass (removed vertical bulkheads that recreated cab-back + cavity read) before HANDOFF.

## Assets / strips
- Generator: `game/tools/art/g10_coalition_samples.gd` (`revise_cycle: 13`)
- Ref: `game/.plan/shots/G71_LOOK/ref_humvee_owner_v2.jpg`
- Unit: `game/assets/art/g10_coalition/units/x_technical_rocket.png`
- Strips: `strip_g10_coalition_samples.png` (+`_2x`), `strip_g10_coalition_facings.png` (+`_2x`)
- Checklist: `game/.plan/shots/G71_LOOK/G10_SAMPLES_OWNER.txt`

## Board
- FACT `tech-enclosed-slant` (this ship)
- STATUS `revise13 last-chance ready`
- NEED owner **FINAL TECHNICAL** approve only
- HANDOFF — rear enclosed slant-back; CLOSE AIR untouched; strip compared to owner ref v2

## Explicitly not done
No CLOSE AIR / CELL / DEATH / WALKER / SAFEHOUSE / HATCH drawer edits · no bulk catalog · no `world.gd` · **no commit**
