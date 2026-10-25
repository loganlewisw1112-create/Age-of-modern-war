# G6-AI7-DOC: operating guide
Read `.plan/agents/prompts/G6_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G6 §0-§2, §5, §6, §16 (doctrine), §3.6 tags. **Plan:** PLAN_G6 §9, D40.
**Board / bus id:** `AI7-DOC`. **Budget: MAX_TOKENS 750000, MAX_TOOL_CALLS 140** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g6/test_doctrine.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### AI7-DOC: doctrine engine: AI that fights like a military
- **Role:** the strategic / operational / tactical layers, the special-ops and exfil missions, and reason-tag logging. Every AI fights with real doctrine.
- **Owns:** see CONTRACTS_G6 §1 row AI7-DOC (`sim/ai/doctrine/**`, `sim/systems/ops_missions.gd`, test_doctrine).
- **Inputs:** `ops.gd` / `ops_missions.gd` (G2 missions), ARMY6's company/army API, ELEV (height/LOS), MECH6a (cover, garrison, mines), the existing AI (`ai_army`, `ai_tactics`: read; CR AI7-USE for hooks).
- **Tasks (in order):**
  1. `Doctrine.think` skeleton + `plan_for`. Post `fact doctrine.api_ready` (partial).
  2. Tactical: high-ground and cover position picks, bounding overwatch, flanks, garrisons, mine awareness.
  3. Operational: company axis, formation, phase lines; the recon → suppress → assault → consolidate sequence; artillery prep; breaching.
  4. Strategic: fronts, main effort vs fixing force, reserves, timing, retreat and regroup.
  5. Missions in ops_missions.gd: `raid`, `sabotage`, `recon`, `officer_hunt`, `exfil`.
  6. Every decision emits `AiDecision {fid, tag, unit_ids, reason}` with a §3.6 tag.
  7. Owner checkpoint: record a replay of one AI company assaulting high ground (screenshots + a replay file under `.plan/shots/AI7-DOC/`). Post `fact doctrine.demo_ready`.
  8. Make test_doctrine green.
- **Publishes:** `doctrine.api_ready`, `doctrine.demo_ready`.
- **Done-when:**
  - test_doctrine green
  - the demo recorded
  - full suite green
- **Never:** edit ai_controller.gd or other AI7-USE files (CR).
