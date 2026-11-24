# Task 2 Report — COUNT9+ play paths and coalition bridge

## Status

Complete. All 13 counters now record `play_ok` only after a real simulation effect. COUNT9 exports `try_coalition(w, fids, until_tick)`, `coalition_active(w)`, and `in_dead_zone(w, cell)`, and emits `CoalitionFormed`.

## RED evidence

Command:

`godot --headless --path game -s res://tests/run_tests.gd -- --only=test_count9`

Initial result: parse failure (`pass=0 fail=0`) because `reverse_engineered`, `try_coalition`, and `in_dead_zone` did not exist and `coalition_active` still required a faction argument.

## GREEN evidence

The 13 tests each assert both a concrete effect and harness `play_ok`: relay isolation, EMP hold, denied wreck skip, seed purge, virus relay cut, command removal/pulse loss, power deficit, reverse-engineering unlock, blocking fire cell, temporary alliance/expiry, dead-zone relay unlink, hunter tag, and owner reprogram.

Final command:

`godot --headless --path game -s res://tests/run_tests.gd -- --only=test_count9`

Result: `pass=13 fail=0 files=1 time_ms=14595`.

IDE diagnostics: no linter errors in the changed GDScript files. `git diff --check` passed.

## Coalition contract

`try_coalition` validates unique live faction IDs and an absolute future tick, saves prior team assignments, assigns a temporary shared team so existing `SimWorld.is_enemy` combat paths reject friendly fire, emits `CoalitionFormed`, and restores the exact prior teams at expiry.

## Concerns

Coalition expiry is processed in COUNT9's normal system-order tick. The temporary team bridge intentionally affects every existing hostility query, not only direct weapon fire.
