# UP71 permanent semantic messaging board

Standing OS for G7.1 lock → G8 → G9 → G10+. Append-only JSONL: `board.jsonl` (one JSON object per line).

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

### Active roster (UP71 Stage A→C)
| ID | Role |
|----|------|
| ORCH | Dispatch, integrate, suite/soak, commit, package, README currency, push |
| PEAK60 | Frame budget: static records, invisible LOD, HUD cull, native-if-wins |
| POLISH71 | Latch/jammer, body-piles, Glass thermal/rain, fleet ~150 UX |
| VERIFY71 | Full suite + hash + soaks + Done-when evidence packs |
| ROT8 | View rotation (G8) |
| ART8 | 4-side art generators (G8) |
| ANIM8 | Animation overhaul (G8) |
| PRES8 | Director PiP, reel, creep timelapse (G8) |
| HIVE9 | Machine overhaul (G9) |
| COUNT9 | Thirteen counters (G9) |
| COMBAT9 | Destructible terrain, ballistics, EW, forts, crews (G9) |
| SKIRM9 | LP hive → skirmish (G9) |

### Ship cadence
HANDOFF → ORCH verify → README refresh → commit → `package_g71.ps1` → push → FACT `ship.<sha>` + `readme.synced`.
