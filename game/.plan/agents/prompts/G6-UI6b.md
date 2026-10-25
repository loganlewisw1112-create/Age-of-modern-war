# G6-UI6b: operating guide
Read `.plan/agents/prompts/G6_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G6 §0-§2, §5, §6, §14, §15 (Live), §9 (tools). **Plan:** PLAN_G6 §10.
**Board / bus id:** `UI6b`. **Budget: MAX_TOKENS 750000, MAX_TOOL_CALLS 140** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g6/test_ui6b.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### UI6b: loadouts, garage, Live controls, G6 tools, research/Stage 10
- **Role:** the smaller G6 panels and command buttons.
- **Owns:** see CONTRACTS_G6 §1 row UI6b (`presentation/ui5/panels/**`, `presentation/ui6/b/**`, the command/inspector HUD files, the g2/g4b input+overlay files, test_ui6b, test_ui_panels).
- **Inputs:** UiKit; exo / loadout / mines / garrison / rail / strike / submerge APIs; ED6's Live API; CONTENT6 research + Stage 10.
- **Tasks (in order):**
  1. Loadout swap panel and Exo-Suit Garage panel (resuit).
  2. Command buttons + input modes for `lay_minefield` (rect drag), `sweep`, `line_charge`, `garrison`, `build_rail` (line drag), `deploy_bridge`, `airdrop`, `designate`, `aerostat`, `strike`, `assimilate`, `cloak`, `submerge`.
  3. Editor Live toggle + speed widget (with ED6).
  4. Research panel + Stage 10 additions.
  5. Make test_ui6b green; keep test_ui_panels green; 0 fit issues.
- **Publishes:** `ui6b.ready`.
- **Done-when:**
  - test_ui6b + test_ui_panels green
  - 0 fit issues
  - full suite green
- **Never:** edit UI6a's files or sim code.
