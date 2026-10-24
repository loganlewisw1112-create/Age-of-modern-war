# ART4: G3b sprites, map decor, LOD icons (CONTRACTS_G3b §8)
Read G3B_COMMON.md first. The art pipeline is procedural GDScript: `tools/gen_art.gd` with modules in `tools/art/*.gd`, writing `assets/generated/**` + a manifest that ArtCatalog loads. Study how the G3a agents did faction art: `tools/art/faction_b*.gd` (Human B industrial: riveted, rust, brick, smokestacks) and `faction_m*.gd` (Machine: panels, emissive cyan, walkers/drones), and Human A's modules (`vehicles`, `buildings`, `infantry`...). Match the established style and quality. The owner said vehicles and buildings now look great; keep that detail level. Visual direction: `docs/vision/README.md` + view `06_forward_base_tank_company.webp` (at most 2 images).

Order:
1. The 9 new units (§3.1 table):
   - Human A: a_old_tank, a_uav (air, hovering/shadow like m_drone), a_ew_truck (antenna/dish), a_guided_arty;
   - Human B: b_field_gun (towed gun, crew optional), b_radar_aa (radar dish + AA guns), b_jammer_truck, b_guided_battery (rocket rails);
   - Machine: m_siege_crawler, m_swarm (cluster of small drones, air), m_ew_node, m_lancer (rail walker).
   Facings, anims and team-colour masks the same as comparable units. Wrecks for vehicles.
2. The 5 new buildings: research_station (A), b_drafting_office (B), m_compute_node (M), comms_tower (A), b_signal_mast (B). Include construction stages/damaged states like the other buildings.
3. Icons for the new production/build buttons.
4. Map decor for MAP4: rail track pieces, factory block, refinery tanks, ruined plant, dam, tunnel portal, airfield tarmac/hangar. Check the board for MAP4's CHANGE_REQUESTs with ids, and agree the ids via board facts.
5. Far-zoom LOD icons for R4: small team-tintable icons per role class (infantry, vehicle light/heavy, artillery, air, building), and a dot.
Post `fact art.gen_lock {"by":"ART4"}` before running the full generator and `art.gen_unlock` after. You are the only art agent this wave. `tests/test_art_g3b.gd`: every new def has art (manifest entries, files exist, sizes sane); the existing test_art suites stay green. Contact sheet PNGs in `.plan/shots/ART4/`, viewed with Read to self-check quality.
MAX_TOKENS 500000, MAX_TOOL_CALLS 130, board id `ART4`.
