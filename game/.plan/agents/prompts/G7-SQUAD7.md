# G7-SQUAD7: squad tactics, formations, convoys (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first. Flow name: squad7. Spec: G7_REFERENCE master scope sections 0, 3 (all of it, including
"Formations rebuilt like a real military"), 2 (gait under fire, backing off), 6.7 (motorcade convoy, moving cover:
you build the framework; CNSIM7 uses it later). The owner said formations "still look stupid": this is a quality bar.

Today: orders.gd has 8 formations (line, wedge, column, box, echelon_left/right, file, spread); G6.1 split groups > 12
into chunks; squad_ai.gd runs squad behaviour; movement.gd `formation_slots` builds slot offsets.

## Deliver
1. **Formations rebuilt** (formations7.gd + formation_slots): staggered column (soldiers 5–10 m, vehicles 50 m+,
   alternating sides), wedge and diamond with fire-team wedges inside (leader front-centre, automatic rifle on the
   flank), plus the existing types rebuilt to real spacing. Spacing widens under artillery/drone/grenade threat and
   tightens in low visibility/close terrain; every soldier and vehicle has a sector of fire (front/flanks/rear) moving
   and halted; terrain-aware shape (bend along roads, squeeze to file through gaps then reopen, hug tree lines and
   walls, avoid open crossings, never through buildings or stacked); smooth reforming (pivot on the leader, nearest
   slot, nobody crosses through others).
2. **Movement techniques by threat**, automatic: traveling / traveling overwatch / bounding overwatch.
3. **Halts:** vehicles angle into a herringbone facing outward on a road; longer halts form a 360° coil; infantry form
   a 360° security ring.
4. **Tactics:** bounding fire teams (A/B), suppressive fire on last-known positions or areas, hold and ambush (hold fire
   until the kill zone, then break contact), assault under covering fire, break contact (smoke, backing off, bounding
   to the rear), building clearing (stack, grenade first, room by room, window fire, and a `roof_open` flag on the
   building while own troops are inside, for LOOK7), soldiers decide grenade throws (call WOUND7's Shrapnel via guard).
5. **Gait under fire** (walk / crouch-walk / duck-run / sprint from threat distance, route cover, suppression; decided
   per squad on a schedule) and **backing off** (ordered fall-backs walk backwards facing the enemy and keep firing;
   only broken units turn and run).
6. **Convoy framework** (convoy.gd, commands convoy_form / convoy_move / convoy_disband): motorcade layout (a protected
   core in the centre, escorts at lead/rear/threatened flank), shielding (nearest escort moves between threat and
   core), never stop in a kill zone (one escort peels off to hold, the rest push through and regroup), fixed spacing at
   the slowest vehicle's speed, roads preferred, tighter at chokepoints, perimeter-before-dismount at stops, and moving
   cover for soldiers on foot beside vehicles (sheltered side, walking pace, swing to block new threats). Generic over
   unit roles so CNSIM7 can plug in the strike group. Post `fact convoy.api`.
7. **Render snapshot fields** for LOOK7 (change_request): gait, facing/sector, backing-off, stacking/entering,
   formation slot heading, herringbone angle, building roof_open.
8. **Controls:** formation and technique buttons in g2_commands.gd, rebindable hotkeys in hotkeys.gd.

## Tests (tests/test_squad7.gd)
staggered column spacing; wedge/diamond slot layout; spacing widens under a threat flag; every member has a sector;
squeeze through a gap and reopen; no slot inside a building; reforming without crossings; traveling/overwatch/bounding
chosen by threat; herringbone and coil at halts; bounding alternation; backing off keeps facing; a convoy keeps
formation and an escort interposes on contact; same seed twice = same hash; 2k sim cost delta reported.
Playtest flow tools/pt7_squad7.gd: a platoon in staggered column on a road, wedge across open ground, a halt into
herringbone, bounding under fire, a building clear, a 5-vehicle convoy taking contact; shots of each plus a 10-shot
0.3 s strip of the column for the owner.
