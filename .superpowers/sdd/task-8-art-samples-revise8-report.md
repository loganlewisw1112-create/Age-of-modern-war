# ART10 Task 8 — look samples REVISE cycle 8

**Agent:** ART10 · **Branch:** g71 · **Claim:** seq 155 held · **No commit**

## Owner gate
Cycle-7 hard reject on CELL / DEATH / WALKER (“TRASH”). Regenerated cycle 8; NEED `g10.look.samples` re-opened for owner re-review.

## Owner notes (cycle 7) → actions
| KEEP | Action |
|------|--------|
| SAFEHOUSE | **DO NOT TOUCH** — drawer `_draw_safehouse` unchanged |
| CLOSE AIR | **DO NOT TOUCH** — drawer `_draw_patron_cas` unchanged |
| TECHNICAL | Leave (c7 HMMWV) — `_draw_technical` unchanged |

| FIX | Action |
|-----|--------|
| CELL | Call `g7_cn_fig.draw` with black operator kit (nvg + rifle) + small tan/red patches |
| DEATH | Same Human A body; sealed elite kit; gold debt patch; slightly taller `sc_mul` |
| WALKER | Same Human A plantigrade body (NOT digitigrade/mecha); sealed + launcher; taller `sc_mul` |
| Palette | All black + little patches; **NO purple** on CELL/DEATH/WALKER |

## Human A sources matched
| Source | Role |
|--------|------|
| `game/tools/art/g7_cn_fig.gd` | Soldier silhouette / stance / limb / aim-carry grammar (`FIG.draw`) |
| `game/tools/art/g7_cn_gear.gd` | Pack / chest / head / weapon drawers used by FIG |
| `game/tools/art/g7_cn_lib.gd` | DL7 `fpt` / `tube` / `blob` / `ramp` / `selout` |
| `game/tools/art/g7_cn_soldiers.gd` | Kit key grammar (suit/plate/helm/boot/web/head/weapon/bulk/rc) |

Optional scale hook: `FIG.draw(..., sc_mul)` default `1.0` — sample gate uses `FIG_SC`/`DEATH_SC`/`WLK_SC` only.

## Design bar
Copy Human A infantry construction; re-skin black Coalition identity via clothing/armor/detail only. Death/Walker = elite sealed variants of the same body, not a new stick/nano language.

## Per-subject changes
| Subject | Change |
|---------|--------|
| CELL | **Rewired** → `FIG.draw(_kit_cell, idle)` black + patches |
| TECHNICAL | **UNTOUCHED** |
| SAFEHOUSE | **UNTOUCHED** |
| DEATH | **Rewired** → `FIG.draw(_kit_death, idle)` sealed black + gold patch |
| CLOSE AIR | **UNTOUCHED** |
| WALKER | **Rewired** → `FIG.draw(_kit_walker, idle)` sealed + launcher |

## Assets / strips (overwritten in place)
- Generator: `game/tools/art/g10_coalition_samples.gd` (`revise_cycle: 8`)
- Assets: `game/assets/art/g10_coalition/`
- Checklist: `game/.plan/shots/G71_LOOK/G10_SAMPLES_OWNER.txt`
- Strips:
  - `game/.plan/shots/G71_LOOK/strip_g10_coalition_samples.png` (+ `_2x`)
  - `game/.plan/shots/G71_LOOK/strip_g10_coalition_facings.png` (+ `_2x`)
  - `game/.plan/shots/G71_LOOK/strip_g10_cell_vs_ghost.png` (+ `_2x`)
  - `game/.plan/shots/G71_LOOK/strip_g10_safehouse_states.png` (+ `_2x`)

## Board
- FACT **238** owner-notes-cycle7
- STATUS **239** revise8 ready
- NEED **240** owner re-approve
- CLAIM **155** still held

## Self-critique (post-regen `_2x` samples strip)
| Subject | bbox @2× | purple px | note |
|---------|----------|-----------|------|
| CELL | 120×146 | **0** | Human A FIG idle; black + tan/red patches |
| TECHNICAL | 150×152 | 0 | untouched c7 HMMWV |
| SAFEHOUSE | 144×154 | 0 | untouched |
| DEATH | 122×146 | **0** | sealed elite; gold patch |
| CLOSE AIR | 144×150 | 980 | **untouched** (owner KEEP; purple left as-is) |
| WALKER | 124×148 | **0** | sealed + launcher; plantigrade Human A legs |

1. CELL/DEATH/WALKER call the same Human A drawer as CN/operator infantry.
2. No purple on CELL/DEATH/WALKER.
3. SAFEHOUSE + CLOSE AIR code paths unchanged this cycle.
4. TECHNICAL unchanged this cycle.

## Explicitly not done (at revise8 write)
No bulk catalog · no `art_catalog.gd` · no `entity_layer` · no `world.gd` · no dog art · **no commit** (ORCH ships after owner approve)

## Lock (owner APPROVE cycle 8 — except TECHNICAL)
Owner initial: “all approved / all solid.” **Exception AFTER approve:** TECHNICAL Humvee rejected — redesign incoming.
ORCH FACT `art.look.approved.except_technical` **246** (supersedes **241**); NEED **240** closed **242**; RELEASE **155** **243**; CLAIM **248** TECHNICAL open; NEED **249**; STATUS partial **250**; bulk blocked **251**.
Locked: CELL/DEATH/WALKER/SAFEHOUSE/CLOSE AIR. TECHNICAL not look-final.
