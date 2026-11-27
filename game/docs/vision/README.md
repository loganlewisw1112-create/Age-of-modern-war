# Vision references (owner-supplied)

These images show where the owner wants the game to go visually and in scale. They are **concept references**, not shipped screens and not approved scope. As with the handoff's `Approved_Mockups/` (DEC-12), match their mood, readability and density direction, not their exact content.

## 2026-10-23 (supplied by the owner during G3a)

| File | What it shows | Most useful for |
|---|---|---|
| `2026-10-23/01_continental_war_status_map.webp` | A multi-continent strategic map: territory borders in each faction's colour, fleets and convoy lanes, a War Status panel (territory %, bases, armies, fleets, population per faction), and an expeditionary-force panel with Airlift / Naval support / Launch offensive | G5/G6 continental layer, a naval/air roster, the territory % UI (G3a territory mode is the first small step) |
| `2026-10-23/02_mountain_stronghold_bridge_assault.webp` | A walled mountain fortress with a waterfall dam, bridges under assault, a dense red horde, artillery and smoke, and squad orders including "Use cover", "Defend position" and "Disembark" | Large battles (500–2,000 units), walls/gates, cover UI, the transport "Disembark" order |
| `2026-10-23/03_mountain_stronghold_wall_defense_a.webp` | Stronghold defence: wall lines and gatehouses, turrets firing, wave-defence objectives ("Repel all enemy waves", "Survive for 30:00") | Wall and gate building (BUILD-01 road/wall tool), survival/wave victory types |
| `2026-10-23/04_mountain_stronghold_wall_defense_b.webp` | An alternate angle of 03: layered fortifications on a ridge, and the river crossing | The same, plus how terrain height should read |
| `2026-10-23/05_city_battle_infantry_company.webp` | A dense urban battle: a 24-unit Infantry Company group card with a unit grid, a Battle Status panel (our and enemy units and groups, incoming waves), and an officer requesting air support | Company/group UI (G2 officer groups grown up), the battle-status panel, unit density |
| `2026-10-23/06_forward_base_tank_company.webp` | A forward-base battle at a closer zoom: a Tank Company group card, missile turrets, wreck fires, Human A, Human B and Machine-style buildings mixed in a base | **Closest to the current build.** Target density and detail for the next art and scale passes |

## Notes for whoever builds from these (keep the record honest)
- The mockups show **"Stage 15"**, "Stage 13" and "Stage 12" in the top bar. The approved design says there are **exactly 13 stages** (DEC-03, Master GDD §5). Treat the stage numbers in these images as placeholders, not a change to the 13-stage model. If the owner wants more than 13 stages, that needs a decision-register entry first.
- The numbers in the images (populations of 286–412, credits of 18k–28k, "Survive 30:00" and so on) are illustrative, not balance targets.
- Features shown that are **not yet built**:
  - naval units and fleets, airlift, aircraft;
  - walls and gates;
  - multi-continent maps;
  - group cards with unit grids;
  - a battle-status panel;
  - wave and survival victory types;
  - transports (Disembark).
  These map onto roadmap G3b–G6 and need their own scoping.
- The scale shown (hundreds of units on screen) is beyond the measured cap: about 512 simulated units within budget, and roughly 20–24 fps at about 440 units (see `perf/`). Getting there needs the G4 work: a sim thread and rendering LOD.
- File hashes (sha256, first 16 hex): 01 `868ce2cdbe8d6d03`, 02 `14c659cea2b9fd53`, 03 `47624a6137066171`, 04 `d7eedbfb66d6a07c`, 05 `11635fb0195886a1`, 06 `207dc3efa5723ff9`.


## Future expansion authority (2026-11-27)

[Space Expansion master design](../SPACE_EXPANSION_GDD.md) records the approved DLC 1 / DLC 2 numbering, True Dynasty and independent starts, stellar catalog, Hidden Chronicle and engineering guidance. These are future planning specifications only; do not implement ahead of existing gates. No change to current source, build, save format or completion status.
