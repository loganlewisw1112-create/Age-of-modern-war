# ART10 Task 8 — approved-core bulk wave2

**Agent:** ART10 · **Branch:** g71 · **Date:** 2026-11-24

## Scope

Unblock runtime use of approved-core art (CELL / DEATH / WALKER / CLOSE AIR families). No Humvee/safehouse redesign. No `world.gd`.

## Wave2 delivered

| Item | Result |
|------|--------|
| Fleet/army-style clones | **30** approved IDs (4 locked templates + **26** marked role variants) |
| Facings atlas | `strip_g10_bulk_facings.png` (+`_2x`) — all 30 × N/E/S/W |
| Kit strip | `strip_g10_bulk_kits.png` (+`_2x`) — marked roles only |
| Locked samples strip | `strip_g10_bulk_approved.png` (+`_2x`) — 2×2 CELL/DEATH/CAS/WALKER |
| Catalog | `g10_coalition` already in `ArtCatalog.G5_GROUPS`; sheets load at runtime |
| Deferred | **31** ids in `deferred_ids` only (TECHNICAL/SAFEHOUSE/HATCH) |
| Tests | `test_g10_content` **13/0** (new Step 4 coverage + deferred-placeholder OK) |
| Roster audit | approved art present; `orphan_art` = deferred-only (31) |

## Generator

`game/tools/art/g10_coalition.gd` — `bulk_wave: 2`; clones locked sample sheets then paints role marks (cleared from team mask).

## Leftover for g10.lock (Steps 6–9 polish)

1. Ghost set beyond infiltrator clone — Judge/Warden/Shade/Sergeant, Mk I–III, aces (`G10_GHOST_LOOK.md`)
2. Camo / state sheets (rest/walk/sprint/fire/hit, battery, shield)
3. Non-TECHNICAL vehicle/drone/building state sheets (Silent Rotor flip, etc.) — SAFEHOUSE still deferred
4. Final contact sheets + `orphan_art=0` (or deferred exception) + owner look gate

Locked look must not regress: CELL · DEATH · WALKER · CLOSE AIR.
