# G61-AUDIO61: battle sound + radio chatter (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G61_COMMON.md first. Flow name: audio61.

Owner (2026-10-26): "radio chatter + sound" in G6.1. The game has NO audio today. Build the whole layer.

## 1. Sound generation (offline, at build time, into assets/generated/audio, committed like the generated art)
- No sound assets exist and none may be downloaded. Generate every effect procedurally with a GDScript/Python synth tool of
  yours (tools/audio/*.gd or .py run with the system Python 3.13 with no third-party packages): gunshots per weapon class
  (rifle, MG burst, cannon, autocannon, rocket launch, artillery boom + distant thump, laser/energy for Machine), impacts,
  explosions (near / far variants), engines (tank, truck, jet, helicopter, ship) as loops, footsteps/gear, UI clicks, alerts.
  Several variants each so repeats don't sound identical. 16-bit PCM .wav (or .ogg if Godot import is reliable), 44.1 or
  22.05 kHz mono.
- **Radio voices:** Windows has two SAPI voices (Microsoft David Desktop, Microsoft Zira Desktop). Pre-render the radio line
  library with PowerShell System.Speech (rate/pitch varied per speaker for variety), then apply a radio filter (band-pass
  300-3400 Hz, light distortion, squelch click in/out, static bed). Lines cover the chain of command: contact reports ("Contact,
  enemy armour, north-east!"), taking fire, casualties, objective taken, requesting support / resupply / medevac, moving out,
  holding, falling back, artillery inbound, air support on station, orders acknowledged ("Copy, moving to phase line Bravo"),
  officer down, company ready, low ammo, plus per-faction flavour (Machine = synthetic, heavily processed, no SAPI accent issue).
  Write the line list as data (content/g6/audio_lines_g61.json) so future lines are easy to add. Keep the generation script
  re-runnable; ship the generated files.
## 2. Runtime (new presentation/audio/*)
- An audio director node: listens to sim events through the view (ShotFired, hits, EntityDestroyed, construction, production,
  alerts) and CHAIN61 reports (CommandNet.reports / its events) for radio chatter; positional 2D audio relative to the camera
  (pan + distance attenuation + far-variant swap), voice limiting per category (max N gunshots, max 1 radio line at a time,
  priority queue: officer down > contact > orders), ducking of battle sound under radio, engine loops for selected/near vehicles.
- Only the player's own side's radio is heard; fog-hidden events are silent or distant-only.
- Buses: Master, Battle, Radio, UI, Music(empty for now); volume sliders + mute in Settings (presentation/menu/settings.gd:
  send ORCH a change_request with the exact lines, or add a small section if the file has a section API; settings persist
  where settings already persist).
- Never affects the sim or its hash; headless runs and tests stay silent and fast (detect headless / dummy audio driver).
## Owned files
tools/audio/*, assets/generated/audio/*, content/g6/audio_lines_g61.json, presentation/audio/*, tests/test_audio61.gd,
tools/pt61_audio61.gd. Hook lines in match_view/hud: change_request to ORCH with exact lines.
## Tests (tests/test_audio61.gd)
Every event type maps to a sound id that exists on disk; variants rotate; voice limits hold under a 2k-unit firefight (no more
than N concurrent); radio queue priority and one-at-a-time; a CHAIN61 report produces the matching radio line; enemy radio is
never heard; volume settings apply per bus; headless mode creates no players.
Playtest flow tools/pt61_audio61.gd: run a battle and log the sounds and radio lines played (the harness can't hear; log ids +
counts), open Settings and move the sliders (shot).
