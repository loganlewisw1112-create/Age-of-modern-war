# G7-ARTCN7: new art detail level + look-checkpoint samples (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first. Spec: G7_REFERENCE master scope sections 0, 6.2, 6.4–6.6, 6.9, 6.12, 7, 8 (threat units,
living cores). **This feeds Done-when 6: the owner approves these samples before any full art roll-out.** Make them
look great: they are the first units at the G7 detail level and set the bar for everything after.

## Deliver
1. **Set the detail level** (post `fact art.detail_level` early, update when final): sprite resolution/pixel density,
   palette and shading rules, facings, frame budget, mask (armband) rules, and a memory budget per unit class that keeps
   the fps gates (2k p10 ≥ 60, 10k zoomed out p10 ≥ 30) given G6.1's atlas sizes. Upgraded pixel art through the
   existing generator style (study tools/art/g6_*.gd, g61_anim*.gd); no 3D.
2. **Samples** (generators `tools/art/g7_cn_*.gd`, `g7_turrets.gd`, `g7_threats.gd`; output under assets/art/g7_*/), each
   with every facing it needs and its key animation frames:
   - Counter-nanite strike team: the distinct kits (team leader, second-in-command/radio, deployment specialist
     carrying a strike package, scanner technician, EW specialist, security gunner, medic/engineer), sealed suits,
     armband team colour.
   - Tactical operators: the 8 role kits (leader, marksman, hunter-killer with harpoon/net gun, EMP grenadier,
     anti-drone specialist, purge/demolitions, medic).
   - Strike-team APC (larger than a regular APC; front and rear shielded .50 mounts with gunners; side pop-out panels
     open/closed; dome effect frame; rear doors) and the tactical APC (roof remote twin .50).
   - Stealth strike dropship (no rotors, stealth engines, VTOL nozzles; ramp open/closed showing an APC inside) and the
     enlarged regular VTOL dropship with the same internal bay.
   - A facility sample: the gate + decontamination zone + a garage bay + the helipad (enough to judge the look).
   - 2 of the 8 turrets: Heavy MG nest and Rail cannon.
   - Machine threats (in the Machine's CURRENT style): packhunter walker (wolf/spider gait, clawed talons), Weaver
     (huge spider-mother, web spit, cocoon), living core (pulsing, plating, and the walking second phase).
3. **Strips for the owner** (`tools/g7_lookcheck.gd`): renders each sample on terrain at game zoom, with a 10-frame
   animation strip per sample, into `.plan/shots/ARTCN7/` plus one contact sheet PNG. Post `fact art.checkpoint_ready`
   with the paths, then wait for ORCH's directive (owner feedback). Apply feedback, re-post.
4. Do **not** wire these into content defs (later agents do); keep them as generated assets + manifest entries.

## Tests (tests/test_artcn7.gd)
every sample has its facings and key frames in the manifest; masks present; per-unit memory within the posted budget;
generators deterministic (same output twice).
