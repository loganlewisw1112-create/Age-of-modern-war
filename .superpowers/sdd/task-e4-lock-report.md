# ORCH/VERIFY10 — E4 Task 23 lock (`g10.lock`)

**Agent:** ORCH/VERIFY10 (Stage E4 lock)  
**Branch:** g71 → `github/g71`  
**Godot:** 4.7.2 WinGet console headless  
**Pre-lock HEAD:** `031a6e60` (wave3 FACT)  
**Lock file:** `.superpowers/sdd/g10.lock`

## Done-when posture

Closes Task 23 with owner **deferred look exception** for TECHNICAL / SAFEHOUSE / HATCH (Done-when **#13a** only). Does **not** weaken #1–12, #13b, #14–16. Ghost strips remain optional owner look (non-blocking).

## Smoke matrix (fresh lock-prep)

| Suite | Pass | Fail | Exit | SCRIPT ERROR |
|-------|------|------|------|--------------|
| test_g10_stage | 14 | 0 | 0 | 0 |
| test_g10_modes | 8 | 0 | 0 | 0 |
| test_g10_tech | 6 | 0 | 0 | 0 |
| test_g10_ghost | 15 | 0 | 0 | 0 |
| test_g10_counterghost | 5 | 0 | 0 | 0 |
| test_g10_exo_armory | 7 | 0 | 0 | 0 |
| test_g10_dark | 6 | 0 | 0 | 0 |
| test_g10_ai | 8 | 0 | 0 | 0 |
| test_g10_buildings | 8 | 0 | 0 | 0 |
| test_g10_content | 15 | 0 | 0 | 0 |
| test_g10_mechanics | 6 | 0 | 0 | 0 |
| test_exo | 4 | 0 | 0 | 0 |
| test_lpmode7 | 18 | 0 | 0 | 0 |
| test_lp_save71 | 2 | 0 | 0 | 0 |

**Totals:** 14 suites · **122 pass / 0 fail** · 0 SCRIPT ERROR in RESULT lines  

Logs: `.superpowers/sdd/lockprep/fresh-*.log` · matrix `.superpowers/sdd/lockprep/fresh-smoke-matrix.json`  
Command form: `godot --headless --path game -s res://tests/run_tests.gd -- --only=<suite>` (never `--filter`).

## Two-run hashes

| Scenario | Harness | Result |
|----------|---------|--------|
| Stage 3 @600 | `tools/g10_e4_stage_hash.gd` | **MATCH** `09ae27b0…a8b2fd` |
| Stage 8 @600 | same | **MATCH** `8f2f356e…3135b9` |
| Stage 12 @600 | same | **MATCH** `65da9d7a…45f1f7` |
| LP profiles (suite) | `test_g10_modes` / `test_lp_save71` | **PASS** |

Evidence: `game/.plan/upgrade_board/evidence/g10_e4_stage_hash_lock.log`

## AI soak / 100-squad

| Item | Status |
|------|--------|
| `tools/g10_e4_ai_soak.gd` 900 ticks | **PASS** `ok=true` (coalition_vs_human_a + coalition_vs_machine); no SCRIPT ERROR in lock log |
| `tools/g10_e4_100_squad_stress.gd` | **PASS** spawned_squads=100, units=400, pop_cap_floor=500 |
| Peak remasure | **SKIP** — no G10 peak tool (prior G71 cite still held) |

Evidence: `…/g10_e4_ai_soak_lock.log`, `…/g10_e4_100_squad_stress_lock.log`

## ART / deferred exception

- **Locked look:** CELL / DEATH / WALKER / CLOSE AIR (`art.look.approved.core`)
- **Shipped bulk:** wave2 + wave3 (`4945e77e`) — Ghost Wing + camo + CLOSE AIR states
- **Deferred (not blocking):** TECHNICAL Humvee family, SAFEHOUSE, HATCH — see `.superpowers/sdd/g10-lock-deferred-exception.md`
- **Optional remaining owner look:** Ghost strip contact sheet only (non-blocking)

## Package / docs

- Package: `powershell -NoProfile -File game/.plan/package_g71.ps1 -Note g10.lock`
- SCOPE → **CLOSED (`g10.lock`)**; README / PLAY_ME / ROADMAP updated
- Board FACT `ship.g10.lock` (+ `g10.lock`, `ship.<sha>`, `readme.synced`)

## Optional leftover (non-blocking)

1. Ghost strips optional owner look
2. TECHNICAL / SAFEHOUSE / HATCH redesign (design-blueprint later)
3. Full Task 21–22 long soak tools / fresh peak remasure if owner wants beyond closest probes

## Ship record

- **Commit:** `5f55236c`
- **Package:** `C:\Users\logan\Downloads\Age of Modern War\RTS_Age_of_Modern_War_G71_2026-11-24_5f55236c`
- **Zip:** `...\RTS_Age_of_Modern_War_G71_2026-11-24_5f55236c.zip`
- **PCK_MD5:** `8d6db9cc7946dfe517035f5b34d7f1ed`
- **Board:** FACT `ship.g10.lock` seq **291**
