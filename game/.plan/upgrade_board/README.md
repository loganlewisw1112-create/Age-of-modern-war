# UP71 permanent semantic messaging board

Standing OS for G7.1 → G8 → G9 → Pre-G10 → **G10 Shadow Coalition** → G14+. Append-only JSONL: `board.jsonl` (one JSON object per line).

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
7. Execution is **local** with parallel board agents (≤6 live). Cloud is off unless ORCH farms a non-perf draft.
8. Prefer public APIs across pillars. Foreign path needed → board **NEED**, wait for RELEASE.
9. Packages one-at-a-time; prefer `--only=` pillar tests; full smoke at E3/E4 under ORCH.

### Active roster (UP71 Stage E — G10 Shadow Coalition)

Frozen scope: `game/docs/G10_SCOPE.md` · plan: `docs/superpowers/plans/2026-11-23-g10-shadow-coalition.md`  
Kickoff: `.superpowers/sdd/G10_KICKOFF.md` · Ghost look: `G10_GHOST_LOOK.md` · Armory: `G10_EXO_ARMORY.md` · Dogs: `G10_HUMAN_A_DOG_LOOK.md`

| ID | Role |
|----|------|
| ORCH | Dispatch, `world.gd` seams, integ, smoke, soak, commit, package, README, push `github/g71` |
| FOUND10 | Content loader, faction registry, Coalition-only stage API, audit tests |
| IDENT10 | `coalition10.gd`, doctrine state/telemetry, intent-first UI contracts |
| ROSTER10 | G10 definition fragments; subclaims RAID10 / CORE10 / LATE10 by file |
| ART10 | Sample gate, four-facing catalog, icons, hidden/revealed, Ghost look sheets |
| MECH10 | Tunnels, civilians, IEDs, patron, weld/capture; exclusive `capture71.gd` |
| TECH10 | Buy/steal/unseal + all denial gates |
| BLD10 | Coalition structures, hidden/revealed/damage, Ghost campus shell |
| GHOST10 | Ghost anatomy, mission lifecycle, Conductor; first owner of `exo.gd` |
| ARMORY10 | Exo Armory building, unlock/outfit UX, bay caps |
| CG10 | Human A Counter-Ghost defs + counterplay; second owner of `exo.gd` after GHOST10 handoff |
| DOG10 | Human A `g71_robot_dog` complete art redesign |
| AI10 | Coalition doctrine adapter over shipped Pre-G10 AI |
| MODE10 | Skirmish stage filtering + Coalition LP profile (LP files exclusive) |
| DARK10 | Blackout, Hollow Ground, Mirror Fortress, Dead Radio only |
| VERIFY10 | Independent smoke/hash/soak/perf; no feature edits without ORCH NEED/CLAIM |

**Serialized seams (never parallel-write):** `game/sim/world.gd` (ORCH) · `game/content/factions.json` (FOUND10) · `game/sim/systems/capture71.gd` (MECH10) · `game/sim/systems/exo.gd` (GHOST10 → CG10) · LP entry/mode files (MODE10).

Max **6** live implementers; CLAIMs must be path-disjoint. Rotate queued agents as RELEASE frees slots.

### Historical roster (Stages A–D — closed)

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
| PEAK60 / HIVE9+ / COUNT9+ / COMBAT9+ / SKIRM9+ / AI9 / ECON9 / PACE71 | Pre-G10 Depth Bridge | D |

### Ship cadence
HANDOFF → ORCH verify → README refresh → commit → `package_g71.ps1` → push → FACT `ship.<sha>` + `readme.synced`.
