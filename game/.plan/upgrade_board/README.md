# UP71 permanent semantic messaging board

Standing OS for G7.1 lock → G8 → G9 → **Pre-G10** → G10+. Append-only JSONL: `board.jsonl` (one JSON object per line).

## Protocol

Every agent **must** post before starting work, on progress, and on handoff.

```json
{"seq":N,"ts":"ISO-8601","from":"AGENT_ID","to":"orch|AGENT_ID|*","type":"STATUS|FACT|NEED|HANDOFF|CLAIM|RELEASE","topic":"kebab.topic","data":{}}
```

### Types
- **CLAIM** — exclusive ownership of paths (`data.paths`, `data.slice`). Wait if another CLAIM overlaps and no RELEASE.
- **RELEASE** — done with claimed paths.
- **FACT** — measured evidence (test RESULT, FPS_SUMMARY, package tag, `readme.synced`).
- **NEED** — blocked; name owner + why.
- **STATUS** — progress heartbeat.
- **HANDOFF** — slice complete; `next_action` for ORCH.

### Rules
1. Read the last ~40 lines of `board.jsonl` before CLAIM.
2. Never edit another agent's claimed paths.
3. ORCH alone commits + `package_g71.ps1` + pushes `github` + refreshes root `README.md` (+ PLAY_ME).
4. Every ship FACT must include `readme: true` (or NEED if blocked). Push without README update = protocol fail.
5. Never weaken frozen Done-when. No owner questions unless Stop-if.
6. Guidebook README voice on every ship.
7. Execution is **local** with parallel board agents. Cloud is off unless ORCH farms a non-perf draft.

### Active roster (UP71 Stage D — Pre-G10 Depth Bridge)

Frozen scope: `game/docs/PRE_G10_SCOPE.md` · plan: `docs/superpowers/plans/2026-11-23-pre-g10.md`

| ID | Role |
|----|------|
| ORCH | Dispatch, integ, smoke, soak, commit, package, README, push |
| PEAK60 | Remeasure each integ; no feature work unless FPS regress |
| HIVE9+ | Machine art ≥60, modular/evolve depth, glow |
| COUNT9+ | 13 counters play-paths + coalitions bridge (AI9 calls public API only). Counter EW/EMP hooks that touch `machine_ew7.gd`: post **NEED** to COMBAT9+ — not in COUNT9+ CLAIM/coord (see board FACT `pre_g10.claim.machine_ew7`, seq 106). |
| COMBAT9+ | Forts, EW depth (`machine_ew7.gd` exclusive CLAIM), crews/breakdown, ballistics breadth |
| SKIRM9+ | Skirmish setup `director_adapt` toggle, siege attack-move |
| AI9 | Adapt, named generals, diplomacy, intel-diff, CoC ops |
| ECON9 | Resources, trade, territory/civ, research, black market, upgrades |

Serialize **D2 AI9 ↔ D3 ECON9** on diplomacy + Machine-coalition seam (`count9.gd` coalitions owned by COUNT9+).

### Historical roster (Stages A–C — closed)

| ID | Role | Stage |
|----|------|-------|
| POLISH71 | Latch/jammer, body-piles, Glass, fleet UX | A |
| VERIFY71 | Full suite + hash + soaks | A |
| ROT8 | View rotation | B |
| ART8 | 4-side art generators | B |
| ANIM8 | Animation overhaul | B |
| PRES8 | Director PiP, reel, creep timelapse | B |
| HIVE9 | Machine thin vertical (G9) | C |
| COUNT9 | Thirteen counters thin (G9) | C |
| COMBAT9 | Terrain, ballistics thin (G9) | C |
| SKIRM9 | Tide siege / director_adapt flag (G9) | C |

### Ship cadence
HANDOFF → ORCH verify → README refresh → commit → `package_g71.ps1` → push → FACT `ship.<sha>` + `readme.synced`.
