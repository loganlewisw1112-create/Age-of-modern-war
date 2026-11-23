# Wave 6 semantic messaging board

Append-only JSONL: `board.jsonl` (one JSON object per line).

## Protocol

Every agent **must** post before starting work, on progress, and on handoff.

```json
{"seq":N,"ts":"ISO-8601","from":"AGENT_ID","to":"orch|AGENT_ID|*","type":"STATUS|FACT|NEED|HANDOFF|CLAIM|RELEASE","topic":"kebab.topic","data":{}}
```

### Types
- **CLAIM** — take exclusive ownership of paths (`data.paths`, `data.slice`). Wait if another CLAIM overlaps and no RELEASE.
- **RELEASE** — done with claimed paths.
- **FACT** — measured evidence (test RESULT, FPS_SUMMARY, package tag).
- **NEED** — blocked; name owner + why.
- **STATUS** — progress heartbeat.
- **HANDOFF** — slice complete; next_action for orch.

### Rules
1. Read the last ~40 lines of `board.jsonl` before CLAIM.
2. Never edit another agent's claimed paths.
3. Orch alone commits + `package_g71.ps1` + pushes github + refreshes root `README.md`.
4. Never weaken frozen Done-when. No questions to the owner unless Stop-if.
5. Guidebook README voice on every ship.

### Active roster
| ID | Slice |
|----|--------|
| ORCH | Phase 0, commits, packages, dispatch |
| ART71-SIEGE | Phase 1A siege Machines |
| ART71-SPECIAL | Phase 1B Reclaimer / Glass / Conductor |
| ART71-FLEET | Phase 1C robot fleet |
| ART71-FX | Phase 1D–1F CN/effects/gore (after 1A–1C or non-overlapping) |
| ANIM71 | Phase 2 E4 (starts 2.1 after Phase 0; avoid art asset paths) |
