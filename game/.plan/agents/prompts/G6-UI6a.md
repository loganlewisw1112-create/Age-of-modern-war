# G6-UI6a: operating guide
Read `.plan/agents/prompts/G6_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G6 §0-§2, §5, §6, §13 (market), §8, §16 (AI Commanders). **Plan:** PLAN_G6 §10.
**Board / bus id:** `UI6a`. **Budget: MAX_TOKENS 750000, MAX_TOOL_CALLS 140** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g6/test_ui6a.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### UI6a: Marketplace, Army Builder, company/army cards, Commanders panel
- **Role:** the four big new panels, skirmish setup for survival, and UI fit for everything.
- **Owns:** see CONTRACTS_G6 §1 row UI6a (`presentation/ui5/kit/**`, `presentation/ui6/a/**`, the HUD core files, `presentation/menu/**`, `match_view`, the UI fit tool and tests).
- **Inputs:** the UiKit (G5), the market / army / aicmd APIs, MODES6's victory types, vision image 05 (company card).
- **Tasks (in order):**
  1. Marketplace panel (from the HQ panel): prices, buy/sell, limit.
  2. Army Builder screen: create, edit, validate and save custom templates (per profile); train from presets or customs at the Company HQ.
  3. Company and army cards with a unit grid + battle-status line (vision 05); form army / disband / refill toggle.
  4. Commanders panel: assign a formation or role, playstyle, objective (map click), stance, recall; badges.
  5. Skirmish setup: survival victory options + the two new maps.
  6. Make test_ui6a green; the UI fit test shows 0 issues at 7 resolutions with the new screens (`FIT RESULT` line).
- **Publishes:** `ui6a.ready`.
- **Done-when:**
  - test_ui6a + test_ui_fit + test_hud + test_ui3 green
  - FIT RESULT issues=0
  - full suite green
- **Never:** edit UI6b's panels or sim code.
