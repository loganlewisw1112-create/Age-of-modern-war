# Task 19 Report — MODE10 Skirmish stages + Coalition LP profile

## Status

Complete (API + menu + tests green). `world.gd` stage gate still global `playable_now` — NEED for ORCH. No commit. No `world.gd` edit.

## Authority

- Plan Task 19: `docs/superpowers/plans/2026-11-23-g10-shadow-coalition.md`
- Scope: `game/docs/G10_SCOPE.md` modes §9 / done-when 11
- Board CLAIM seq **179**

## Files (MODE10 claim)

| Path | Action |
|------|--------|
| `game/sim/systems/last_protocol.gd` | `make_config(..., profile)`, `profile(w)`, Coalition loss/fill hooks |
| `game/sim/systems/lp_setup.gd` | `start_spec(w)` + Coalition facility/army/plots/fill; skip CN/g71/fleet |
| `game/presentation/ui7/lp_menu.gd` | **Coalition Protocol** button → `profile="shadow_coalition"` |
| `game/content/g10/lp_profile_coalition.json` | Created — Stage 10 Coalition LP start/loss/plot_remap |
| `game/tests/test_g10_modes.gd` | Created — 8 acceptance tests |

Coord: `skirmish_setup.gd` unchanged (Task 2 faction stage lists already ship).

## APIs

```gdscript
LastProtocol.make_config(seed, map_id = "", profile = "human_a") -> Dictionary
LastProtocol.profile(w) -> String   # "human_a" | "shadow_coalition"
LpSetup.start_spec(w) -> Dictionary
```

- `profile="human_a"` (default): config **byte-equivalent** to pre-G10 (no `lp_profile` key).
- Coalition: `cfg.lp_profile="shadow_coalition"`, Stage 10, Ghost complex + safehouse/tunnels, Coalition army/air, `lp_obj_team` loss; Machine map/cores unchanged. No CN teams/facility/Fleet71/g71_lp Human A cards.

## Tests

| Suite | Result |
|-------|--------|
| `test_g10_modes` | pass=8 fail=0 |
| `test_lpmode7` | pass=18 fail=0 |
| `test_lp_save71` | pass=2 fail=0 |

```
godot --headless --path game -s res://tests/run_tests.gd -- --only=test_g10_modes
# RESULT pass=8 fail=0
```

## NEED (ORCH)

`SimWorld.validate_config` still rejects non-`playable_now` stages globally. Coalition Stages 3/12 boot via stamp-after-Stage-8 (same as Task 2 soak). Wire faction-aware check via `G3bData.playable_stages_for(faction)` in `world.gd` at E3.

## ORCH next

- Commit MODE10 slice; accept NEED for `validate_config` Coalition stages.
- Keep LP exclusive to MODE10 until RELEASE.
