# G7-WOUND7: soldier realism (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first. Flow name: wound7. Spec: G7_REFERENCE master scope sections 0, 2 (all of it), 5 (the poses
your states drive), 6.8 (suits/exposure will read your wound/puncture hooks later).

## Deliver (sim; LOOK7 draws it)
1. **Hit zones replace infantry HP** (infantry with a `morale` field or an infantry class; vehicles unchanged). Zone
   picked by posture, cover (cover hides lower zones) and shooter facing, via `w.rng`.
   - legs: slower; both legs = crawl only. arms: worse aim, slower reload. torso: bleeding + short knock-out.
     head: usually killed or unconscious.
   - every wound sets an out-of-action timer by zone; bleeding runs over time; untreated -> unconscious -> dead.
   - Keep a derived "hp fraction" for code that still reads HP (AI, UI, victory) so nothing else breaks.
2. **Shrapnel** (`sim/systems/shrapnel.gd`): grenades, shells and drone munitions throw a sampled fan of fragment rays;
   walls/cover/buildings block them (use the existing LOS/cover queries); each connecting ray = a hit-zone wound; blast
   flinch + pin via morale. Ray count budgeted by the sim detail level (tiers.gd).
3. **Casualty care, full chain** (`wounds.gd`, `medical.gd`): buddy aid (any squadmate, slow), squad medic (fast,
   stabilise), drag to cover (slow move), casualty evacuation by stretcher team / ambulance / APC / helicopter to the
   existing G5 hospitals, return to duty with scars kept on the soldier; survival odds fall with time to treatment.
   Commands `treat_casualty`, `evacuate_casualty` (stubs pre-registered); AI and squads do it on their own too.
4. **Visible panic** (morale.gd): breaking morale gets explicit states (cower, freeze, flee, drop weapon) using the
   G6.1 traits for the odds.
5. **Render snapshot fields** for LOOK7 (change_request to LOOK7 for render_snap.gd): per soldier wound zones,
   unconscious, bleeding, being treated / dragged / carried, panic state. Post `fact wounds.render_fields`.
6. **UI:** `presentation/ui7/wound_card.gd`: wound icons + a body diagram in the selection card replacing the infantry
   HP bar (ORCH hooks it into the inspector: send a change_request with the hook line).
7. **APIs for others** (post `fact` stubs early): `Wounds.apply_hit(w, e, zone_hint, dmg, src)`,
   `Wounds.state(e) -> Dictionary`, `Wounds.is_down(e)`, `Wounds.puncture(w, e, src)` (CNSIM7 suits later),
   `Shrapnel.burst(w, pos, profile, src)`.

## Tests (tests/test_wound7.gd)
zone distribution responds to posture and cover; leg/arm/torso/head effects; bleed-out timeline; buddy aid / medic /
drag / evacuation to hospital and return with scars; shrapnel blocked by a wall; same seed twice = same hash; a fight
with no infantry hash-identical to before; 2k-fight sim cost delta reported.
Playtest flow tools/pt7_wound7.gd: a squad under grenade fire behind a wall vs in the open; a leg-wounded soldier
crawls; a medic treats; a drag and an evacuation; shots of each.
