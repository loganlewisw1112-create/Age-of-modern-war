# ORCH/VERIFY10 — E4 batch A (pre-lock)

**Agent:** ORCH/VERIFY10 (Stage E4 batch A)  
**Branch:** g71  
**CLAIM:** `orch.e4.batch_a` seq **224**  
**Pre-run HEAD:** `a6aa44fc` (post-E3 `ffe627d1` + README follow-up)  
**Godot:** 4.7.2 WinGet console headless  
**Lock:** **NOT** written — ART look not approved; no `g10.lock` / final package claim

## Done-when posture

Batch A measures evidence only. Does **not** close Task 23 (ART approve → package → README/PLAY_ME/SCOPE). Does **not** weaken Done-when rows.

## Smoke matrix (expanded)

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
| test_g10_buildings | 8 | 0 | 0 |
| test_g10_content | 11 | 0 | 0 |
| test_g10_mechanics | 6 | 0 | 0 |
| test_exo | 4 | 0 | 0 |
| test_lpmode7 | 18 | 0 | 0 |
| test_lp_save71 | 2 | 0 | 0 |

**Totals:** 14 suites · **118 pass / 0 fail** · 0 SCRIPT ERROR in suite RESULT lines

Logs: `.superpowers/sdd/e4-*.log` · matrix `.superpowers/sdd/e4-smoke-matrix.json`

Suite smoke includes LP two-run hash (`test_lp_profile_two_run_hash_short` PASS), stage openers/raider 1200 soak, late/100-squad **config** caps, doctrine/AI unit tests.

## Two-run hashes

| Scenario | Harness | Result |
|----------|---------|--------|
| Stage 3 @600 | `tools/g10_e4_stage_hash.gd` | **MATCH** `09ae27b0…a8b2fd` |
| Stage 8 @600 | same | **MATCH** `8f2f356e…3135b9` |
| Stage 12 @600 | same | **MATCH** `65da9d7a…45f1f7` |
| LP human_a @200 | `test_g10_modes` | **PASS** (suite) |
| LP shadow_coalition @200 | `test_g10_modes` | **PASS** (suite) |
| Non-Coalition / tunnels | `test_g10_content` / `test_g10_mechanics` | **PASS** (suite) |

Evidence: `game/.plan/upgrade_board/evidence/g10_e4_stage_hash.log`  
**Gap closed by tiny harness:** plan’s Task-22 stage hash tool was absent; added minimal `g10_e4_stage_hash.gd` (ORCH verify only).

## AI-vs-AI / doctrine soak

| Item | Status |
|------|--------|
| Plan `g10_doctrine_soak.gd` | **MISSING** (Task 21) |
| Closest: `tools/g10_e4_ai_soak.gd` 900 ticks Coalition AI vs Human A / Machine | invariants OK (`ok=true`, doctrine=`bleed`) |
| Closest: `tools/g71_pre_g10_coalition_soak.gd` | **PASS** `ok=true` |
| Closest: `test_g10_ai` 8/0 | **PASS** |

**Blocker (non-fatal to suite, blocks clean Done-when soak):** AI soak logged **7× SCRIPT ERROR** in `sim/ai/ai_air.gd:113` (`String(ud.aircraft)` when aircraft field is non-string) during `w.step()` AI think with Coalition `ai:true`. Soak still finished without crash/neg-stock/ownership fail. Needs AI10/ORCH tiny harden before claiming soak Done-when clean — **not** a world.gd E3 wire break.

Evidence: `game/.plan/upgrade_board/evidence/g10_e4_ai_soak.log`, `…/g10_e4_pre_g10_coalition_soak.log`

## 100-squad / Death stress

| Item | Status |
|------|--------|
| Plan `g10_100_squad_soak.gd` | **MISSING** (Task 22) |
| Config `rules.g10_100_squad` | present (LATE10); `test_g10_stage` caps **PASS** |
| Closest: `tools/g10_e4_100_squad_stress.gd` | **PASS** — spawned_squads=100, units=400, pop_cap_floor=500, ordinary pop_cap_max=120 unchanged |

Evidence: `game/.plan/upgrade_board/evidence/g10_e4_100_squad_stress.log`

## Peak remasure

**SKIP** — no G10/E4 peak remasure tool under `game/tools`. Prior G71 cites only (`upgrade_board/evidence/remasure_cite_note.txt`: 2k p10=69.9 ≥60; peak p10=42.8 ≥30 amended). Fresh 2k/10k G10 remasure still owed before lock if Done-when requires post-E3 numbers.

## Harness gaps (Task 21–22 still open)

- `g10_donewhen_smoke.ps1`
- `g10_stage_soak.gd` / `g10_doctrine_soak.gd`
- `g10_100_squad_soak.gd` (full long stress)
- Peak remasure runner for G10

Batch A shipped **closest** probes only (`g10_e4_*`).

## ART

CLAIM 155 / NEED 216 cycle3 `pause_for_owner`. **ART dirt left unstaged.** No catalog approve → no package.

## Blockers for lock

1. **Owner ART look approve** (NEED 216) → bulk catalog → Task 23
2. **Package** `package_g71.ps1 -Note g10.lock` + PLAY_ME include
3. **README / PLAY_ME / ROADMAP / G10_SCOPE** close (`CLOSED (g10.lock)`)
4. **ai_air SCRIPT ERROR** on Coalition AI think (soak cleanliness)
5. Optional: full doctrine/stage soak tools + fresh peak remasure if owner requires beyond closest probes

## Board

- CLAIM `orch.e4.batch_a` **224**
- FACT `verify.e4.batch_a` (this report)
- STATUS `e4-awaiting-art-for-lock`
- RELEASE `orch.e4.batch_a` after FACT (slot free; lock gated on ART)

## Commit scope

Report + board + progress + `g10_e4_*` harnesses + evidence logs only. **No** `world.gd`. **No** ART assets. **No** `g10.lock`.
