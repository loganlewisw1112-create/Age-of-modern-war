# G5-NAVAL: operating guide
Read `.plan/agents/prompts/G5_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G5 §1-§6, §8. **Plan:** Plan section 4 (Workstream C).
**Board / bus id:** `NAVAL`. **Budget: MAX_TOKENS 700000, MAX_TOOL_CALLS 170** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g5/test_naval.gd`, `tests/pending_g5/test_coastal_front.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### NAVAL: ships, shipyards, Coastal Front
- **Role:** the whole naval sim and the new map.
- **Owns:**
  - `sim/systems/naval.gd` (bombardment, beaching/unload rules, sinking wrecks, pier resupply);
  - `sim/maps/coastal_front.gd` (new map generator + validation);
  - `content/g5/naval.json`;
  - `tests/test_naval.gd`, `tests/test_coastal_front.gd`.
- **Inputs:** plan §4; G4 movement classes (`naval`, `naval_small`, `amphibious`); `Movement` API (call only).
- **Tasks:**
  1. Content for every ship and naval building with fixed IDs.
  2. Coastal Front (192×192):
     - mainland, 2 islands, beaches, an estuary with fords;
     - 2–4 spawns validated reachable by land or sea;
     - registered through a CR to ORCH (map list).
  3. Shipyard shore placement (part water, part beach).
  4. Landing craft unload only at beach/shallow; the amphibious crawler drives ashore.
  5. Shore bombardment (indirect fire on land in range).
  6. Wrecks sink into a shallow obstruction (nav updated).
  7. Supply Pier restock.
  8. Save/load mid-sea.
- **Publishes:** `naval.api_ready`, `map.coastal_front_ready`.
- **Done-when:** test files green (movement by class, placement, beaching, amphibious path, bombardment, sinking, save mid-sea); the map validates for seeds 1–5; full suite green.
- **Budget:** 700k / 170.
- **Never:** edit `movement.gd` (CR to CORE10K) or the AI.
