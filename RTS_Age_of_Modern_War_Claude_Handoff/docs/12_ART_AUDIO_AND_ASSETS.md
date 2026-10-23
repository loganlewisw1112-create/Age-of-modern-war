# Art direction, approved mockups and asset pipeline

Status: consolidated handoff; no gameplay implementation or verification claimed.

Sources: [Master_GDD_v1.3](../source_text/Master_GDD_v1.3.md), [GDD_v1.0](../source_text/GDD_v1.0.md), [Technical_Architecture_v1.0](../source_text/Technical_Architecture_v1.0.md)

## Source-backed direction

Grounded gritty high-detail pixel art; layered 2.5D depth; readable proportional military silhouettes; industrial/post-collapse architecture; atmospheric light, weather, smoke, fire and dust. Fixed isometric angle for the first playable. Close, tactical and strategic visual scales are long-term presentation goals. Cinematic concept frames do not establish target performance or production asset readiness.

## Visual reference inventory and use

The six original PNGs are under `reference/Game_Project_GDD_Architecture_Approved_Mockups/Approved_Mockups/`:

| Reference | Intent visible in reviewed concept |
|---|---|
| 01_Survivor_Exploration.png | Ruined urban exploration, close character scale, warm interior light against cold ruins; future survivor mode |
| 02_Settlement_Construction.png | Dense fortified industrial settlement, build palette, utility/building readability |
| 03_Massive_Tactical_Battle.png | Bridge/river combined-arms battlefield, distant massing, smoke and layered silhouettes |
| 04_Continental_Strategy_Map.png | Regional network/territory overview and information panels; future strategic renderer |
| 05_Underground_Civilization.png | Multi-level cavern industry and inhabited infrastructure; future underground scope |
| 06_Mountain_Valley_Warfare.png | Ridgeline roads, fortification, battle fronts and terrain depth |

`originals/89848953-CBD7-41F9-9C0D-7D3AC3AD8414.jpeg` is an additional front-facing military taxonomy sheet with large and small unit presentations. It was visually inspected. Its projection and proportions differ from isometric world concepts; approval status as a production asset is not independently established. Use it for silhouette/role discussion, not direct sprite export or an implied final roster.

## Proposed production pipeline — decisions still required

First approve a small in-engine reference scene: infantry, tank, building, road/bridge, tree, muzzle flash and smoke against representative terrain at actual gameplay zoom. Choose camera tilt, pixels per world unit, sprite proportions, orientation count, palette/team treatment, frame counts, pivots, collision footprints and lighting conventions from this test. Do not choose pixel dimensions from the JPEG by assumption.

Author source files with stable asset IDs and record license/provenance, faction, stage, role, dimensions, pivot, animation states/directions, shadow policy, collision/navigation footprint and export settings. Export atlases with padding and consistent sampling; test animation bounds and ordering with structures/trees. Production metadata is proposed; no rights clearance or original layered artwork was supplied.

Readability review: unit vs ground contrast; infantry vs vehicles; friend vs foe with shape and color; obscured selections; cover/height; fog; projectiles; casualties; component disable states; reduced flash. Smoke and foreground layers must not hide critical commands. Benchmark effects density and draw cost before multiplying content.

Audio: local and distant weapons, machines, weather, civilian ambience and underground reverb; layered combat mixing and contextual music. Provide subtitles and visual alert equivalents. Final music, voice, source recordings and audio asset licenses are not supplied.
