#!/bin/bash
# Builds the native sim core (Rust + godot-rust gdext) and installs the DLL in bin/.
#   bash tools/build_native.sh [--debug] [--stage]
#     --stage   build and copy to bin/rts_core.new.dll only (test it in a sandbox first)
#     --swap    install a previously staged bin/rts_core.new.dll (no build)
# Install is a swap, never an overwrite in place: a DLL loaded by a running godot is locked on
# Windows but may be renamed, so the live one is renamed to bin/rts_core.prev*.dll first (deleted on the next install) and the
# new one moved in (retried for ~60 s). Needs rustc/cargo (msvc target) on PATH or at ~/.cargo/bin.
# The built bin/rts_core.dll is committed, so a fresh clone runs without Rust (CONTRACTS_G3b s5).
set -e
cd "$(dirname "$0")/.."
export PATH="$HOME/.cargo/bin:$PATH"
PROFILE=release
FLAG=--release
STAGE=0
SWAP_ONLY=0
for a in "$@"; do
  case "$a" in
    --debug) PROFILE=debug; FLAG= ;;
    --stage) STAGE=1 ;;
    --swap) SWAP_ONLY=1 ;;
  esac
done
mkdir -p bin
if [ "$SWAP_ONLY" = 0 ]; then
  ( cd native/rts_core && cargo build $FLAG )
  cp "native/rts_core/target/$PROFILE/rts_core.dll" bin/rts_core.new.dll
  echo "staged bin/rts_core.new.dll ($PROFILE, $(wc -c < bin/rts_core.new.dll) bytes)"
  [ "$STAGE" = 1 ] && exit 0
fi
[ -f bin/rts_core.new.dll ] || { echo "no bin/rts_core.new.dll to install"; exit 1; }
for i in $(seq 1 30); do
  rm -f bin/rts_core.prev*.dll 2>/dev/null || true   # old copies still loaded somewhere stay
  PREV="bin/rts_core.prev$$_$i.dll"
  if [ ! -f bin/rts_core.dll ] || mv -f bin/rts_core.dll "$PREV" 2>/dev/null; then
    if mv -f bin/rts_core.new.dll bin/rts_core.dll 2>/dev/null; then
      echo "installed bin/rts_core.dll ($(wc -c < bin/rts_core.dll) bytes, try $i)"
      exit 0
    fi
    mv -f "$PREV" bin/rts_core.dll 2>/dev/null || true
  fi
  sleep 2
done
echo "could not swap bin/rts_core.dll (locked?); new build left at bin/rts_core.new.dll"
exit 1
