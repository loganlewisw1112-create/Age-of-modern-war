extends "res://tests/test_base.gd"
## G5 acceptance (owner: UI5a). CONTRACTS_G5 section 11.
## The fit checks run tools/ui_fit_test.gd in a headless child Godot (tests run inside
## SceneTree._init, where no screen can be instantiated), then parse its FIT lines.

const ScaledLayer = preload("res://presentation/hud/scaled_layer.gd")
const Screens = preload("res://presentation/ui5/kit/fit_screens.gd")
const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")
const HT = preload("res://presentation/hud/hud_theme.gd")
const DroneCam = preload("res://presentation/view/drone_cam.gd")
const RES7 := ["1280x720", "1366x768", "1600x900", "1920x1080", "2560x1440", "3440x1440", "3840x2160"]


## Runs the fit tool; returns {rc, screens, issues, skips, lines (issue lines, first 12)}.
func _fit(res: Array, scales: String, screens: String = "") -> Dictionary:
	var out: Array = []
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "tools/ui_fit_test.gd", "--", "--fit-res=" + ",".join(PackedStringArray(res)), "--fit-scales=" + scales])
	if screens != "":
		args.append("--fit-screens=" + screens)
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


## G7 DFEED7: the drone camera's corner feed used to be drawn under the HUD's OBJECTIVES and VICTORY panels (top right),
## hiding most of the picture. The fit tool's FEEDCOVER check (a control with meta "ui_feed" must not touch any HUD frame
## of any layer, nor the OBJECTIVES / VICTORY panels) runs here on a skirmish HUD and on a Last Protocol HUD (no skirmish
## cards, its own card in the left stack) with the feed up, at all 7 resolutions and at the two UI scale extremes.
const DRONE_SCREENS := "hud_drone,ui7_lp_drone"


func test_drone_corner_feed_clear_of_hud_panels_at_7_resolutions() -> void:
	var r := _fit(RES7, "1", DRONE_SCREENS)
	_report(r, "drone corner feed, 7 resolutions at 100%", RES7.size() * 2)


func test_drone_corner_feed_clear_at_ui_scale_extremes() -> void:
	var res3 := ["1280x720", "2560x1440", "3440x1440"]
	var r := _fit(res3, "0.75,1.5", DRONE_SCREENS)
	_report(r, "drone corner feed, UI scale 75% and 150%", res3.size() * 2 * 2)


## The placement itself, on the rects of the real HUD at 1600x900 (top bar, right column with OBJECTIVES + VICTORY at
## 1282..1588 x 42..334, F3 button, bottom panel): the old fixed rect (vs.x - 432, 64, 420x250) sat on the column; the
## placed one must be on screen, touch none of them, and stay full size while a free spot exists.
func test_drone_corner_feed_placement() -> void:
	var vs := Vector2(1600, 900)
	var obj := Rect2(1282, 42, 306, 150)     # OBJECTIVES (inside the right column)
	var vic := Rect2(1282, 200, 306, 134)    # VICTORY
	var avoid: Array = [Rect2(0, 0, 1600, 42), Rect2(12, 42, 300, 264), Rect2(1282, 42, 306, 292), Rect2(0, 680, 1600, 220),
		Rect2(740, 46, 125, 30)]
	var old := Rect2(Vector2(vs.x - DroneCam.CORNER.x - 12.0, 64.0), DroneCam.CORNER)
	check(old.intersects(obj) and old.intersects(vic), "the old fixed corner rect covers OBJECTIVES and VICTORY (the bug)")
	var r := DroneCam.place_corner(vs, avoid)
	check(Rect2(Vector2.ZERO, vs).encloses(r), "placed feed %s is off screen" % str(r))
	check(r.size == DroneCam.CORNER, "full size is kept while a free spot exists, got %s" % str(r.size))
	check(not r.intersects(obj) and not r.intersects(vic), "placed feed %s still covers OBJECTIVES / VICTORY" % str(r))
	for a in avoid:
		check(not r.intersects(a as Rect2), "placed feed %s touches HUD rect %s" % [str(r), str(a)])
	# the real HUD at 1600x900 with UI scale 150% and the game paused (measured from the hud_drone fit screen): top bar, left
	# column, right column, bottom panel, group bar, F3 button, PAUSED banner mid-screen. No spot is free at full size, so
	# the feed shrinks instead of sliding under a panel.
	var tight: Array = [Rect2(0, 0, 1600, 63), Rect2(18, 63, 450, 396), Rect2(1102, 63, 480, 435), Rect2(0, 570, 1600, 330),
		Rect2(1268, 516, 314, 45), Rect2(710, 69, 187.5, 45), Rect2(691.25, 252.75, 217.5, 61.5)]
	var t := DroneCam.place_corner(vs, tight)
	check(t.size.x < DroneCam.CORNER.x and t.size.x >= DroneCam.CORNER.x * 0.6 - 0.01, "a crowded screen shrinks the feed, got %s" % str(t.size))
	check(Rect2(Vector2.ZERO, vs).encloses(t), "shrunk feed %s is off screen" % str(t))
	for a in tight:
		check(not t.intersects(a as Rect2), "shrunk feed %s touches %s" % [str(t), str(a)])
	# no HUD to avoid: the old spot, unchanged
	check(DroneCam.place_corner(vs, []) == old, "without a HUD the corner feed keeps its old spot")
