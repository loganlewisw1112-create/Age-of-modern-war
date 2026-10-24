# ART-F: walls, gates, towers art (3 factions)
Read G4_COMMON.md first. Contract: CONTRACTS_G4 §1, **§6** (IDs; `conn_<mask>` states). Style: Human A concrete barriers + steel gate + MG tower; Human B brick and scrap + rolling iron gate + flak tower; Machine energy barrier between pylons (cyan emissive) + field gate + sentry spire. Match the existing building modules (`tools/art/buildings.gd`, `faction_b_bld.gd`, `faction_m_bld.gd`).
**Owns:** `tools/art/g4_fort*.gd` (`g4_fort.gd` is a registered stub), fort entries in `assets/generated/**`, `tests/test_art_g4_fort.gd`.
Tasks:
1. For each wall/gate def, build states `conn_0`..`conn_15`, the 4-bit N/E/S/W neighbour mask, so straight runs, corners, T-junctions and crosses connect seamlessly in isometric view. Gates also get `open`/`closed` variants per conn (state `conn_<m>_open`). Towers get conn states too, so walls attach to them.
2. Construction stages (`build_0..2`) and damaged looks; team-colour masks; icons for the build buttons.
3. Generator lock protocol; existing assets must stay byte-identical.
4. `tests/test_art_g4_fort.gd`: all defs × states exist, masks present, deterministic.
5. Contact sheet `.plan/shots/ART-F/fort.png` showing a drawn wall ring with a gate and towers per faction, self-checked with Read.
Done when: tasks 1-5 are done. MAX_TOKENS 500000, MAX_TOOL_CALLS 130, board id `ART-F`.
