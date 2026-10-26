extends "res://tests/test_base.gd"
## G5 acceptance (owner: UI5a). CONTRACTS_G5 section 11.
## The fit checks run tools/ui_fit_test.gd in a headless child Godot (tests run inside
## SceneTree._init, where no screen can be instantiated), then parse its FIT lines.

const ScaledLayer = preload("res://presentation/hud/scaled_layer.gd")
const Screens = preload("res://presentation/ui5/kit/fit_screens.gd")
const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")
const HT = preload("res://presentation/hud/hud_theme.gd")
const RES7 := ["1280x720", "1366x768", "1600x900", "1920x1080", "2560x1440", "3440x1440", "3840x2160"]


## Runs the fit tool; returns {rc, screens, issues, skips, lines (issue lines, first 12)}.
func _fit(res: Array, scales: String) -> Dictionary:
	var out: Array = []
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "tools/ui_fit_test.gd", "--", "--fit-res=" + ",".join(PackedStringArray(res)), "--fit-scales=" + scales])
	var rc := OS.execute(OS.get_executable_path(), args, out, true)
	var text := "\n".join(PackedStringArray(out))
	var r := {"rc": rc, "screens": -1, "issues": -1, "skips": 0, "lines": [], "errors": []}
	for ln in text.split("\n"):
		var l := String(ln)
		if l.begins_with("FIT RESULT"):
			print("    [%s scales %s] %s" % [",".join(PackedStringArray(res)), scales, l])   # raw line for the run log (G6 UI6a)
			for part in l.split(" "):
				if part.begins_with("screens="):
					r.screens = int(part.get_slice("=", 1))
				elif part.begins_with("issues="):
					r.issues = int(part.get_slice("=", 1))
		elif l.begins_with("FIT ") and l.contains(" SKIP "):
			r.skips += 1
		elif l.begins_with("FIT ") and not l.begins_with("FIT SUMMARY") and r.lines.size() < 12:
			r.lines.append(l.substr(0, 200))
		elif l.contains("SCRIPT ERROR") and r.errors.size() < 6:
			r.errors.append(l.substr(0, 200))
	return r


func _report(r: Dictionary, what: String, want_screens: int) -> void:
	check(r.screens == want_screens, "%s: ran %d screens, expected %d (skips %d; errors %s)" % [what, r.screens, want_screens, r.skips, str(r.errors)])
	check(r.skips == 0, "%s: %d screens were not available" % [what, r.skips])
	check(r.issues == 0, "%s: %d clipped/overlapping controls, e.g. %s" % [what, r.issues, "\n    ".join(PackedStringArray(r.lines))])


func test_every_screen_fits_at_7_resolutions() -> void:
	var r := _fit(RES7, "1")
	_report(r, "7 resolutions at 100%", RES7.size() * Screens.NAMES.size())


func test_ui_scale_75_to_150_still_fits() -> void:
	# the scale maths: every resolution x every step keeps the virtual canvas >= the minimum, and a
	# larger setting never gives a smaller UI
	for res in RES7:
		var p := String(res).split("x")
		var vs := Vector2(float(p[0]), float(p[1]))
		var last := 0.0
		for st in ScaledLayer.SCALE_STEPS:
			var e := ScaledLayer.effective_scale(vs, float(st))
			var canvas := vs / e
			check(canvas.x >= ScaledLayer.MIN_CANVAS.x - 0.5 and canvas.y >= ScaledLayer.MIN_CANVAS.y - 0.5,
				"%s @%d%%: canvas %s below the minimum" % [res, int(st * 100), str(canvas)])
			check(e >= last - 0.0001, "%s: scale %d%% gives a smaller UI than the step below" % [res, int(st * 100)])
			last = e
	check(ScaledLayer.SCALE_STEPS.front() == 0.75 and ScaledLayer.SCALE_STEPS.back() == 1.5, "UI Scale range is 75-150%")
	# the real screens at both ends of the range, on the smallest, a 16:9 and the ultrawide display
	var res3 := ["1280x720", "2560x1440", "3440x1440"]
	var r := _fit(res3, "0.75,1.5")
	_report(r, "UI scale 75% and 150%", res3.size() * 2 * Screens.NAMES.size())


func test_typeface_applied_to_theme() -> void:
	# FONT delivers assets/fonts/rts_mil_{regular,bold}.ttf; UI5a switches the theme to it after
	# font.final (owner-approved specimen). Until then this stays red on purpose.
	check(UiKit.USE_FINAL_FONT, "UiKit.USE_FINAL_FONT is off (waiting for FONT's font.final)")
	check(FileAccess.file_exists(UiKit.FONT_REGULAR) and FileAccess.file_exists(UiKit.FONT_BOLD), "the rts_mil TTFs are not in assets/fonts yet")
	var t: Theme = HT.make_theme()
	var f: Font = t.default_font
	check(f is FontFile and String(f.resource_path) == UiKit.FONT_REGULAR,
		"theme default font is %s, expected %s" % [str(f.resource_path) if f != null else "null", UiKit.FONT_REGULAR])
	var bold: Font = t.get_font("font", "HeaderLabel")
	check(bold is FontFile and String(bold.resource_path) == UiKit.FONT_BOLD, "headers do not use the bold weight")
