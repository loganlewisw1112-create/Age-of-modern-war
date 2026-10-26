# G61-ANIMB: animation overhaul, part B: vehicles, aircraft, ships (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G61_COMMON.md first. Flow name: animb61.

Owner (2026-10-26): "wayyyyy better animations for the entire game and all movement (complete upgrade/overhaul)", in G6.1.
ANIMA61 owns the render/motion layer (entity_layer.gd, batch_art.gd, batch_atlas.gd) and infantry. You own the vehicle, air
and naval art and their animation frames; you get frame-selection hooks from ANIMA61 (its `fact anim.frame_api`; send it a
change_request listing frame names and what selects them).

Build (through the existing generators under tools/art: g6_vehicles.gd, g6_turrets.gd, vehicles.gd, vdetail.gd, truck.gd,
faction_b_veh.gd, faction_b_trk.gd, faction_m_veh.gd, faction_m_drone.gd, g5_units_veh_a/b.gd, g5_air*.gd, g5_naval*.gd,
g6_seaair.gd and any others that draw vehicles; name them in `claim files`):
1. **Turrets** rotate independently of the hull toward the target (separate turret sprites per facing, smooth rotation via the
   frame API), barrel recoil frames on fire (2-3), muzzle position per facing exported for VFX61.
2. **Tracks and wheels** animate with speed (track link phase 3-4 frames, wheel spin), suspension bob/pitch on start, stop and
   rough terrain, a slight hull rock on firing.
3. **Damage states:** damaged (smoking hatch, scorch), burning, destroyed hulk frames (turret blown off variant for tanks).
4. **Aircraft:** banking frames in turns, rotor blur cycles (helicopters), gear up/down, prop spin, afterburner frames for jets.
5. **Ships:** bow wake and stern wash frames by speed, roll in turns, turret traverse as tanks, submarine surfacing/diving.
6. **Machine faction:** walker leg cycles >= 6 frames (coordinate with ANIMA61 if the walker rig is shared), drone hover bob,
   energy pulse frames.
Keep the pixel style and team mask files. Regenerate via gen_art.gd. Check atlas size before/after with ANIMA61.

Tests (tests/test_animb61.gd): every vehicle/air/naval def in the manifest has turret frames (where it has a turret), recoil,
track/wheel phases (ground vehicles), damage/destroyed frames, banking (air), wake (naval), for every facing; art tests
(test_art_*) stay green (update expected counts only where your new frames are the intended change, and say so).
Playtest flow tools/pt61_animb61.gd: a tank platoon advancing and firing, a helicopter turning, a ship at speed; shots plus a
10-shot 0.3 s strip (animb61_strip_*.png) for the owner.
