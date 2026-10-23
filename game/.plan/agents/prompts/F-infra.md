# F-infra: save/load, determinism, soak and perf harness
MAX_TOKENS 500000 | MAX_TOOL_CALLS 130 | model sonnet (bounded infra spec)

You own `sim/save_system.gd`, `tools/soak.gd`, `tools/bench.gd`, `tests/test_save.gd`, `tests/test_determinism.gd`, `perf/**`.
Implement CONTRACTS.md section 8.

Details:
- save_system.gd: no class_name (preload it).
  - `save(w, path) -> String` writes atomically: tmp file, verify it parses and the schema matches, keep .bak, then rename.
  - `load(path) -> SimWorld` returns null and calls push_error on a missing, corrupt or wrong-schema file.
  - `list_slots() -> Array` serves the UI ({path, tick, date}). Store the tick and wall-clock date in a header line or embedded meta.
- Agents A and B (econ/mil), and later the AI agent, are implementing the systems concurrently. Your tests must hold whatever those systems do:
  - Compare whole-state hashes between two identical runs, and between save->load->continue and an uninterrupted run.
  - Drive them with a scripted command stream (moves, gather, build, queue_unit). Commands rejected today are fine, since rejections are deterministic too.
  - Run at least 3000 ticks, both with both sides AI-enabled (`cfg.sides[0].ai = true`) and with the player scripted.
- SAVE-01 field checks: treasury, stock, hp, ownership, queues, orders, rng state, next_id, entity ids, fog arrays,
  memory and ai_state are all equal after a round trip. A corrupt or truncated file and a wrong schema_version are rejected.
- tools/soak.gd: `"$G" --headless --path . -s tools/soak.gd -- --seed=N --max-ticks=36000 --difficulty=normal`
  - Runs AI vs AI and prints a summary every 1200 ticks (tick, credits, unit counts, buildings, kills per side).
  - Ends with `SOAK RESULT winner=<fid|none> end_tick=<n> reason=<...> hash=<state_hash>`. Exits 0 unless a script error occurs.
  - Checks invariants every 600 ticks and prints `INVARIANT FAIL ...` lines: no negative balances, no duplicate ids, every unit in a passable cell, pop <= cap + in-flight squad.
- tools/bench.gd: per CONTRACTS section 8.
  - N total = 64, 128, 256, 512. Mixed infantry and vehicles face each other on open ground west of the map centre, with attack_move toward each other.
  - Report avg/p95/max ms per tick, entity counts, survivors after 600 ticks, CPU name, RAM, Godot version and date.
  - Write `perf/BENCH_<YYYY-MM-DD>.md` and print a table. This measures SIM time only; agent D measures rendering fps separately.
- Run the bench once at the end. Until A and B land it mostly measures stubs, so label the report with the git state and
  which systems were real. The orchestrator re-runs it at integration.
