# ART10 Task 8 — approved-core lock + TECHNICAL/SAFEHOUSE defer

**Agent:** ORCH/ART10 · **Branch:** g71 · **Date:** 2026-11-24

## Owner directive

Remove SAFEHOUSE + TECHNICAL mockups from the look package; continue G10 with approved subjects; redesign Humvee/safehouse later.

## Locked

| Label | ID | Notes |
|-------|-----|--------|
| CELL | `x_cell_rifle` | Human A black FIG |
| DEATH | `x_death_strike` | Human A sealed |
| WALKER | `x_prototype_walker` | Human A sealed + launcher |
| CLOSE AIR | `x_patron_cas` | solid CAS |

## Deferred

| Subject | Status |
|---------|--------|
| TECHNICAL | DEFERRED — design-blueprint-later; CLAIM 248 RELEASED |
| SAFEHOUSE / HATCH | DEFERRED — states strip omitted |

## Look package

- Regenerated 2×2 samples strip (no TECHNICAL/SAFEHOUSE cells)
- Facings + CELL vs DEATH strips updated
- `strip_g10_safehouse_states*.png` removed
- Deferred PNGs removed from `assets/art/g10_coalition/`
- `G10_SAMPLES_OWNER.txt` marks deferred slots

## Bulk wave 1

- `game/tools/art/g10_coalition.gd` — 30 approved clones, 31 deferred ids
- `ArtCatalog.G5_GROUPS` includes `g10_coalition`
- Dispatch: `.superpowers/sdd/dispatch-art-bulk-approved.md`

## Board

FACT `art.look.approved.core` **268** · `art.technical.deferred` **269** · `art.safehouse.deferred` **270** · RELEASE **271** · STATUS bulk unlocked **272** · CLAIM/FACT bulk **273–274** · lock exception **275**
