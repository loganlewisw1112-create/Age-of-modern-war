# G10 kickoff (paste into NEW chat)

Owner APPROVED G10 full execution — **Subagent-Driven + max safe parallelism**. Start immediately. No further scope questions unless Stop-if.

## Authorities
- Scope (APPROVED): `game/docs/G10_SCOPE.md`
- Plan: `docs/superpowers/plans/2026-11-23-g10-shadow-coalition.md`
- Ghost look: `game/docs/G10_GHOST_LOOK.md`
- Exo Armory: `game/docs/G10_EXO_ARMORY.md`
- Human A dogs: `game/docs/G10_HUMAN_A_DOG_LOOK.md`
- Board: `game/.plan/upgrade_board/`
- Ledger: `.superpowers/sdd/g10-progress.md`
- Branch: `g71` (after `pre_g10.lock`)

## Parallelism mandate (owner)

**Do as much in parallel as possible** without file overlap, CLAIM fights, or hash races.

1. Cap **≤6 live** implementers (board roster). Queue the rest.
2. **Never** two agents on the same path set. Read last ~40 `board.jsonl` lines before every CLAIM.
3. **Serialize only these seams** (ORCH owns integration):
   - `game/sim/world.gd` — ORCH only
   - `game/content/factions.json` — FOUND10 only
   - `game/sim/systems/capture71.gd` — MECH10 only
   - `game/sim/systems/exo.gd` — GHOST10 first, then CG10 (NEED/handoff)
   - LP entry / mode files — MODE10 only
4. Prefer **public APIs** across pillars (call, don’t edit neighbor files). If you need a foreign file → board **NEED**, wait for RELEASE.
5. Art generators may run parallel to sim if they only touch their art group paths.
6. Packages: **one at a time** (DLL lock). Tests: prefer `--only=` per pillar; full smoke at E3/E4 under ORCH.
7. Controller may dispatch **multiple Task implementers in parallel** when CLAIMs are disjoint (unlike single-threaded SDD default). Still: one reviewer per finished task; no two writers on one CLAIM.

## Wave parallelism map

| Wave | Mode |
|------|------|
| **E0** | Serial: Task 0 board freeze + CLAIM map |
| **E1** | Mostly serial: FOUND10 → IDENT10 (IDENT may start after FOUND registry FACT) |
| **E2** | **Max parallel** (example live set of 6): `ROSTER10/CORE10` · `ART10` · `MECH10` · `GHOST10` · `DOG10` · `TECH10` — rotate in `BLD10`, `ARMORY10`, `CG10`, `AI10`, `MODE10`, `DARK10` as CLAIMs free |
| **E3** | Serial/light parallel: ORCH seams + VERIFY10 |
| **E4** | Serial: smoke/hash/soak/package → `g10.lock` |

**Safe early parallel (after E1 registry FACT):** DOG10 (Human A art only) can run beside almost anything. ART10 samples can start once roster manifest IDs exist. ARMORY10 after BLD10 Ghost campus shell OR with explicit interface stubs from BLD10.

## Protocol
- Subagent-Driven: fresh implementer per task + task review; ledger `.superpowers/sdd/g10-progress.md`
- CLAIM / RELEASE / FACT / HANDOFF on `upgrade_board`
- ORCH: commits, push `github/g71`, `package_g71.ps1`, README/PLAY_ME every ship
- Never weaken Done-when

## Start now
1. Task 0: Stage E roster + **non-overlapping CLAIM map** posted to board (include ARMORY10, DOG10).
2. E1 FOUND10 → IDENT10.
3. Immediately open E2 parallel set (≤6) on disjoint claims.
4. E3 → E4 `g10.lock`.

Godot: `%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe`

Owner authorized commits / push / package for G10.
