extends SceneTree
## G7.1 look-checkpoint contact pack (Done-when 5). Groups PNGs under assets/art/g71_* into per-def
## strips (no masks), writes PNGs + OWNER_CHECKLIST for owner approve/reject.
##   godot --headless --path . -s tools/art/g71_lookcheck.gd [-- --out=<abs dir>]
const PAD := 3
const LABEL_H := 10
const GROUPS := ["g71_army", "g71_defences", "g71_fires", "g71_cn", "g71_damage", "g71_farp", "g71_siege", "g71_special", "g71_fleet"]
const SUBS := ["units", "buildings", "icons"]
const FONT := {"A": 0x7B6F, "B": 0x6BAE, "C": 0x7927, "D": 0x6B6E, "E": 0x79A7, "F": 0x79A4, "G": 0x796F,
	"H": 0x5BED, "I": 0x7497, "J": 0x126F, "K": 0x5BAD, "L": 0x4927, "M": 0x5FED, "N": 0x6B6D, "O": 0x7B6F,
	"P": 0x7BE4, "Q": 0x7B79, "R": 0x7BAD, "S": 0x79CF, "T": 0x7492, "U": 0x5B6F, "V": 0x5B6A, "W": 0x5BFD,
	"X": 0x5AAD, "Y": 0x5A92, "Z": 0x72A7, "0": 0x7B6F, "1": 0x2C97, "2": 0x73E7, "3": 0x73CF, "4": 0x5BC9,
	"5": 0x79CF, "6": 0x79EF, "7": 0x7249, "8": 0x7BEF, "9": 0x7BCF, "_": 0x0007, "-": 0x01C0, " ": 0}


func _init() -> void:
	var out := ProjectSettings.globalize_path("res://.plan/shots/G71_LOOK")
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			out = String(a).substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var index: Array = []
	var n := 0
	for g in GROUPS:
		var base_fs := ProjectSettings.globalize_path("res://assets/art/%s/" % g)
		if not DirAccess.dir_exists_absolute(base_fs):
			continue
		var by_id: Dictionary = {}
		for sub in SUBS:
			var sub_fs := base_fs.path_join(sub)
			if not DirAccess.dir_exists_absolute(sub_fs):
				continue
			var da := DirAccess.open(sub_fs)
			if da == null:
				continue
			da.list_dir_begin()
			var fname := da.get_next()
			while fname != "":
				if not da.current_is_dir() and fname.ends_with(".png") and not fname.contains("_mask"):
					var id := _base_id(fname.get_basename())
					if not by_id.has(id):
						by_id[id] = []
					(by_id[id] as Array).append(sub_fs.path_join(fname))
				fname = da.get_next()
			da.list_dir_end()
		var ids: Array = by_id.keys()
		ids.sort()
		for id in ids:
			var paths: Array = by_id[id]
			paths.sort()
			# Cap frames so strips stay readable: prefer base + a few variants.
			var picked: Array = _pick(paths)
			var strip := _strip(String(id), picked)
			var name := "strip_%s_%s.png" % [g, String(id)]
			strip.save_png(out.path_join(name))
			var big := strip.duplicate() as Image
			big.resize(maxi(strip.get_width() * 2, 2), maxi(strip.get_height() * 2, 2), Image.INTERPOLATE_NEAREST)
			big.save_png(out.path_join(name.replace(".png", "_2x.png")))
			index.append({"group": g, "id": String(id), "frames": picked.size(), "file": name})
			n += 1
	var f := FileAccess.open(out.path_join("contact_index.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"samples": index,
		"count": n,
		"note": "Owner: approve/reject each id; see docs/G71_LOOK_CHECKPOINT.md",
	}, "  ", false))
	f.close()
	var chk := FileAccess.open(out.path_join("OWNER_CHECKLIST.txt"), FileAccess.WRITE)
	chk.store_string("G7.1 look checkpoint strips (%d samples)\nApprove or reject each id.\n\n" % n)
	for s in index:
		chk.store_string("[ ] %s / %s  (%s)\n" % [s.group, s.id, s.file])
	chk.close()
	print("G71_LOOKCHECK samples=%d out=%s" % [n, out])
	quit(0 if n > 0 else 1)


func _base_id(stem: String) -> String:
	# Strip common suffixes: _a1, _rot_0, _aim_3, _build_0, _damaged, _fire, _recoil, _impact_0
	var s := stem
	for _i in 8:
		var next := s
		for suf in ["_damaged", "_fire", "_recoil", "_mask"]:
			if next.ends_with(suf):
				next = next.substr(0, next.length() - suf.length())
		var re_num := RegEx.new()
		re_num.compile("_(a|rot|aim|build|impact)_?\\d+$")
		var m := re_num.search(next)
		if m:
			next = next.substr(0, m.get_start())
		if next == s:
			break
		s = next
	return s


func _pick(paths: Array) -> Array:
	var out: Array = []
	# Prefer the plain sheet first, then up to 7 more variants.
	var plain: Array = []
	var rest: Array = []
	for p in paths:
		var bn: String = String(p).get_file().get_basename()
		if not bn.contains("_a") and not bn.contains("_rot") and not bn.contains("_aim") and not bn.contains("_build") and not bn.contains("_impact") and not bn.ends_with("_fire") and not bn.ends_with("_damaged") and not bn.ends_with("_recoil"):
			plain.append(p)
		else:
			rest.append(p)
	for p in plain:
		out.append(p)
		if out.size() >= 8:
			return out
	for p in rest:
		out.append(p)
		if out.size() >= 8:
			break
	return out


func _strip(id: String, paths: Array) -> Image:
	var imgs: Array = []
	var max_h := 1
	var total_w := 0
	for p in paths:
		var im := Image.load_from_file(String(p))
		if im == null:
			continue
		im.convert(Image.FORMAT_RGBA8)
		imgs.append(im)
		max_h = maxi(max_h, im.get_height())
		total_w += im.get_width() + PAD
	if imgs.is_empty():
		var empty := Image.create(80, 24, false, Image.FORMAT_RGBA8)
		empty.fill(Color8(40, 40, 40))
		_label(empty, id, 2, 8)
		return empty
	total_w = maxi(total_w - PAD, 8)
	var label_w := maxi(total_w, id.length() * 4 + 4)
	var out := Image.create(label_w, max_h + LABEL_H + 2, false, Image.FORMAT_RGBA8)
	out.fill(Color8(48, 56, 44))
	var x := 0
	for im in imgs:
		var y := LABEL_H + 1 + int((max_h - im.get_height()) / 2)
		out.blend_rect(im, Rect2i(0, 0, im.get_width(), im.get_height()), Vector2i(x, y))
		x += im.get_width() + PAD
	_label(out, id, 2, 1)
	return out


func _label(img: Image, text: String, x0: int, y0: int) -> void:
	var x := x0
	for ch in text.to_upper():
		var bits: int = int(FONT.get(ch, 0))
		for row in 5:
			for col in 3:
				if (bits >> (row * 3 + col)) & 1:
					var px := x + col
					var py := y0 + row
					if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
						img.set_pixel(px, py, Color8(230, 230, 220))
		x += 4
