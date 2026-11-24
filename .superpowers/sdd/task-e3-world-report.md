# ORCH/VERIFY10 — E3 world.gd seam integration

**Agent:** ORCH (VERIFY10 Stage E3)  
**Branch:** g71  
**CLAIM:** `orch.e3.world` seq **217**  
**Pre-wire HEAD:** ~`f35a3763` (E2 verified 116/0; STATUS `e2-ready-for-e3`)

## Done-when

| # | Item | Status |
|---|------|--------|
| 1 | CLAIM `world.gd` exclusively | **done** seq 217 |
| 2 | Wire Coalition stage gate + deferred ticks/commands | **done** |
| 3 | human_a / other factions byte-stable outside Coalition paths | **done** (gates no-op unless Coalition; Exo Ghost/CG paths additive) |
| 4 | Smoke Godot 4.7.2 headless required suites | **done** 91/0 |
| 5 | Report + FACT `ship.e3` + close NEED 164/183 + HANDOFF + RELEASE | **done** |
| 6 | Commit world + tiny glue + report/board/progress; push github/g71 | **done** (this ship) |
| 7 | Return hash / smoke matrix / E4 remainder | see below |

## Wires

### `game/sim/world.gd` (ORCH exclusive)
- Preload: `Coalition10`, `CoalitionTech10`, `CoalitionBuildings10`, `GhostConductor10`, `Tunnels10`, `CivilianCells10`, `Ieds10`, `Patron10`, `WeldShop10`, `CoalitionDark10`, `G3bData`
- **NEED 183:** `validate_config` uses `G3bData.playable_stages_for(faction)` — Coalition stages **1–13**; other factions keep global `playable_now`
- **SYSTEM_ORDER** (G71 pattern, no parallel boot):
  - After `Progression`: `CoalitionTech10` → `CoalitionBuildings10` → `Coalition10`
  - After combat/wounds block: `Tunnels10` → `CivilianCells10` → `Ieds10` → `Patron10` → `WeldShop10` → `CoalitionDark10`
  - After `Exo`: `GhostConductor10` (mission advance; GhostExo + CounterGhost remain via `Exo.tick`)
- **ExoArmory10:** API-only (no `tick`); outfit/bind called from tests/UI — no SYSTEM_ORDER slot
- **CounterGhost10:** already ticked via `Exo.counter_ghost_tick` — no duplicate world entry

### Tiny glue (NEED 164 + AI hook)
| File | Change |
|------|--------|
| `progression.gd` | `CoalitionTech10.validate_research` on research; `_playable(stage, faction)` via `G3bData.playable_stages_for` |
| `production.gd` | `CoalitionTech10.gate_queue(fid, item)` (no building_id — avoids recurse) |
| `construction.gd` | `CoalitionTech10.gate_build` on build |
| `market.gd` | black-market: `forbidden_reason` when Coalition active (no `gate_market` recurse) |
| `ai_controller.gd` | `CoalitionAi10.choose_operation` after Doctrine when `Coalition10.active` |
| `ghost_conductor10.gd` | Drop nested `GhostExo10.tick` — Exo owns GhostExo drain |

## Smoke matrix (Godot 4.7.2 headless)

| Suite | Pass | Fail | Exit |
|-------|------|------|------|
| test_g10_stage | 14 | 0 | 0 |
| test_g10_modes | 8 | 0 | 0 |
| test_g10_tech | 6 | 0 | 0 |
| test_g10_ghost | 15 | 0 | 0 |
| test_g10_counterghost | 5 | 0 | 0 |
| test_g10_exo_armory | 7 | 0 | 0 |
| test_g10_dark | 6 | 0 | 0 |
| test_g10_ai | 8 | 0 | 0 |
| test_exo | 4 | 0 | 0 |
| test_lpmode7 | 18 | 0 | 0 |

**Totals:** 10 suites · **91 pass / 0 fail** · 0 SCRIPT ERROR

Logs: `.superpowers/sdd/e3-*.log` · matrix `.superpowers/sdd/e3-smoke-matrix.json`

## Board

- CLAIM `orch.e3.world` **217**
- FACT `ship.e3` (closes NEED **164** tech wire, NEED **183** stage gate)
- HANDOFF → E4 evidence/soak/package
- RELEASE `world.gd`

## ART

Look gate still open (CLAIM 155 / NEED 216). **ART strips left unstaged.**

## Remaining E4 (Task 22–23)

1. Expanded smoke + G71 done-when smoke + full suite evidence
2. Stage 1–13 opener soak + doctrine soak tools
3. Two-run hashes (Stage 3/8/12 + LP profiles)
4. AI-vs-AI soaks; 100+ Death-squad stress; perf remasure
5. Owner ART catalog approve → package `g10.lock` + README/PLAY_ME/ROADMAP/SCOPE close
