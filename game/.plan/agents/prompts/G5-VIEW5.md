# G5-VIEW5: operating guide
Read `.plan/agents/prompts/G5_COMMON.md` first: board, semantic layer and rules all apply.
**Contract sections:** CONTRACTS_G5 §0.6, §1, §5, §6. **Plan:** Plan sections 3-7, 10.
**Board / bus id:** `VIEW5`. **Budget: MAX_TOKENS 600000, MAX_TOOL_CALLS 150** (registered by ORCH; never raised).
**Your acceptance skeletons:** `tests/pending_g5/test_view5.gd`. `git mv` them into `tests/` first.
**First tool call:** post `status`. Second: post `claim` with your owned files. Then a bus `NOTE <ID> started`.

---
#### VIEW5: drawing everything new in the game world
- **Role:** render the new sim state from the snapshot.
- **Owns:** `sim/render_snap.gd`, `presentation/view/{entity_layer,batch_art,fx_layer,terrain_layer,lod_icons}.gd`, `presentation/art/art_catalog.gd`.
- **Inputs:** every `*.api_ready`; the art manifests from the ART agents.
- **Tasks:**
  - aircraft with altitude offset + shadow, takeoff/landing/taxi on the strips, holding circles, sling loads;
  - runway craters and hangar states;
  - ships with wakes and sinking;
  - drones in flight;
  - the wounded marker and the evac carry pose;
  - the truck Auto area circle and supply icons;
  - burnt ground from the sim set;
  - LOD icons for all new units;
  - snapshot flags for every new visual state.
- **Done-when:**
  - a headless probe passes for each new visual state;
  - the 6 existing playtests pass;
  - screenshots of air, naval, drones and evac saved;
  - full suite green.
- **Budget:** 600k / 150.
- **Never:** read the live world while `sim_busy()`.
