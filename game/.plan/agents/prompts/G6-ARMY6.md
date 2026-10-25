# G6-ARMY6: operating guide
Read `.plan/agents/prompts/G6_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G6 §0-§2, §5, §6, §8, §3.5, §4 (company commands). **Plan:** PLAN_G6 §6.
**Board / bus id:** `ARMY6`. **Budget: MAX_TOKENS 750000, MAX_TOOL_CALLS 140** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g6/test_companies.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### ARMY6: companies, armies, chain of command
- **Role:** everything in §8: templates, Company HQ training, the captain/lieutenant/Commander hierarchy, armies, promotion, cohesion and refill.
- **Owns:** see CONTRACTS_G6 §1 row ARMY6 (`sim/systems/companies.gd`, `ops.gd`, `production.gd`, `content/g6/rules_companies.json`, test_companies, test_ops).
- **Inputs:** `sim/systems/ops.gd` (G2 groups, missions, prune); `production.gd`; CONTENT6's leader / Commander / HQ defs (`content.g6_defs_ready`); D28-D31.
- **Tasks (in order):**
  1. Make the §4 company commands validate and apply, with stub behaviour first. Post `fact army.api_ready` (partial) within your first hour.
  2. Templates: presets for all 16 types × 3 sizes in `rules_companies.json` (built from existing + G6 units of that faction); custom templates via `validate_template`.
  3. `train_company` at the Company HQ: cost/pop = sum, time = slowest + 25%, spawn all at once; captain + one lieutenant per platoon; platoons = ops groups (officer = lieutenant, `parent_company`).
  4. Hierarchy and limits: Commander (`train_commander`, max 2), `form_army` (2-4 companies, max 2 armies), `disband_army`, one HQ per player. Captain death → field promotion (10 s confusion, −15 morale). Commander death → `ArmySplit`.
  5. Cohesion (`cohesion_acc`, `cohesion_morale`), refill (`set_company_refill`: losses queue at the HQ, replacements travel to their platoon), `on_destroyed`, save/hash.
  6. Make test_companies green; keep test_ops green. Post `army.api_ready` (complete).
- **Publishes:** `army.api_ready`.
- **Done-when:**
  - test_companies + test_ops green
  - full suite green
- **Never:** write AI (AI7-*), UI (UI6a), or change production behaviour for existing items.
