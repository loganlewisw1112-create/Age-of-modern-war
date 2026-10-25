# G5-UI5a: operating guide
Read `.plan/agents/prompts/G5_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G5 §0.6, §1, §2, §5. **Plan:** Plan section 7 (Workstream F).
**Board / bus id:** `UI5a`. **Budget: MAX_TOKENS 900000, MAX_TOOL_CALLS 220** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g5/test_ui_fit.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### UI5a: UI kit, screen fit, layouts
- **Role:** the new look and the "everything fits" guarantee.
- **Owns:**
  - `presentation/ui5/kit/**` (theme, panel kit, faction accents, tooltips);
  - `presentation/hud/hud.gd`, `hud_theme.gd`, `scaled_layer.gd`, `minimap.gd`, `objectives.gd`;
  - `presentation/menu/**` except `settings.gd`;
  - `presentation/match_view.gd`;
  - `tools/ui_fit_test.gd`.
- **Inputs:** plan §7; FONT's TTF when ready (placeholder until then); THREAD's rule (read only the render snapshot while `sim_busy()`).
- **Tasks:**
  1. **Fit test first:** it opens every screen and panel at the 7 resolutions and fails on any rect outside the viewport or overlapping another. Run it on today's UI to list every current clip.
  2. Panel kit and theme: military style, faction accents, hover/selected/disabled states, tooltips with hotkey + cost. Post `fact ui5.kit_ready` early.
  3. Re-layout the HUD, top bar, minimap frame, menus, skirmish setup, pause and objectives with anchors/containers; add UI Scale (75-150%).
  4. Control-group bar, idle-units button, double-click select-type.
  5. Swap in FONT's typeface everywhere after the owner approves it.
- **Done-when:** the fit test shows 0 clipped/overlapping controls at all 7 resolutions (screenshot sheets saved); the 6 existing playtests pass; full suite green.
- **Budget:** 900k / 220.
- **Never:** read `w.entities` during a step; edit UI5b/ED5/PT5 files.
