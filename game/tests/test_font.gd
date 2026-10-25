extends "res://tests/test_base.gd"
## G5 acceptance (owner: FONT). CONTRACTS_G5 section 11.
## The game's own typeface: assets/fonts/rts_mil_{regular,bold}.ttf, built by tools/font/build_font.py.
## Fonts load with FontFile.load_dynamic_font (no .import files needed).

const REG_PATH := "res://assets/fonts/rts_mil_regular.ttf"
const BOLD_PATH := "res://assets/fonts/rts_mil_bold.ttf"

const LATIN := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
const DIGITS := "0123456789"
const PUNCT := "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
## UI symbols named in the plan (● × % + − / : arrows) plus the ones the HUD/editor already use.
const UI_SYMBOLS := "●×%+−/:←↑→↓•·°…–—‘’“”◆⟲⟳▲▼▶◀✓±¡¿"
const LATIN1 := "ÀÁÂÃÄÅÇÈÉÊËÌÍÎÏÑÒÓÔÕÖÙÚÛÜÝàáâãäåçèéêëìíîïñòóôõöùúûüýÿ"


func _load(path: String) -> FontFile:
	# load_dynamic_font returns OK even for a missing file (checked in Godot 4.7.2), so check the file first.
	if not check(FileAccess.file_exists(path), "%s does not exist" % path):
		return null
	var f := FontFile.new()
	var err := f.load_dynamic_font(ProjectSettings.globalize_path(path))
	if not check(err == OK, "load_dynamic_font %s failed (err %d)" % [path, err]):
		return null
	return f


func test_both_weights_load() -> void:
	var reg := _load(REG_PATH)
	var bold := _load(BOLD_PATH)
	if reg == null or bold == null:
		return
	check_eq(reg.get_font_name(), "RTS Mil", "regular family name")
	check_eq(bold.get_font_name(), "RTS Mil", "bold family name")
	check_eq(reg.get_font_style_name(), "Regular", "regular style name")
	check_eq(bold.get_font_style_name(), "Bold", "bold style name")
	check(bold.get_font_style() & TextServer.FONT_BOLD != 0, "bold face flagged bold")
	check(reg.get_font_style() & TextServer.FONT_BOLD == 0, "regular face not flagged bold")
	# both faces must actually shape text, and the bold face must be the wider/heavier one
	var s := "Rifle Squad 120/150 HP"
	var wr := reg.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	var wb := bold.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	check(wr > 100.0, "regular shapes a real string (width %.1f)" % wr)
	check(wb > wr, "bold is wider than regular (%.1f vs %.1f)" % [wb, wr])


func test_glyph_coverage_latin_digits_ui_symbols() -> void:
	var all := LATIN + DIGITS + PUNCT + UI_SYMBOLS + LATIN1
	for path in [REG_PATH, BOLD_PATH]:
		var f := _load(path)
		if f == null:
			continue
		var missing := ""
		var blank := ""
		for i in range(all.length()):
			var c := all.unicode_at(i)
			if not f.has_char(c):
				missing += String.chr(c)
			elif f.get_char_size(c, 32).x <= 0.0:
				blank += String.chr(c)
		check(missing == "", "%s missing glyphs: [%s]" % [path.get_file(), missing])
		check(blank == "", "%s zero-advance glyphs: [%s]" % [path.get_file(), blank])
		check(f.has_char(0x20) and f.get_char_size(0x20, 32).x > 0.0, "%s has a space" % path.get_file())


func test_kerning_pairs_applied() -> void:
	for path in [REG_PATH, BOLD_PATH]:
		var f := _load(path)
		if f == null:
			continue
		var off := FontVariation.new()
		off.base_font = f
		off.opentype_features = {"kern": 0}
		for s in ["AV", "AT", "To", "LT", "Yo"]:
			var on_w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 100).x
			var off_w := off.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 100).x
			check(on_w < off_w - 2.0, "%s kern pair %s tightens (on %.1f off %.1f)" % [path.get_file(), s, on_w, off_w])
