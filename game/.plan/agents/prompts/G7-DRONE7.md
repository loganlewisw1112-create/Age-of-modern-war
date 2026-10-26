# G7-DRONE7: drone piloting and the drone camera (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first. Flow name: drone7. Spec: G7_REFERENCE master scope sections 0 and 1 (all of it).

## Deliver
1. **Flyable drones:** recon (Human A UAV and recon drones, Human B recon drone, the G5 Drone Team's drones), a new
   **strike drone** (grenade or mortar-bomb drops on a recon airframe, limited drops, then it returns or crashes) and an
   **FPV kamikaze** (single-use, from the Drone Team or a new FPV launcher). New defs in content/g7/defs_g7_drones.json
   (ORCH registers production/stage by change_request); art via tools/art/g7_drones.gd at the G7 detail level
   (`fact art.detail_level` from ARTCN7; until then match the existing drone art).
2. **Sim** (`drone_pilot.gd`, commands pre-registered): drone_take, drone_steer (heading/speed/height per tick from the
   player's input), drone_release, drone_detonate, drone_return. The drone stays a real air unit (HP, battery, noise);
   counter-drone, AA and jammers act on it normally; munitions resolve through strikes.gd and WOUND7's shrapnel (guarded
   call). What it sees feeds the side's intel. **Steering is recorded as commands** so a replay of the command log
   reproduces the flight exactly.
3. **Drone cam** (`presentation/view/drone_cam.gd` + shader): corner window by hotkey, second key full-screen, B or
   Esc hands control back; the battle keeps running with minimap and alerts visible. Greyscale or thermal toggle
   (thermal: soldiers and engines glow, cold terrain dark). Overlays: compass tape, heading, height, dashed reticle with
   range, prompts "ARMED", "MUNITION AWAY", "RNG nn M LIVE"; noise grows with distance and jamming; "LINK LOST" on
   death, jam or out of range.
4. **Controls** (`presentation/hud/drone_input.gd`): recon and strike: WASD fly, Q/E turn, mouse wheel height, Space
   drop; FPV: mouse aims, W/S speed, C detonates. Hotkeys via change_request to SQUAD7 (hotkeys.gd).
5. **Art/animation:** rotor blur, banking, release puffs, the FPV dive, blast types for ground, soldiers, walls, roofs
   and air (ask LOOK7 by change_request for fx hooks you need).

## Tests (tests/test_drone7.gd)
take/steer/release/detonate/return validate and apply; strike drop lands per ballistics with drift; FPV detonation;
jamming and out-of-range cut the link; **a recorded piloted flight replayed from its command log gives the identical
hash**; same seed twice = same hash; a match without piloting is hash-identical to before.
Playtest flow tools/pt7_drone7.gd: take a recon drone, corner window then full-screen, thermal toggle, strike drop on a
squad, FPV dive on a vehicle, LINK LOST under a jammer; shots of each.
