# Dispatch — ART10 bulk (approved-core only)

**Branch:** g71 · **Owner:** 2026-11-24 · **Agent:** ART10 / ORCH

## Gate (closed)

- FACT `art.look.approved.core` — CELL / DEATH / WALKER / CLOSE AIR locked
- FACT `art.technical.deferred` + `art.safehouse.deferred` — redesign later (not locked)
- CLAIM 248 TECHNICAL **RELEASED**; bulk **unlocked** for approved unit art only

## Wave 1 (shipped)

- Generator: `game/tools/art/g10_coalition.gd`
- Catalog: `g10_coalition` added to `ArtCatalog.G5_GROUPS`
- ~30 approved-family IDs cloned from locked sample drawers (4-facing idle)
- 31 deferred IDs listed in manifest (`deferred_ids`) — no locked mockups
- Strip: `game/.plan/shots/G71_LOOK/strip_g10_bulk_approved.png`

## Wave 2 (shipped — runtime unblock)

- Fleet/army-style role marks on 26 of 30 approved clones (templates stay locked pixels)
- Facings atlas: `strip_g10_bulk_facings.png` (+`_2x`)
- Kit strip: `strip_g10_bulk_kits.png` (+`_2x`)
- Step 4 tests in `test_g10_content.gd` — approved coverage + deferred placeholders OK
- FACT `ship.art.bulk.approved.wave` — see board

## Still owed (Steps 6–9 polish) — approved only

1. Ghost set (Judge/Warden/Shade/Sergeant, Mk bands, aces) — `G10_GHOST_LOOK.md`
2. Camo / state sheets for approved Ghosts
3. Non-TECHNICAL vehicle/drone/building states that are **not** SAFEHOUSE family (or keep deferred)
4. Contact sheets + orphan_art audit for approved scope (deferred exception OK)
5. Final catalog look gate before `g10.lock` (with deferred exception)

## Explicitly out of this dispatch

- TECHNICAL Humvee redesign / owner-ref work
- SAFEHOUSE / HATCH redesign
- Do not re-add deferred subjects to owner look strips until new blueprint

## Lock note

`g10.lock` / Done-when #13a (raider + technical + hidden structure) carries owner **deferred exception** — see `.superpowers/sdd/g10-lock-deferred-exception.md`.
