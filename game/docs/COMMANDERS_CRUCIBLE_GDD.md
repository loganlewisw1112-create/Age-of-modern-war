# COMMANDERS CRUCIBLE GDD

Owner-approved expanded design direction, 2026-11-27. All features planned; implementation and acceptance pending. Working names, proposed interfaces and test IDs are not source code or frozen gate contracts. Existing G10.1 regression remains open.

## Purpose
Immediate, highly replayable tactical RTS challenges; target short 10–30 minute operations where appropriate (not a promised duration), optional longer scenarios. No need to build an entire civilization every session. Handcrafted and procedural challenges, coherent pressure, meaningful accomplishments.

| ID / family | Starting situation | Objective options |
|---|---|---|
| CC-01 Against the Odds | Smaller or lower-tech force vs credible superior opposition | Achieve defined objective, win or extract; not raw unit-count superiority |
| CC-02 Last Stand | Isolated defensive position | Hold priority assets, survive, evacuate or defeat attack |
| CC-03 Encirclement | Forces cut off from main command | Rescue, withdraw or reopen supply corridor |
| CC-04 Counteroffensive | Territory already lost | Recover objectives and stabilize defenses |
| CC-05 Resource Crisis | Limited fuel/ammo/power/materials | Restore logistics or complete mission within available resources |
| CC-06 Combined Arms | Multiple legal military branches | Complete coordinated objective using viable ground/air/naval support as available |
| CC-07 Total Crisis | Several causal challenges overlap | Prioritize objectives, achieve configured success thresholds or endure persistent scenario |

Difficulty presets separate AI skill, coordination, adaptation, starting handicap, resource scarcity, environmental pressure and assistance. Generated challenges validated for viable starting assets, routes and completion conditions; not every seed automatically eligible for competitive comparison. Challenge rules fixed before start, seed and rules hash saved. Score uses completed objectives, survival, time, resource efficiency and optional achievements appropriate to scenario; explicit weights and tie-break before play. Avoid casualty farming, repeated replays for grind, opaque penalties or power rewards. Medals and trophies reflect meaningful accomplishment; local records offline, eligible online records segregated by version/seed/rules/assistance/mods. Optional challenge leaderboards use trust classification, dedicated verification or replay evidence where feasible; host-supplied records unverified. Offline records never require upload. Co-op/PvP only where role/objective design supports it; no forced competitive mode.

Loop: quick preset -> brief -> fight -> adapt -> debrief -> retry seed or generate fresh challenge. Optional tutorial hint, replay timeline and records. Retry restores clean starting scenario, no changes to Dynasty. Shared generator, objective framework, AI, archive and replay. [Player experience](PLAYER_EXPERIENCE.md) · [Records](REPLAY_SPECTATOR_AND_RECORDS.md).

## Acceptance
All seven distinct families, reproducible seeds, valid reachable objectives, score explanation, challenge end/retry, local records and eligible online comparisons, no pay-to-win/grind, accessibility and assistance transparency, quick start friction and enjoyable short-session playtests.
