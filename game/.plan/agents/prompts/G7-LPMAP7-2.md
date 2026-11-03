# G7-LPMAP7-2: Last Protocol map, finish (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first, then G7-LPMAP7.md (your predecessor's brief) and its handoff .plan/handoff/LPMAP7-1.json
("remaining" is your list). Flow name: lpmap7. ORCH has applied both change requests: `last_protocol` is in
sim/map_gen.gd MODULES + validate() and in content/maps.json (`"skirmish": false, "mode": "last_protocol"`), and
World7Layer is wired in presentation/match_view.gd (after terrain, before creep; setup + refresh).

Files you own: sim/maps/last_protocol.gd, tests/test_lpmap7.gd, tools/pt7_lpmap7.gd, .plan/lpmap7/.
**Not yours any more:** presentation/view/world7_layer.gd now belongs to FISSURE7 (creep fissures/canyons/growths,
an owner amendment, master scope 13.9a); send it change_requests if you need something there.

## Do
1. test_lpmap7 (its registered_in_map_gen test now runs its real checks), test_maps, test_scale7 green.
2. Run pt7_lpmap7 windowed to PLAYTEST RESULT all ok, 0 SCRIPT ERROR; look at every shot yourself and say what is
   wrong.
3. Perf: bench --map=last_protocol fps cases (2k on screen p10 >= 60, 10k zoomed out p10 >= 30) with the pre-built
   base, plus `bench --breakdown` to find what drives the ~31.8 ms sim step your predecessor measured (walls are a
   suspect, not a finding). Fix what is yours; send exact change_requests for what is not (e.g. LPMODE7 wall
   placement). The PC is shared with other agents: report numbers as shared-PC, not gate numbers.
