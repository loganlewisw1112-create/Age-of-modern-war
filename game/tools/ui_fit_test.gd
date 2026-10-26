extends SceneTree
## UI5a (G5): the "everything fits" guarantee. Opens every screen and panel at 7 resolutions
## (optionally at several UI scales) inside a SubViewport of exactly that size and reports:
##   CLIP     a visible control whose rect leaves the viewport;
##   OVERFLOW a visible control that spills out of its frame (nearest Panel/PanelContainer);
##   TEXTCUT  a Button with clip_text whose text is wider than the button;
##   OVERLAP  two top-level frames of the same layer that overlap (modal frames are exempt).
## Controls inside a clip_contents ancestor (ScrollContainer) are checked only through that ancestor.
## Run (from the game folder):
##   godot --path . [--headless] -s tools/ui_fit_test.gd -- [--fit-out=ABS_DIR]
##        [--fit-scales=1,0.75,1.5] [--fit-res=1280x720,1920x1080] [--fit-screens=main_menu,hud_idle]
##        [--fit-font=final]   (measure with FONT's rts_mil TTFs even before font.final)
##        [--fit-full]         (windowed: also save every screen full size, <screen>_<W>x<H>_s<scale>.png)
## Prints "FIT <W>x<H> s=<scale> <screen> <KIND> <path> <detail>" per issue, a summary per screen and a
## final "FIT RESULT screens=N issues=K". Windowed runs also save sheet_<W>x<H>_s<scale>.png
## (one thumbnail per screen, issue rects outlined red) into --fit-out.

const Screens = preload("res://presentation/ui5/kit/fit_screens.gd")

const RES := [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2560, 1440), Vector2i(3440, 1440), Vector2i(3840, 2160)]
const TOL := 1.0          # px slack for rounding
const FRAME_TYPES := ["Panel", "PanelContainer", "ScrollContainer", "TabContainer"]

var out_dir := ""
var shots := false
var full_shots := false   # G6 (UI6a): --fit-full also saves each screen full size as <screen>_<W>x<H>_s<scale>.png
var scales: Array = [1.0]
var res_list: Array = RES.duplicate()
var only_screens: Array = []
var issues: Array = []          # {res, scale, screen, kind, path, detail, rect}
var screens_run := 0
var controls_checked := 0


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var s := String(a).trim_prefix("--")
		var eq := s.find("=")
		args[s.substr(0, eq) if eq >= 0 else s] = s.substr(eq + 1) if eq >= 0 else "1"
	out_dir = String(args.get("fit-out", ""))
	if args.has("fit-scales"):
		scales = []
		for t in String(args["fit-scales"]).split(",", false):
			scales.append(float(t))
	if args.has("fit-res"):
		res_list = []
		for t in String(args["fit-res"]).split(",", false):
			var p := String(t).split("x")
			res_list.append(Vector2i(int(p[0]), int(p[1])))
	if args.has("fit-screens"):
		only_screens = Array(String(args["fit-screens"]).split(",", false))
	shots = out_dir != "" and DisplayServer.get_name() != "headless"
	full_shots = shots and args.has("fit-full")
	if String(args.get("fit-font", "")) == "final":
		load("res://presentation/ui5/kit/ui_kit.gd").preview_final = true
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	Content.load_all()
	var names: Array = Screens.NAMES if only_screens.is_empty() else only_screens
	for sc in scales:
		for r in res_list:
			var thumbs: Array = []
			for nm in names:
				var img = await _run_screen(String(nm), r, float(sc))
				if img != null:
					thumbs.append(img)
			if shots and not thumbs.is_empty():
				_save_sheet(thumbs, r, float(sc), names)
	_report()
	quit(0 if issues.is_empty() else 1)


## Build one screen in a fresh SubViewport of size r, settle the layout, check it, optionally shoot it.
func _run_screen(nm: String, r: Vector2i, sc: float) -> Variant:
	var vp := SubViewport.new()
	vp.size = r
	vp.gui_disable_input = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if shots else SubViewport.UPDATE_DISABLED
	root.add_child(vp)
	var ok: bool = await Screens.build(nm, vp, sc, self)
	if not ok:
		print("FIT %dx%d s=%s %s SKIP (screen not available)" % [r.x, r.y, _sf(sc), nm])
		vp.queue_free()
		await process_frame
		return null
	for i in 4:
		await process_frame
	screens_run += 1
	var found := _check(vp, nm, r, sc)
	var img: Variant = null
	if shots:
		await RenderingServer.frame_post_draw
		var full: Image = vp.get_texture().get_image()
		if full != null and not full.is_empty():
			_outline(full, found, r)
			if full_shots:
				full.save_png("%s/%s_%dx%d_s%s.png" % [out_dir, nm, r.x, r.y, _sf(sc)])
			var tw := 480
			full.resize(tw, int(round(float(tw) * r.y / r.x)), Image.INTERPOLATE_BILINEAR)
			img = full
	Screens.teardown(vp)
	vp.queue_free()
	await process_frame
	await process_frame
	return img


func _sf(sc: float) -> String:
	return str(snappedf(sc, 0.01))


# ------------------------------------------------------------------ checks
func _check(vp: SubViewport, nm: String, r: Vector2i, sc: float) -> Array:
	var view := Rect2(Vector2.ZERO, Vector2(r))
	var found: Array = []
	var groups := {}   # layer instance id -> Array of {rect, path, modal}
	for c in _all_controls(vp):
		var ctl: Control = c
		if not _visible(ctl):
			continue
		controls_checked += 1
		var rect := _vrect(ctl)
		if rect.size.x < 0.5 or rect.size.y < 0.5:
			continue
		var clip_anc := _clip_ancestor(ctl)
		if clip_anc == null:
			if not view.grow(TOL).encloses(rect):
				found.append(_issue(r, sc, nm, "CLIP", ctl, rect, "rect=%s view=%s" % [_rs(rect), _rs(view)]))
			var fr := _frame_ancestor(ctl)
			if fr != null:
				var frect := _vrect(fr)
				if not frect.grow(TOL + 1.0).encloses(rect):
					found.append(_issue(r, sc, nm, "OVERFLOW", ctl, rect, "rect=%s frame=%s" % [_rs(rect), _rs(frect)]))
		if ctl is Button and (ctl as Button).clip_text and (ctl as Button).text != "":
			var b := ctl as Button
			var font := b.get_theme_font("font")
			var fs := b.get_theme_font_size("font_size")
			var sb := b.get_theme_stylebox("normal")
			var avail := b.size.x - (sb.get_minimum_size().x if sb != null else 0.0)
			if b.icon != null:
				avail -= b.icon.get_width()
			var need := font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if need > avail + 2.0:
				found.append(_issue(r, sc, nm, "TEXTCUT", ctl, rect, "need=%d have=%d" % [int(need), int(avail)]))
		if _is_frame_top(ctl, view, rect):
			var key := _layer_key(ctl)
			if not groups.has(key):
				groups[key] = []
			groups[key].append({"rect": rect, "ctl": ctl, "modal": _is_modal(ctl)})
	for key in groups:
		var g: Array = groups[key]
		for i in g.size():
			for j in range(i + 1, g.size()):
				if g[i].modal or g[j].modal:
					continue
				var a: Rect2 = g[i].rect
				var b2: Rect2 = g[j].rect
				var inter := a.intersection(b2)
				if inter.size.x > TOL and inter.size.y > TOL:
					found.append(_issue(r, sc, nm, "OVERLAP", g[i].ctl, inter,
						"with=%s area=%dx%d" % [_path(g[j].ctl), int(inter.size.x), int(inter.size.y)]))
	return found


func _all_controls(n: Node, out: Array = []) -> Array:
	for c in n.get_children():
		if c is Window:
			continue
		if c is Control:
			out.append(c)
		_all_controls(c, out)
	return out


func _visible(c: Control) -> bool:
	if not c.is_visible_in_tree():
		return false
	var p: Node = c
	while p != null and not (p is SubViewport):
		if p is CanvasLayer and not (p as CanvasLayer).visible:
			return false
		if p is CanvasItem and (p as CanvasItem).modulate.a < 0.02:
			return false
		p = p.get_parent()
	return true


func _vrect(c: Control) -> Rect2:
	return c.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, c.size)


func _clip_ancestor(c: Control) -> Control:
	var p := c.get_parent()
	while p is Control:
		if (p as Control).clip_contents:
			return p
		p = p.get_parent()
	return null


func _is_frame(c: Node) -> bool:
	return c is Control and (FRAME_TYPES.has(c.get_class()) or c.has_meta("ui_fit"))


func _frame_ancestor(c: Control) -> Control:
	var p := c.get_parent()
	while p is Control:
		if p is Panel or p is PanelContainer:
			return p
		p = p.get_parent()
	return null


func _is_frame_top(c: Control, view: Rect2, rect: Rect2) -> bool:
	var loose := (c is Label and (c as Label).text.strip_edges() != "") or (c is Button and (c as Button).text != "")
	if not _is_frame(c) and not loose:
		return false
	if rect.get_area() >= view.get_area() * 0.97:
		return false   # full-screen backdrop / dimmer
	var p := c.get_parent()
	while p is Control:
		if _is_frame(p) and not loose:
			return false
		if loose and (p is Button or _is_frame(p)):
			return false
		p = p.get_parent()
	return true


func _is_modal(c: Node) -> bool:
	var p := c
	while p is Control:
		if p.has_meta("ui_modal"):
			return true
		p = p.get_parent()
	return false


func _layer_key(c: Node) -> int:
	var p := c.get_parent()
	while p != null and not (p is SubViewport):
		if p is CanvasLayer:
			return p.get_instance_id()
		p = p.get_parent()
	return 0


func _path(c: Node) -> String:
	var parts: Array = []
	var p := c
	while p is Control:
		var nm := String(p.name)
		if nm.begins_with("@"):
			nm = p.get_class()
		if p is Label or p is Button:
			var t := String(p.text).replace("\n", " ").strip_edges()
			if t != "":
				nm += "\"%s\"" % t.substr(0, 22)
		parts.push_front(nm)
		p = p.get_parent()
	if parts.size() > 5:
		parts = [parts[0], "~"] + parts.slice(parts.size() - 3)
	return "/".join(parts)


func _rs(r: Rect2) -> String:
	return "%d,%d %dx%d" % [int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y)]


func _issue(r: Vector2i, sc: float, nm: String, kind: String, c: Control, rect: Rect2, detail: String) -> Dictionary:
	var it := {"res": "%dx%d" % [r.x, r.y], "scale": sc, "screen": nm, "kind": kind,
		"path": _path(c), "detail": detail, "rect": rect}
	issues.append(it)
	print("FIT %s s=%s %s %s %s %s" % [it.res, _sf(sc), nm, kind, it.path, detail])
	return it


# ------------------------------------------------------------------ output
func _outline(img: Image, found: Array, r: Vector2i) -> void:
	var t := maxi(2, r.x / 320)
	var col := Color(1, 0.1, 0.1, 1)
	var bounds := Rect2i(Vector2i.ZERO, img.get_size())
	for it in found:
		var rr: Rect2 = it.rect
		var ri := Rect2i(rr.position.floor(), rr.size.ceil()).intersection(bounds)
		if ri.size.x <= 0 or ri.size.y <= 0:
			continue
		for e in [Rect2i(ri.position, Vector2i(ri.size.x, t)), Rect2i(ri.position + Vector2i(0, ri.size.y - t), Vector2i(ri.size.x, t)),
				Rect2i(ri.position, Vector2i(t, ri.size.y)), Rect2i(ri.position + Vector2i(ri.size.x - t, 0), Vector2i(t, ri.size.y))]:
			img.fill_rect((e as Rect2i).intersection(bounds), col)


func _save_sheet(thumbs: Array, r: Vector2i, sc: float, names: Array) -> void:
	var cols := 4
	var tw: int = thumbs[0].get_width()
	var th: int = thumbs[0].get_height()
	var rows := int(ceil(float(thumbs.size()) / cols))
	var sheet := Image.create(cols * (tw + 4), rows * (th + 4), false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.05, 0.05, 0.05))
	for i in thumbs.size():
		var im: Image = thumbs[i]
		im.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i((i % cols) * (tw + 4), (i / cols) * (th + 4)))
	var base := "%s/sheet_%dx%d_s%s" % [out_dir, r.x, r.y, _sf(sc)]
	sheet.save_png(base + ".png")
	var f := FileAccess.open(base + ".txt", FileAccess.WRITE)
	if f != null:
		f.store_string("row-major order, %d per row:\n%s\n" % [cols, "\n".join(PackedStringArray(names))])


func _report() -> void:
	var by := {}
	for it in issues:
		var k := "%s %s %s" % [it.screen, it.kind, it.path]
		if not by.has(k):
			by[k] = []
		by[k].append("%s@%s" % [it.res, _sf(it.scale)])
	var keys := by.keys()
	keys.sort()
	for k in keys:
		print("FIT SUMMARY %s  [%s]" % [k, ", ".join(PackedStringArray(by[k]))])
	if out_dir != "":
		var rows: Array = []
		for it in issues:
			var d: Dictionary = it.duplicate()
			d.rect = _rs(it.rect)
			rows.append(d)
		var f := FileAccess.open(out_dir + "/fit_report.json", FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify({"screens_run": screens_run, "issues": rows, "distinct": keys.size()}, " "))
	print("FIT RESULT screens=%d controls=%d issues=%d distinct=%d" % [screens_run, controls_checked, issues.size(), keys.size()])
