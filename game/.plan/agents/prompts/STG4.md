# STG4: Stage 7→8→9, research, new unit/building data (CONTRACTS_G3b §3)
Read G3B_COMMON.md first. Design source: `RTS_Age_of_Modern_War_Claude_Handoff/docs/06_CIVILIZATIONS_13_STAGES.md` §4 (Stages 7-9), `04_FIRST_PLAYABLE.md` (MATCH-01), `15_TESTING_AND_RELEASE_GATES.md` (QA-002, QA-014). The gate numbers in CONTRACTS_G3b §3.2 are **owner-approved**: implement exactly those (they live in `rules.json` `advancement`, already added by the orchestrator).

Order (UI4, ART4 and AI4 depend on your data; land data first):
1. **Content data first** (post `fact stg4.data_ready` when done):
   - `stage_min`/`stage_max` on the gated defs;
   - the 9 new units (stats, weapons, production entries, hotkeys that don't collide) and 5 new buildings (research + comms);
   - `stage_roles` in factions.json; `content/research.json`; `comms: true` on m_sensor_relay;
   - in `stages.json`, set `playable_now: true` for 7 and 9.
   - Fix `world.validate_config`'s "(only Stage 8)" message via CHANGE_REQUEST if needed.
   - New defs need art; ART4 draws them. test_art may fail on the new defs until ART4 lands; that's expected, say so.
2. Gating in construction.gd / production.gd via `Content.available(d, stage)` + `requires_research`, with clear reasons.
3. Gate stat counters:
   - economy.gd: `ore_refined` when a refines-building consumes ore; `power_ok_ticks` (reset on any shortfall);
   - production.gd: `line_trained`, `officers_trained`.
4. progression.gd: research (one active project, any `research:true` building, pause on facility loss, ledger-charged cost); `advance_stage` (all gates, cost x rules mult, 60 s transition, `StageAdvanced` event, never spawns anything); `gate_report()`.
   - `Content.role(fdef, role, stage)` is ready; also update `w._place_start_package` start units per stage via CHANGE_REQUEST if Stage 7 should start with different units (e.g. no MBT-era recon). Keep it minimal.
5. EW + guided (status.gd, combat.gd hooks only). PERF4 takes combat.gd in wave 2, so keep your combat diff small and clearly marked.
6. `tests/test_stages.gd`: MATCH-01, QA-002, QA-014, each gate refuse/pass, cost charged once, no spawn on advance, research pause/resume, save round trip mid-research and mid-transition, EW status applies and expires. Keep test_factions/test_econ/test_mil green (adjust only tests that encode the old "only Stage 8" rule, and list those in your report).
MAX_TOKENS 700000, MAX_TOOL_CALLS 170, board id `STG4`.
