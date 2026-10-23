extends RefCounted
## Machine vehicles (agent ART3-M): cargo hauler, tracked platform, artillery node (+ wrecks) and the
## combat drone (hover sprite + separate ground shadow, see faction_m_drone.gd).
## Vehicle-style sheets: rows = 8 facings (world angle k * 45 deg), frames idle/move/fire.
const P = preload("res://tools/art/pix.gd")
const D = preload("res://tools/art/vdetail.gd")
const L = preload("res://tools/art/faction_m_lib.gd")
const DR = preload("res://tools/art/faction_m_drone.gd")

const FRAMES := ["idle", "move", "fire"]
const SPEC := {
	"m_hauler": {"fw": 62, "fh": 46, "pivot": [31, 30]},
	"m_tracked": {"fw": 70, "fh": 50, "pivot": [35, 32]},
	"m_artillery_node": {"fw": 64, "fh": 56, "pivot": [32, 38]},
	"m_drone": {"fw": 38, "fh": 30, "pivot": [19, 22]},
}
const WRECKS := ["m_hauler", "m_tracked", "m_artillery_node"]


static func build(out: Dictionary) -> void:
	var man: Dictionary = out.manifest.get("vehicles", {})
	var wrecks: Dictionary = out.manifest.get("vehicle_wrecks", {})
	for def in SPEC:
		var sp: Dictionary = SPEC[def]
		var fw: int = sp.fw
		var fh: int = sp.fh
		var o := Vector2(sp.pivot[0], sp.pivot[1])
		var img := Image.create(fw * FRAMES.size(), fh * 8, false, Image.FORMAT_RGBA8)
		var msk := Image.create(fw * FRAMES.size(), fh * 8, false, Image.FORMAT_RGBA8)
		var wimg := Image.create(fw, fh * 8, false, Image.FORMAT_RGBA8)
		for k in 8:
			for f in FRAMES.size():
				var cv = P.Canvas.new(fw, fh)
				draw(cv, def, k * PI / 4.0, f, false, o)
				img.blit_rect(cv.img, Rect2i(0, 0, fw, fh), Vector2i(f * fw, k * fh))
				msk.blit_rect(cv.mask, Rect2i(0, 0, fw, fh), Vector2i(f * fw, k * fh))
			if def in WRECKS:
				var wc = P.Canvas.new(fw, fh)
				draw(wc, def, k * PI / 4.0, 0, true, o)
				wimg.blit_rect(wc.img, Rect2i(0, 0, fw, fh), Vector2i(0, k * fh))
		out.images["units/%s.png" % def] = img
		out.images["units/%s_mask.png" % def] = msk
		man[def] = {"file": "units/%s.png" % def, "mask": "units/%s_mask.png" % def, "fw": fw, "fh": fh,
			"pivot": sp.pivot, "frames": FRAMES, "facings": 8}
		if def in WRECKS:
			out.images["wrecks/%s_wreck.png" % def] = wimg
			wrecks[def] = {"file": "wrecks/%s_wreck.png" % def, "fw": fw, "fh": fh, "pivot": sp.pivot,
				"frames": ["wreck"], "facings": 8}
	# air fields (contract G3a s6/s7; board fact art.air_fields)
	out.images["units/m_drone_shadow.png"] = DR.shadow_image()
	man["m_drone"].merge({"air": true, "altitude": DR.ALTITUDE, "bob": DR.BOB,
		"shadow": {"file": "units/m_drone_shadow.png", "pivot": DR.SHADOW_PIVOT}}, true)
	out.manifest["vehicles"] = man
	out.manifest["vehicle_wrecks"] = wrecks


static func draw(cv, def: String, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	if def == "m_drone":
		DR.draw(cv, rot, f, o)
		return
	var hull: Color = L.DEAD if wreck else L.GRAPH
	var shell: Color = P.mul(L.DEAD, 1.15) if wreck else L.PANEL
	var trk: Color = Color8(36, 32, 30) if wreck else Color8(40, 43, 46)
	var trot := rot + (0.6 if wreck else 0.0)
	var tw: Dictionary = {"m_hauler": [0.46, 0.2, 5.0], "m_tracked": [0.56, 0.245, 6.0], "m_artillery_node": [0.4, 0.23, 5.0]}
	var t: Array = tw[def]
	# shadows
	for s in [-1, 1]:
		P.box_shadow(cv, o, L.w(rot, 0, t[1] * s), t[0], 0.09, t[2], rot)
	match def:
		"m_hauler":
			P.box_shadow(cv, o, L.w(rot, -0.1, 0, 8), 0.3, 0.25, 7.0, rot)
		"m_tracked":
			P.box_shadow(cv, o, Vector3(0, 0, 5), 0.54, 0.32, 11.0, rot)
		"m_artillery_node":
			L.hex_shadow(cv, o, Vector3(0, 0, 4), 0.36, 10.0, rot, 0.8)
	cv.flush_shadow()
	# tracks: far one first, near one after the hull
	var near_s := 1 if L.w(rot, 0, 1).x + L.w(rot, 0, 1).y > 0.0 else -1
	_track(cv, o, rot, t, -near_s, f, trk, wreck)
	match def:
		"m_hauler":
			_track(cv, o, rot, t, near_s, f, trk, wreck)
			_hauler(cv, o, rot, f, hull, shell, wreck)
		"m_tracked":
			_track(cv, o, rot, t, near_s, f, trk, wreck)
			_tracked(cv, o, rot, trot, f, hull, shell, wreck)
		"m_artillery_node":
			_track(cv, o, rot, t, near_s, f, trk, wreck)
			_artillery(cv, o, rot, trot, f, hull, shell, wreck)
	cv.outline(Color(0.07, 0.08, 0.09, 1))


static func _track(cv, o: Vector2, rot: float, t: Array, s: int, f: int, col: Color, wreck: bool) -> void:
	var r: Dictionary = P.box(cv, o, L.w(rot, 0, t[1] * s), t[0], 0.085, t[2], rot, col, 0.08, 131 + s)
	for sd in r.sides:
		if absf((sd.n as Vector2).dot(Vector2(-sin(rot), cos(rot)))) > 0.7:
			D.track_side(cv, sd.quad, 1 if f == 1 else 0, wreck, 5)


static func _hauler(cv, o: Vector2, rot: float, f: int, hull: Color, shell: Color, wreck: bool) -> void:
	var ch: Dictionary = P.box(cv, o, Vector3(0, 0, 4), 0.46, 0.25, 4.0, rot, hull, 0.08, 141)
	for sd in ch.sides:
		L.seam(cv, sd.quad, 0.5, wreck, 0.05, 0.95)
	D.contact_ao(cv, ch)
	var front := cos(rot) + sin(rot) > 0.0
	var head_c := L.w(rot, 0.3, 0, 8)
	var hop_c := L.w(rot, -0.12, 0, 8)
	var parts := [[head_c, "head"], [hop_c, "hopper"]]
	if not front:
		parts.reverse()
	for p in parts:
		if p[1] == "head":
			var hd: Dictionary = L.hexp(cv, o, p[0], 0.15, 5.0, rot, P.mul(hull, 0.85), 143, null, 0.9)
			L.rims(cv, hd, hull)
			if front:
				L.eye(cv, P.proj(o, L.w(rot, 0.43, -0.05, 11)), false, wreck)
				L.eye(cv, P.proj(o, L.w(rot, 0.43, 0.05, 11)), false, wreck)
		else:
			var hp: Dictionary = P.box(cv, o, p[0], 0.29, 0.24, 7.0, rot, shell, 0.07, 145)
			for sd in hp.sides:
				if not wreck:
					L.team_panel(cv, sd.quad, 0.1, 0.25, 0.9, 0.6)
				L.joints(cv, sd.quad, [0.5], shell)
			L.rims(cv, hp, shell)
			var inner := P.sub(hp.top, 0.12, 0.12, 0.88, 0.88)
			cv.poly(inner, Color8(34, 36, 38))
			for i in 9:  # cargo: ore / salvage lumps
				var q := P.sub(inner, P.hn(i, 3, 151) * 0.8 + 0.1, P.hn(i, 4, 151) * 0.8 + 0.1, 0.0, 0.0)
				var cc: Color = [Color8(120, 98, 70), Color8(112, 112, 106), Color8(88, 70, 54)][i % 3]
				cv.rect(int(q[0].x), int(q[0].y), 2, 1, cc if not wreck else P.mul(cc, 0.6))
	if f == 2 and not wreck:  # status beacon blink (no weapon)
		var b := P.proj(o, L.w(rot, -0.36, 0.18, 15))
		L.eye(cv, b, true)


static func _tracked(cv, o: Vector2, rot: float, trot: float, f: int, hull: Color, shell: Color, wreck: bool) -> void:
	var h: Dictionary = P.box(cv, o, Vector3(0, 0, 5), 0.54, 0.32, 6.0, rot, hull, 0.08, 161)
	for sd in h.sides:
		var long := absf((sd.n as Vector2).dot(Vector2(-sin(rot), cos(rot)))) > 0.7
		if long and not wreck:
			L.team_panel(cv, sd.quad, 0.08, 0.15, 0.92, 0.42)
		L.seam(cv, sd.quad, 0.7, wreck, 0.04, 0.96)
		L.joints(cv, sd.quad, [0.35, 0.7] if long else [0.5], hull)
	D.contact_ao(cv, h)
	L.rims(cv, h, hull)
	var deck: Dictionary = P.box(cv, o, L.w(rot, -0.2, 0, 11), 0.26, 0.26, 1.5, rot, P.mul(shell, 0.85), 0.05, 163)
	L.hex_plate(cv, deck.top, 0.3, 0.3, 2.5, L.GRAPH_D, not wreck)
	L.hex_plate(cv, deck.top, 0.3, 0.7, 2.5, L.GRAPH_D, not wreck)
	var toward := cos(trot) + sin(trot) > 0.0
	var tc := L.w(trot, 0.06, 0, 11)
	if not toward:
		_twin(cv, o, trot, f, wreck)
	var t: Dictionary = L.hexp(cv, o, tc, 0.2, 5.0, trot, shell, 165, null, 0.85)
	for sd in t.sides:
		if not wreck:
			L.team_panel(cv, sd.quad, 0.12, 0.35, 0.88, 0.8)
		L.seam(cv, sd.quad, 0.15, wreck)
	if toward:
		L.eye(cv, P.proj(o, L.w(trot, 0.2, -0.1, 14)), true, wreck)
		_twin(cv, o, trot, f, wreck)
	else:
		var a := P.proj(o, L.w(trot, -0.12, 0.08, 16))
		cv.line_v(a, a + Vector2(0, -6), L.JOINT)
		if not wreck:
			cv.px(int(a.x), int(a.y) - 7, L.CYAN)


static func _twin(cv, o: Vector2, trot: float, f: int, wreck: bool) -> void:
	var bl := 0.24 if f != 2 else 0.21
	for s in [-1, 1]:
		P.box(cv, o, L.w(trot, 0.2 + bl, 0.06 * s, 13), bl, 0.02, 1.6, trot, L.DEAD_D if wreck else L.GRAPH_D, 0.04, 167)
	if f == 2 and not wreck:
		for s in [-1, 1]:
			var tip := P.proj(o, L.w(trot, 0.2 + 2 * bl + 0.04, 0.06 * s, 14))
			cv.ellipse(tip.x, tip.y, 1.8, 1.3, Color8(255, 228, 150))
			cv.px(int(tip.x), int(tip.y), Color8(255, 255, 230))


static func _artillery(cv, o: Vector2, rot: float, trot: float, f: int, hull: Color, shell: Color, wreck: bool) -> void:
	var pl: Dictionary = L.hexp(cv, o, Vector3(0, 0, 4), 0.36, 5.0, rot, hull, 171, null, 0.8)
	for sd in pl.sides:
		L.seam(cv, sd.quad, 0.5, wreck)
	L.rims(cv, pl, hull)
	var dk: Dictionary = L.hexp(cv, o, Vector3(0, 0, 9), 0.22, 3.0, trot, shell, 173)
	for sd in dk.sides:
		if not wreck:
			L.team_panel(cv, sd.quad, 0.1, 0.2, 0.9, 0.85)
	# tilted plasma mortar tube
	var rec := 1.5 if f == 2 else 0.0
	var b := L.w(trot, -0.04, 0, 12)
	var m := L.w(trot, 0.2 - rec * 0.01, 0, (20.0 if wreck else 30.0) - rec)
	var pb := P.proj(o, b)
	var pm := P.proj(o, m)
	var col: Color = shell
	for i in 5:
		var off := Vector2(i - 2, 0)
		cv.line_v(pb + off, pm + off, P.mul(col, [1.2, 1.05, 0.95, 0.82, 0.7][i]))
	for i in 3:  # coil rings
		var c := pb.lerp(pm, 0.3 + i * 0.22)
		cv.line(int(c.x) - 2, int(c.y), int(c.x) + 2, int(c.y), L.DEAD_SEAM if wreck else L.CYAN)
	cv.ellipse(pm.x, pm.y, 2.6, 1.3, Color8(26, 28, 30))
	if f == 2 and not wreck:
		cv.ellipse(pm.x, pm.y - 2, 4.0, 3.2, Color(L.CYAN.r, L.CYAN.g, L.CYAN.b, 0.55))
		cv.ellipse(pm.x, pm.y - 2, 2.0, 1.6, L.CYAN_HOT)
	elif not wreck:
		cv.px(int(pm.x), int(pm.y), L.TEAL)
