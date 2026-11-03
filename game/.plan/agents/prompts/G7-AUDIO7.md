# G7-AUDIO7: G7 sound (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first. Spec: docs/G7_REFERENCE.md master scope 13.2 (adaptive music: calm ambient while planning,
tension layers as the countdown advances and convoys roll, combat drums in firefights, a dedicated Tide theme, sudden
silence just before the Tide hits), 13.4 (operator voice barks by personality: under fire, wounded, kills, hero
detonations; bonds call-outs), 13.7 (PROTOCOL advisor voice: suggests, never acts, mutable), section 10 (Last
Protocol), plus every G7 sound the new systems need (drone feed, APC .50s and rocket pod, dropship fans and ramp,
creep/fissures/growths, Machine threat units, core screams, turrets, EMP, thermite, rail cannon, Weavers). Read the
G6.1 audio system first (presentation/audio/: audio_director, audio_catalog, audio_mixer, radio_queue, audio_buses,
audio_tab; tests/test_audio61.gd; .plan/handoff for AUDIO61 if present) and reuse how it makes and catalogues sounds
(look at assets/generated and how the existing sounds were produced; G7 must use the same pipeline, no downloaded
or third-party audio).

Event sources (read their APIs, don't edit their files): CnProgress7 (personalities, voice index, bond events),
CounterNanite / Apc7 events, CnOps7 (overwatch warning, fire support, relief), Wounds, Senses7 (heard contacts),
LastProtocol (phase, countdown, Tide, endings), Creep / Fissures7 / Cores / Threats7, Turrets7, DronePilot,
OPSUI7's PROTOCOL advisor lines (OPSUI7 is live; agree on the board how its lines reach you).

## Files you own
presentation/audio/* (extend, keep G6.1 behaviour and tests), new generator tools under tools/ for G7 sounds/music,
the generated assets they write, tests/test_audio7.gd, tools/pt7_audio7.gd (flow "audio7" is registered). Settings /
hud hooks: change_request to ORCH with exact lines (music/voice volume, mute PROTOCOL voice).

## Deliver
1. Adaptive music system with layers driven by game state (planning / tension rising with the LP countdown and
   convoys / combat / Tide theme / pre-Tide silence), smooth crossfades, normal matches too (not only Last Protocol).
2. Operator voice barks: 4 personalities x situations, radio-processed, throttled through radio_queue so it never
   spams, subtitles for OPSUI7's team cam (post the event/subtitle API).
3. Command voice (acknowledgements for counter-nanite orders) and the PROTOCOL advisor voice (mutable).
4. G7 sound effects for every new unit/system listed above, positional and culled like the G6.1 sounds.
5. No sim effect: audio never changes the state hash. Mixer budget: no clipping, voice ducks music/effects.

## Tests (tests/test_audio7.gd)
music layer selection per state (planning/tension/combat/Tide/silence window); bark selection by personality and
throttling; PROTOCOL voice mute; every G7 event maps to a sound that exists; hash unchanged with audio on/off;
test_audio61 still green. Playtest flow tools/pt7_audio7.gd: drive a match through the states and log what plays
(audio can't be screenshotted: log cues + levels, and a short WAV capture if the engine allows).
