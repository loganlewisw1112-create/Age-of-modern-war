# Dispatch — ART10 bulk (approved-core only)

**Branch:** g71 · **Owner:** 2026-11-24 · **Agent:** ART10 / ORCH

## Gate (closed)

- FACT `art.look.approved.core` — CELL / DEATH / WALKER / CLOSE AIR locked
- FACT `art.technical.deferred` + `art.safehouse.deferred` — redesign later (not locked)
- CLAIM 248 TECHNICAL **RELEASED**; bulk **unlocked** for approved unit art only

## Wave 1 (started this ship)

- Generator: `game/tools/art/g10_coalition.gd`
- Catalog: `g10_coalition` added to `ArtCatalog.G5_GROUPS`
- ~30 approved-family IDs cloned from locked sample drawers (4-facing idle)
- 31 deferred IDs listed in manifest (`deferred_ids`) — no locked mockups
- Strip: `game/.plan/shots/G71_LOOK/strip_g10_bulk_approved.png`

## Still owed (Task 8 Steps 4–9) — approved only

1. Coverage tests (catalog / facings / masks) for approved IDs; deferred IDs allowed as placeholders
2. Role kit differentiation (cell AT/sapper/medic, Death assault/recon, Shadow/Anchor) beyond clone
3. Ghost set (Judge/Warden/Shade/Sergeant, Mk bands, aces) — `G10_GHOST_LOOK.md`
4. Camo / state sheets for approved Ghosts
5. Non-TECHNICAL vehicle/drone/building states that are **not** SAFEHOUSE family (or keep deferred)
6. Contact sheets + orphan_art audit for approved scope
7. Final catalog look gate before `g10.lock` (with deferred exception)

## Explicitly out of this dispatch

- TECHNICAL Humvee redesign / owner-ref work
- SAFEHOUSE / HATCH redesign
- Do not re-add deferred subjects to owner look strips until new blueprint

## Lock note

`g10.lock` / Done-when #13a (raider + technical + hidden structure) carries owner **deferred exception** — see `.superpowers/sdd/g10-lock-deferred-exception.md`.
