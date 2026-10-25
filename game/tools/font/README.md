# RTS Mil: the game's own typeface

Military-modern stencil UI face for *Age of Modern War*, in two weights:
`assets/fonts/rts_mil_regular.ttf` (400) and `assets/fonts/rts_mil_bold.ttf` (700).

## Licence / provenance

**Original work.** Every outline is hand-placed as coordinates in `glyphs.py` and turned into
TrueType contours by `build_font.py` using fontTools. No existing font was copied, traced,
converted, or used as a reference outline; the TTFs contain no third-party glyph data. The
font is part of this game's own assets and is covered by the project's licence.

## Design

- UPM 1000; cap height 700; x-height 520 (tall, for small HUD sizes); descender -190.
- Straight strokes only: 45-degree chamfered outer corners, square counters.
- Angular stencil cuts (gap 34 units regular / 42 bold): through O/0/Q, at stem-to-bowl joins
  of B D P R b d p q, at stem-to-arm joins of E F, and so on. They read at 32-48 px and close up
  at 12-16 px.
- Disambiguation: slashed 0 versus the cut O; 1 has a flag and foot, l has a tail, I has bars.
- Kerning: GPOS `kern` pairs for the common pairs (T, A, V, W, Y, L, P, F, quotes, punctuation).
  Bold uses the same pairs scaled by 1.1.

## Coverage (184 code points per weight)

ASCII 0x20-0x7E; Latin-1 accented vowels plus Ç/ç and Ñ/ñ (built as composites); and the UI symbols
● × % + − / : ← ↑ → ↓ • · ° … – — ‘ ’ “ ” ◆ ⟲ ⟳ ▲ ▼ ▶ ◀ ✓ ± ¡ ¿.
Not covered yet: Æ æ Ø ø Œ œ ß, currency other than $, and Latin Extended-A.

## Build and check

From `game/`:

```
py -3.12 tools/font/build_font.py --check     # writes both TTFs; overlap + empty-outline report
bash tools/font/render_specimen.sh            # windowed Godot run -> assets/fonts/specimen.png
py -3.12 tools/font/preview.py out.png 64     # quick pure-Python raster preview (no Godot)
godot --headless --path . -s tests/run_tests.gd -- --only=test_font
```

`--check` reports 2 sample hits on the regular `asterisk`, where its arms abut the hub after
rounding. That is harmless under nonzero fill.

## Using it in Godot

```gdscript
var f := FontFile.new()
f.load_dynamic_font(ProjectSettings.globalize_path("res://assets/fonts/rts_mil_regular.ttf"))
```

Note: `load_dynamic_font` returns `OK` even when the path is missing (Godot 4.7.2), so check
`FileAccess.file_exists` first. `load("res://...ttf")` works once the editor has imported the files.

## Files

- `geom.py`: polyline-stroke outliner (chamfers, caps) and half-plane clipping.
- `glyphs.py`: one design function per glyph, plus the code-point table and composites.
- `build_font.py`: weights, kerning table, and the fontTools FontBuilder pipeline.
- `specimen.gd` / `render_specimen.sh`: Godot specimen sheet (12-48 px, dark and light, stat table, buttons).
- `preview.py`: fast raster preview that reads the built TTFs.
