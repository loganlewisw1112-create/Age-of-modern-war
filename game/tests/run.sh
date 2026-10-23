#!/bin/bash
# Authoritative test entry point. Exits non-zero on any failing test OR any SCRIPT ERROR /
# parse error in the output (Godot keeps running after runtime script errors, so the
# in-engine runner alone cannot be trusted).
#   bash tests/run.sh [--only=test_econ] [--import]
cd "$(dirname "$0")/.."
G="${GODOT:-/c/Users/logan/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe}"
if [ ! -f .godot/global_script_class_cache.cfg ]; then "$G" --headless --path . --import >/dev/null 2>&1; fi  # fresh checkout
ARGS=()
for a in "$@"; do
  if [ "$a" = "--import" ]; then "$G" --headless --path . --import >/dev/null 2>&1; else ARGS+=("$a"); fi
done
OUT=$(mktemp)
"$G" --headless --path . -s tests/run_tests.gd -- "${ARGS[@]}" > "$OUT" 2>&1
RC=$?
grep -E "^  (PASS|FAIL)|^FAILURE|^RESULT|SCRIPT ERROR|Parse Error|Compile Error|^ERROR|   at: " "$OUT" | cut -c1-240
ERRS=$(grep -cE "SCRIPT ERROR|Parse Error|Compile Error" "$OUT")
rm -f "$OUT"
if [ "$RC" -ne 0 ] || [ "$ERRS" -ne 0 ]; then echo "TESTS FAILED (rc=$RC script_errors=$ERRS)"; exit 1; fi
echo "TESTS OK"
