#!/bin/bash
# Builds the native sim core (Rust + godot-rust gdext) and copies the DLL to bin/.
#   bash tools/build_native.sh [--debug]
# Needs rustc/cargo (msvc target) on PATH or at ~/.cargo/bin. The built bin/rts_core.dll is
# committed, so a fresh clone runs without Rust (CONTRACTS_G3b section 5).
set -e
cd "$(dirname "$0")/.."
export PATH="$HOME/.cargo/bin:$PATH"
PROFILE=release
FLAG=--release
if [ "$1" = "--debug" ]; then PROFILE=debug; FLAG=; fi
( cd native/rts_core && cargo build $FLAG )
mkdir -p bin
cp "native/rts_core/target/$PROFILE/rts_core.dll" bin/rts_core.dll
echo "built bin/rts_core.dll ($PROFILE, $(wc -c < bin/rts_core.dll) bytes)"
