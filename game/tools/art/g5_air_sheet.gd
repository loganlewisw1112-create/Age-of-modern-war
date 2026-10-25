extends RefCounted
## G5 aircraft sheets (agent ART-AIR). One `vehicles` entry per aircraft (g4_units_lib.sheet layout: rows =
## 8 facings, columns = named frames, `_mask.png` team twin, 1-column wreck sheet) plus air keys:
##   air: true, altitude (px lift when airborne), bob (px), aircraft (heli | lift | jet | vtol | micro)
##   shadow        {file, fw, fh, pivot}: soft blob for renderers that draw one shadow (m_drone schema)
##   shadow_sheet  {file, fw, fh, pivot, facings: 8}: the aircraft's own top-down silhouette per facing,
##                 drawn at the ground point under an airborne aircraft
##   ground_frames frames that sit ON the ground (lift 0, contact shadow already drawn in the frame)
##   alt_scale     {frame: 0..1} fraction of `altitude` for low frames (approach / hover)
##   anim          {state: [frame, frame]} 2-frame loops (rotor blur phase, afterburner flicker), anim_fps
##   sling         lifters: {frame, hook_frame, hook_dz, load_dy}; "sling" draws cables + a generic load,
##                 "sling_hook" only the taut cables + hook (renderer draws the real vehicle load_dy px
##                 below the aircraft's pivot)
## Pivot = the ground point under the aircraft's centre (landed: where its gear stands).
const P = preload("res://tools/art/pix.gd")
const L = preload("res://tools/art/g4_units_lib.gd")
const MS = preload("res://tools/art/g5_air_mesh.gd")
const R = preload("res://tools/art/g5_air_raster.gd")

const VEH := ["idle", "move", "fire"]
const FRAMES := {
	"heli": ["idle", "move", "fire", "idle_b", "move_b", "landed", "parked"],
	"lift": ["idle", "move", "fire", "idle_b", "move_b", "landed", "parked", "sling", "sling_b", "sling_hook", "unload"],
	"jet": ["idle", "move", "fire", "idle_b", "move_b", "taxi", "roll", "landing", "parked"],
	"vtol": ["idle", "move", "fire", "idle_b", "move_b", "hover", "hover_b", "landing", "landed", "parked", "unload",
		"sling", "sling_b", "sling_hook"],
	"micro": ["idle", "move", "fire", "idle_b", "move_b", "landed"],
}
const GROUND := ["landed", "parked", "taxi", "roll", "unload"]
const ALT := {"heli": 20, "lift": 22, "jet": 34, "vtol": 24, "micro": 12}
const BOB := {"heli": 2, "lift": 2, "jet": 1, "vtol": 2, "micro": 1}
const SLING_DY := 14


## Frame name -> draw state for an aircraft class.
static func state(cls: String, fname: String) -> Dictionary:
	var st := {"f": fname, "gear": false, "ph": 0.0, "spin": "spin", "fire": false, "open": false, "tilt": 0.0,
		"sling": 0, "ab": 1.0, "pitch": 0.0, "flaps": false, "canopy": false, "ground": false, "wreck": false}
	var rotor := cls != "jet"
	match fname:
		"idle_b":
			st.ph = 1.0
			st.ab = 1.35
		"move":
			st.ph = 0.5
			st.ab = 2.0
			st.pitch = 0.14 if rotor else 0.0
		"move_b":
			st.ph = 1.5
			st.ab = 2.5
			st.pitch = 0.14 if rotor else 0.0
		"fire":
			st.fire = true
			st.ph = 0.25
			st.pitch = 0.06 if rotor else 0.0
		"landed":
			st.ground = true
			st.gear = true
			st.spin = "slow"
			st.ab = 0.0
		"parked":
			st.ground = true
			st.gear = true
			st.spin = "stop"
			st.canopy = true
			st.ab = -1.0
		"taxi":
			st.ground = true
			st.gear = true
			st.ab = 0.0
		"roll":
			st.ground = true
			st.gear = true
			st.ab = 2.4
		"landing":
			st.gear = true
			st.flaps = true
			st.ab = 0.0
			st.pitch = -0.1 if cls == "jet" else 0.0
		"hover":
			st.gear = true
		"hover_b":
			st.gear = true
			st.ph = 1.0
		"sling":
			st.sling = 1
		"sling_b":
			st.sling = 1
			st.ph = 1.0
		"sling_hook":
			st.sling = 2
			st.ph = 0.5
		"unload":
			st.ground = true
			st.gear = true
			st.open = true
			st.spin = "slow"
			st.ab = 0.0
	if cls == "vtol" and fname in ["hover", "hover_b", "landing", "landed", "parked", "unload", "sling", "sling_b", "sling_hook"]:
		st.tilt = 1.0
		st.gear = true
	if rotor and cls != "vtol":
		st.gear = true  # skids / fixed wheels
	return st


## Blade angle for a rotor with `blades` blades in state st.
static func blade_ph(st: Dictionary, blades: int, base := 0.6) -> float:
	return base + float(st.ph) * PI / float(blades)


## Build one aircraft. model: Callable(m: Mesh, st: Dictionary). look: {style, pal, zc (pitch pivot height)}.
static func sheet(out: Dictionary, def: String, cls: String, model: Callable, look: Dictionary, extra := {}) -> void:
	var frames: Array = FRAMES[cls]
	var sp := fit(model, look, cls)
	var draw := func(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
		if wreck:
			_wreck(cv, o, rot, model, look, cls)
		else:
			_frame(cv, o, rot, model, look, state(cls, String(frames[f])), def, String(frames[f]), out)
	var ex := {"air": true, "altitude": ALT[cls], "bob": BOB[cls], "aircraft": cls, "anim_fps": 10}
	var gf: Array = []
	for fr: String in frames:
		if GROUND.has(fr):
			gf.append(fr)
	ex["ground_frames"] = gf
	var anim := {"air": ["idle", "idle_b"], "move": ["move", "move_b"]}
	if frames.has("hover"):
		anim["hover"] = ["hover", "hover_b"]
	if frames.has("sling"):
		anim["sling"] = ["sling", "sling_b"]
		ex["sling"] = {"frame": "sling", "hook_frame": "sling_hook", "hook_dz": int(look.get("belly", 6)), "load_dy": SLING_DY}
	ex["anim"] = anim
	var alt_scale := {}
	if frames.has("landing"):
		alt_scale["landing"] = 0.35
	if frames.has("hover"):
		alt_scale["hover"] = 0.6
		alt_scale["hover_b"] = 0.6
	ex["alt_scale"] = alt_scale
	ex["shadow"] = _blob(out, def, float(look.get("shadow_r", 8.0)))
	ex["shadow_sheet"] = _shadow_sheet(out, def, sp, model, cls)
	ex.merge(extra, true)
	L.sheet(out, def, sp, draw, frames, "vehicles", true, ex)


static func _mesh(model: Callable, st: Dictionary, look: Dictionary):
	var m = MS.AMesh.new()
	var zc: float = look.get("zc", 8.0)
	var pitch: float = st.pitch
	if absf(pitch) > 0.0001:
		m.xf = Transform3D(Basis.IDENTITY, Vector3(0, 0, zc)) * Transform3D(Basis(Vector3(0, 1, 0), pitch), Vector3.ZERO) \
			* Transform3D(Basis.IDENTITY, Vector3(0, 0, -zc))
	model.call(m, st)
	return m


static func _frame(cv, o: Vector2, rot: float, model: Callable, look: Dictionary, st: Dictionary, def: String,
		fname: String, out: Dictionary) -> void:
	var m = _mesh(model, st, look)
	R.render(cv, o, rot, m, {"style": look.style, "pal": look.pal, "ground": st.ground, "seed": int(rot * 100.0)})
	for x in cv.w:
		for y in [0, cv.h - 1]:
			if cv.img.get_pixel(x, y).a > 0.6:
				_warn(out, "%s %s clipped at the frame edge" % [def, fname])
				return
	for y in cv.h:
		for x in [0, cv.w - 1]:
			if cv.img.get_pixel(x, y).a > 0.6:
				_warn(out, "%s %s clipped at the frame edge" % [def, fname])
				return


static func _warn(out: Dictionary, s: String) -> void:
	var w: Array = out.get("warnings", [])
	if not w.has(s):
		w.append(s)
	out["warnings"] = w


## Crashed airframe: tail broken off and slewed, hull rolled onto its side and crushed, scorch, debris,
## smoke and embers. Colours charred toward soot.
static func _wreck(cv, o: Vector2, rot: float, model: Callable, look: Dictionary, cls: String) -> void:
	var st := state(cls, "parked")
	st.wreck = true
	var m = _mesh(model, st, look)
	var bx: float = look.get("break_x", -10.0)
	var roll := Basis(Vector3(1, 0, 0), 0.32)
	var yaw := Basis(Vector3(0, 0, 1), 0.55)
	for t: Array in m.tris:
		for k in 3:
			t[k] = _crash(t[k], bx, roll, yaw)
	var mains: Array = []
	for d: Dictionary in m.discs:
		if float(d.r) > 8.0:
			mains.append(d)
	m.discs = []
	m.marks = []
	m.lines = []
	var pal := {}
	for key in look.pal:
		pal[key] = P.mix(look.pal[key], Color8(34, 31, 28), 0.72)
	pal["cyan"] = Color8(40, 70, 76)
	var g := Color8(38, 33, 28)
	cv.ellipse(o.x, o.y, float(look.get("shadow_r", 8.0)) * 1.6, float(look.get("shadow_r", 8.0)) * 0.75,
		Color(g.r, g.g, g.b, 0.7))
	for d: Dictionary in mains:  # snapped blades thrown on the ground
		var c: Vector3 = d.c
		var r: float = d.r
		for i in 3:
			var a := 0.9 + i * 2.1
			var p0 := Vector3(c.x + cos(a) * 3.0, c.y + sin(a) * 3.0, 0.5)
			var p1 := Vector3(c.x + cos(a + 0.35) * r * 0.8, c.y + sin(a + 0.35) * r * 0.8, 0.5)
			m.line(p0, p1, "rotor", true)
	pal["rotor"] = Color8(30, 28, 26)
	m.mark(Vector3(2, 0, float(look.get("zc", 8.0)) + 2.0), "smoke")
	m.mark(Vector3(-4, 3, 3), "fire", Vector3(1, 0, 0), 0.8)
	m.mark(Vector3(bx, -2, 2), "fire", Vector3(1, 0, 0), 0.5)
	R.render(cv, o, rot, m, {"style": look.style, "pal": pal, "ground": true, "seed": int(rot * 100.0) + 5})


static func _crash(v: Vector3, bx: float, roll: Basis, yaw: Basis) -> Vector3:
	if v.x < bx:
		var rel := v - Vector3(bx, 0, 0)
		rel = yaw * rel
		v = Vector3(bx - 2.0, 3.0, 0) + Vector3(rel.x, rel.y, rel.z * 0.7)
	v = roll * v
	return Vector3(v.x, v.y, maxf(0.0, v.z * 0.65 - 1.0))


## Soft blob (single image) for the m_drone shadow schema.
static func _blob(out: Dictionary, def: String, r: float) -> Dictionary:
	var rx := r * 1.4
	var ry := r * 0.7
	var w := int(ceil(rx * 2.0)) + 2
	var h := int(ceil(ry * 2.0)) + 2
	var cv = P.Canvas.new(w, h)
	cv.ellipse(w / 2.0, h / 2.0, rx, ry, Color.BLACK, true)
	cv.flush_shadow(Color(0.04, 0.05, 0.03, 0.36))
	var rel := "units/%s_shadow.png" % def
	out.images[rel] = cv.img
	return {"file": rel, "fw": w, "fh": h, "pivot": [w / 2, h / 2]}


## Per-facing top-down silhouette of the cruise pose (1 column x 8 rows, same frame size / pivot).
static func _shadow_sheet(out: Dictionary, def: String, sp: Dictionary, model: Callable, cls: String) -> Dictionary:
	var fw: int = sp.fw
	var fh: int = sp.fh
	var o := Vector2(sp.pivot[0], sp.pivot[1])
	var img := Image.create(fw, fh * 8, false, Image.FORMAT_RGBA8)
	var st := state(cls, "idle")
	for k in 8:
		var cv = P.Canvas.new(fw, fh)
		var m = MS.AMesh.new()
		model.call(m, st)
		R.footprint(cv, o, k * PI / 4.0, m, false)
		cv.flush_shadow(Color(0.04, 0.05, 0.03, 0.36))
		img.blit_rect(cv.img, Rect2i(0, 0, fw, fh), Vector2i(0, k * fh))
	var rel := "units/%s_shadow8.png" % def
	out.images[rel] = img
	return {"file": rel, "fw": fw, "fh": fh, "pivot": sp.pivot.duplicate(), "facings": 8}


## Frame size + pivot that hold every frame, facing, contact shadow, effect and the wreck (3 px margin).
static func fit(model: Callable, look: Dictionary, cls: String) -> Dictionary:
	var box := Rect2(Vector2.ZERO, Vector2.ZERO)
	var o := Vector2.ZERO
	var sr: float = look.get("shadow_r", 8.0)
	box = box.expand(Vector2(-sr * 1.7, -sr * 0.8)).expand(Vector2(sr * 1.7, sr * 0.8))
	for fname: String in FRAMES[cls]:
		var st := state(cls, fname)
		var m = _mesh(model, st, look)
		for k in 8:
			var rot := k * PI / 4.0
			var ca := cos(rot)
			var sa := sin(rot)
			for t: Array in m.tris:
				for v in 3:
					var w := MS.to_w(t[v], ca, sa)
					box = box.expand(MS.scr(o, w))
					if st.ground:
						var off := Vector2(0.9, 0.35) * (w.z / 32.0)
						box = box.expand(P.proj(o, Vector3(w.x + off.x, w.y + off.y, 0.0)))
			for ln: Array in m.lines:
				box = box.expand(MS.sp(o, rot, ln[0])).expand(MS.sp(o, rot, ln[1]))
			for d: Dictionary in m.discs:
				var n: Vector3 = d.n
				var up := Vector3(0, 0, 1) if absf(n.z) < 0.9 else Vector3(1, 0, 0)
				var u := n.cross(up).normalized()
				var vv := n.cross(u).normalized()
				for i in 16:
					var a := float(i) * TAU / 16.0
					box = box.expand(MS.sp(o, rot, d.c + (u * cos(a) + vv * sin(a)) * float(d.r)))
			for mk: Dictionary in m.marks:
				var s := MS.sp(o, rot, mk.p)
				var e := MS.sp(o, rot, mk.p + (mk.dir as Vector3).normalized() * 8.0)
				var dv := (e - s).normalized() if (e - s).length() > 0.1 else Vector2(0, 1)
				var ln: float = {"exhaust": 4.0 + 5.0 * float(mk.s), "plasma": 3.0 + 5.0 * float(mk.s), "tracer": 10.0, "bolt": 9.0, "rocket": 8.0,
					"missile": 9.0}.get(String(mk.kind), 0.0)
				box = box.expand(s + dv * float(ln) + Vector2(3, 3)).expand(s + dv * float(ln) - Vector2(3, 3))
				box = box.expand(s - dv * 8.0 if String(mk.kind) == "missile" else s).expand(s + Vector2(3, 7)).expand(s - Vector2(3, 10))
	var fw := int(ceil(box.size.x)) + 6
	var fh := int(ceil(box.size.y)) + 6
	var px := int(ceil(-box.position.x)) + 3 + maxi(0, 24 - fw) / 2
	var py := int(ceil(-box.position.y)) + 3 + maxi(0, 24 - fh) / 2
	return {"fw": maxi(fw, 24), "fh": maxi(fh, 24), "pivot": [px, py]}
