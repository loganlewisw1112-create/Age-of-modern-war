# G7-VIS7: G7 display integration (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first. Spec: docs/G7_REFERENCE.md sections 6.5 (APC dome, panels, .50 pods, pop-out 6-tube rocket
pod), the owner amendments on the anti-walker pincer and the topple ("physically tip and blow up the heavy machine
walkers"), section 8 + THREAT7's units, 13.9 (a world that reacts), and all "Look checkpoint" decisions (the owner's
quality bar). Read the board change requests seq 558 (CNSIM7-3: render keys + events for the launcher and topple), 577
(THREAT7: Threats7.render_info drawing, topple overlay sheet, fx, events), 1188 (art.apc_weapons: the APC _gun / _rkt
sheets and their frames), and the backlog fact `orch.backlog` (world7 traces, minimap creep, dam readability).

The sim already produces everything; nothing draws it yet. Known gaps seen in real playtest shots:
- heavy walkers never fall over on screen: topple / fall / down / rise are not rendered (CNSIM7-6 shot 09);
- the APC dome bubble is not visible; the pop-out rocket pod barely reads; the new _gun / _rkt fire and reload
  sheets are never played in a match;
- threat unit states (burrowed mound, disguised mimic, latched leech, cocooned soldier, web) are not drawn;
- world7 traces: abandoned vehicles/beacons too small or under the creep, recovering ground shows a grey slab;
- the minimap shows no creep and draws CHASM in ridge colour; the dam barely reads.

## Files you own
A new presentation/view/vis7_layer.gd (draws above/among entities: topple overlays, dome bubble, rocket salvos and
backblast, limpet/harpoon/disruptor fx, threat overlays, cocoons, webs) and presentation/view/world7_layer.gd (FISSURE7
finished; traces + recovering-ground fixes), presentation/hud/minimap.gd (creep + CHASM colour), sim/render_snap.gd
for the G7 render keys (CR 558's copy_g7v_keys), presentation/art/art_catalog.gd only to register sheets.
presentation/view/entity_layer.gd is being edited by CNFAC7-2 (live, dropship loading): if you need a change there
(e.g. skip the normal walker sprite while a topple overlay draws it, or play the APC _gun/_rkt frames), post a `need`
to CNFAC7-2 on the board, agree who writes it, and re-read before any write. match_view wiring: change_request to ORCH.

## Deliver
1. Walker topple: stagger -> fall (in topple_dir) -> down -> rise, and the blown-up wreck fx; using THREAT7's topple
   sheets or ARTCN7's mesh renderer; looks physical and heavy.
2. APC: dome bubble (charge visible), side panels, the .50 pods firing with the _gun sheets, the rocket pod raise ->
   ripple fire with backblast and rocket trails -> reload, limpet / harpoon / disruptor shots.
3. Threat units' special states and events per CR 577.
4. World reaction fixes + minimap creep/CHASM + dam readability.
5. Display only: the state hash is unchanged with any of it on/off; fps gates hold (measure 2k/10k with bench on a
   shared PC, report as shared-PC numbers).

## Tests (tests/test_vis7.gd)
render keys present for each state; each overlay draws from a fixture snapshot without errors; hash unchanged
on/off. Playtest flow tools/pt7_vis7.gd (ask ORCH to register "vis7"): a full pincer with launcher salvos and a
walker toppling and blowing up, a dome soaking fire, each threat state, the world-reaction area, the minimap; shots at
zoom 1/2/3 (look at every one yourself and judge it against the owner's words).
