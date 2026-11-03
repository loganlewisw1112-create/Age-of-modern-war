# G7-CINE7: Last Protocol cinematics + end-of-run screen (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first. Spec: docs/G7_REFERENCE.md 13.1 (in-engine opening cinematic, 60-90 s: the first creep
outbreak, the network waking, the order to activate Last Protocol, then the camera sweeps over the 3-ring base and
hands you control), 13.5 (endings: total purge "world saved" with its own cinematic and top-tier medal; pyrrhic victory
with the "Remembered" list rolling over a darker epilogue; capture-a-core hidden ending; one short defeat cinematic per
loss: creep swallowing the map, countdown hitting zero, the facility falling), section 10's end-of-run data (time,
creep purged, cores destroyed, teams lost, extractions, bronze/silver/gold medals, personal bests, the "Remembered"
list), 6.4/13.4 (named operators who died feed "Remembered": CnProgress7 records). The 13.10 list says what moved to G8
(director-cam PiP, highlight reel, creep timelapse): don't build those.

Read LPMODE7-3's handoff and commit 9f9d264 (endings logic + events already exist in last_protocol.gd; lp_hud.gd has the
end panel + Continue; lp_menu.gd saves records), and CNOPS7's cn_progress7.gd (operator names, call signs, records).
AUDIO7 is live and builds the Tide theme / music: agree on the board which cue each cinematic plays (post `fact
cine.cues`). OPSUI7 is live (codex, PROTOCOL lines).

## Files you own
New presentation/cine7/ (cinematic director: camera paths over the real map, in-engine shots, title cards, fades,
skip; one module per cinematic), presentation/ui7/lp_hud.gd's end panel (LPMODE7 finished; replace it with the full
end-of-run screen) and lp_menu.gd (records/personal bests), tests/test_cine7.gd, tools/pt7_cine7.gd (flow "cine7" is
registered). match_view / hud / main / settings hooks: change_request to ORCH with exact lines. Never change the sim:
cinematics drive the camera and presentation only; the match is paused or the sim keeps its normal tick (decide and
state which); the state hash must be identical with cinematics on/off/skipped.

## Deliver
1. Opening cinematic (skippable, plays once per Last Protocol run start, setting to always skip).
2. Ending cinematics: total purge, pyrrhic (Remembered roll), capture-a-core, and the three defeat cinematics.
3. End-of-run screen: all section-10 stats, medal, personal bests (records file), the Remembered list with call signs.
4. Quality bar: these are the first thing and the last thing the player sees in Last Protocol; make them feel like a
   finished game (framing, pacing, typography, transitions), using the real map, units and creep.

## Tests (tests/test_cine7.gd)
each ending maps to its cinematic; skip works; hash identical with cinematics on/off; Remembered lists exactly the dead
named operators; medals and records saved; no script errors. Playtest flow tools/pt7_cine7.gd: the opening (several
frames), each ending (several frames), the end-of-run screen at 1280x720 and 1920x1080; look at every shot yourself.
