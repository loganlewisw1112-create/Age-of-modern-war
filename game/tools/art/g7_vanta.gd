extends SceneTree
## G7 AIRV7: CN Vanta rotorless stealth gunship art (docs/G7_REFERENCE.md 13.9c-14 / 13.9c-15). Owner: AIRV7.
## Modelled in real metres on the ONE scale (fact art.scale: 4 m / tile, 9.8 px per metre of height) through the
## DL7-3 faceted mesh renderer (g7_cn_mesh.gd, per-pixel depth), same pipeline and detail bar as the approved
## dropships (g7_cn_air.gd): a 14 m faceted, chined two-seat attack airframe with a stepped tandem canopy, NO rotor:
## two tilting ducted lift / vector fans on the stub-wing tips, a shrouded fantail in the fin, two vectored thrust
## nozzles, retractable tricycle gear, chin sensor ball.
## Hardpoints (13.9c-15): nose (chin, main), the mirrored side pair (under the stub wings: both sides always carry
## the same item) and the rear (under the tail boom). Every combination of the content slots (rules.g7_vanta.slots:
## nose 3 x side 4 x rear 4 = 48) gets its own sheet g7_vanta_<nose>_<side>_<rear> (the sim sets e.art_def to it), so
## each item is visible on its own mount and fires from it (fire frame: muzzle flash / missile plume / laser /
## drone popping out / flares at that mount). Frames: hover, hover_b (fan shimmer), flight, flight_b (fans vectored
## forward, gear up), landed (gear down, on the deck), fire, damaged (smoke, scorched panels). 8 facings in game (the
## renderer's step); a 16-facing sheet of the default loadout (hover / flight) is written too (g7_vanta_16).
## Wreck sheet for cn_vanta_a / cn_vanta_b. Never deletes files it does not own (only its own folder's PNGs).
##   godot --headless --path . -s tools/art/g7_vanta.gd                         # all 48 combos -> assets/art/g7_vanta/
##   godot --headless --path . -s tools/art/g7_vanta.gd -- --combos=default --out=<abs dir>
## Prints "G7_VANTA <id> bytes=<n> budget=<n> ok|OVER" per sheet and a summary line.
const GEN = preload("res://tools/gen_art.gd")
const P = preload("res://tools/art/pix.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")
const M = preload("res://tools/art/g7_cn_mesh.gd")
const A = preload("res://tools/art/g7_cn_air.gd")

const FW := 208
const FH := 144
const PIV := Vector2i(104, 92)
const FRAMES := ["hover", "hover_b", "flight", "flight_b", "landed", "fire", "damaged"]
const ALT := {"hover": 0.7, "hover_b": 0.7, "flight": 0.9, "flight_b": 0.9, "landed": 0.0, "fire": 0.7, "damaged": 0.7}
const SLOTS := {"nose": ["cannon", "missiles", "anti_drone"], "side": ["missiles", "gun", "drones", "anti_drone"],
	"rear": ["flares", "deterrents", "anti_drone", "gun"]}
const DEFAULT := ["cannon", "missiles", "flares"]
## Mounts (metres, f / r / z) - the same numbers as rules.g7_vanta.mounts (sim muzzle points).
const NOSE_M := Vector3(5.6, 0.0, 0.8)
const SIDE_M := Vector3(0.6, 1.75, 1.1)
const REAR_M := Vector3(-6.0, 0.0, 1.35)
const HULL := Color8(86, 94, 106)
const GUNM := Color8(52, 54, 58)
const GLASS := Color8(58, 96, 118)
const TEAMG := Color8(152, 152, 152)
const FLASH := Color8(255, 236, 160)
const FLASH2 := Color8(255, 178, 72)
const SMOKE := Color(0.32, 0.31, 0.30, 0.55)
const LASER := Color(0.55, 0.95, 1.0, 0.85)


static func _secs() -> Array:
	var src := [[6.9, [Vector2(0.05, 1.2), Vector2(0.16, 1.32), Vector2(0.12, 1.5), Vector2(0.03, 1.56)]],
		[5.7, [Vector2(0.42, 0.85), Vector2(0.72, 1.3), Vector2(0.52, 1.9), Vector2(0.2, 2.1)]],
		[4.2, [Vector2(0.6, 0.7), Vector2(1.0, 1.3), Vector2(0.72, 2.25), Vector2(0.3, 2.7)]],
		[2.3, [Vector2(0.7, 0.62), Vector2(1.12, 1.3), Vector2(0.82, 2.5), Vector2(0.34, 3.1)]],
		[0.8, [Vector2(0.9, 0.6), Vector2(1.38, 1.35), Vector2(1.12, 2.45), Vector2(0.6, 2.95)]],
		[-1.8, [Vector2(0.92, 0.7), Vector2(1.4, 1.42), Vector2(1.15, 2.4), Vector2(0.62, 2.8)]],
		[-4.0, [Vector2(0.48, 1.15), Vector2(0.78, 1.55), Vector2(0.6, 2.15), Vector2(0.3, 2.4)]],
		[-6.6, [Vector2(0.26, 1.5), Vector2(0.42, 1.72), Vector2(0.32, 2.0), Vector2(0.15, 2.12)]],
		[-7.2, [Vector2(0.1, 1.65), Vector2(0.18, 1.76), Vector2(0.13, 1.9), Vector2(0.05, 1.95)]]]
	var out: Array = []
	for s in src:
		var h: Array = s[1]
		var ring := PackedVector2Array()
		for i in range(h.size() - 1, -1, -1):
			ring.append(Vector2(-(h[i] as Vector2).x, (h[i] as Vector2).y))
		for q in h:
			ring.append(q)
		out.append([float(s[0]), ring])
	return out


# ------------------------------------------------------------------ airframe
static func airframe(S: Array, T: Dictionary, rp: Array, tilt: float, k: int, fname: String) -> void:
	var gl: Array = C.ramp(GLASS)
	var dk: Array = C.ramp(GUNM)
	var mats := {}
	for sg in [1, 2]:
		for j in [0, 6, 7]:
			mats["%d,%d" % [sg, j]] = gl
	var fus := M.part(S, 1)
	M.loft(fus, T, _secs(), rp, {"mats": mats})
	var line := C.ca(rp[0], 0.6)
	# canopy frames (tandem: front gunner, raised rear pilot), chine and panel lines, intake slits
	M.dline(fus, T, Vector3(4.2, -0.45, 2.3), Vector3(4.2, 0.45, 2.3), line, Vector3(0, 0, 1))
	M.dline(fus, T, Vector3(2.4, -0.5, 2.6), Vector3(2.4, 0.5, 2.6), line, Vector3(0, 0, 1))
	for s in [-1.0, 1.0]:
		var n := Vector3(0, s, 0.3).normalized()
		M.dline(fus, T, Vector3(6.4, s * 0.25, 1.32), Vector3(-6.4, s * 0.36, 1.66), C.ca(rp[4], 0.35), n)
		M.dpoly(fus, T, [Vector3(1.6, s * 0.86, 2.15), Vector3(0.2, s * 0.92, 2.2), Vector3(0.2, s * 1.02, 1.85), Vector3(1.4, s * 0.96, 1.8)],
			Color8(18, 20, 24), n)
		for f in [0.0, -1.2, -2.6]:
			M.dline(fus, T, Vector3(f, s * 1.05, 1.0), Vector3(f - 0.4, s * 1.1, 2.1), line, Vector3(0, s, 0.1))
	M.dpoly(fus, T, [Vector3(-0.6, -0.3, 2.56), Vector3(-0.6, 0.3, 2.56), Vector3(-2.2, 0.3, 2.47), Vector3(-2.2, -0.3, 2.47)],
		TEAMG, Vector3(0, 0, 1), true)
	# chin sensor ball (forward of the nose hardpoint)
	var sb := M.part(S, 1.2)
	M.cyl(sb, T, Vector3(6.25, 0, 1.05), Vector3(0, 0, 1), 0.2, 0.16, 8, dk)
	M.dpx(sb, T, Vector3(6.47, 0, 1.05), Color8(120, 220, 255), Vector3(1, 0, 0))
	for s in [-1.0, 1.0]:
		var w := M.part(S, 1)   # faceted stub wing
		M.prism(w, T, [Vector3(1.6, s * 1.0, 1.82), Vector3(1.1, s * 2.4, 1.74), Vector3(-0.2, s * 2.4, 1.72),
			Vector3(-0.8, s * 1.0, 1.78)], Vector3(0, 0, -0.24), rp)
		M.dpoly(w, T, [Vector3(1.0, s * 1.5, 1.79), Vector3(0.85, s * 2.1, 1.76), Vector3(0.0, s * 2.1, 1.74), Vector3(0.1, s * 1.5, 1.76)],
			TEAMG, Vector3(0, 0, 1), true)
		M.dpx(w, T, Vector3(1.1, s * 2.42, 1.76), Color8(255, 70, 50) if s < 0 else Color8(80, 255, 120))
		A.fan(S, T, Vector3(0.3, s * 3.0, 1.74), 0.74, tilt, rp, true, k, s * 2.35)
		var nz := M.part(S, 1)   # vectored thrust nozzle
		M.box(nz, T, Vector3(-4.3, s * 0.62, 1.6), Vector3(0.45, 0.16, 0.16), dk)
		if fname.begins_with("flight"):
			M.dpx(nz, T, Vector3(-4.78, s * 0.62, 1.6), Color8(255, 170, 90))
			M.dpx(nz, T, Vector3(-4.9, s * 0.62, 1.6), Color8(255, 120, 60))
		var hs := M.part(S, 1.5)   # canted horizontal stabiliser
		M.prism(hs, T, [Vector3(-5.5, s * 0.3, 1.98), Vector3(-6.0, s * 1.45, 2.2), Vector3(-6.6, s * 1.45, 2.2),
			Vector3(-6.5, s * 0.3, 1.98)], Vector3(0, 0, -0.08), rp)
	# fin with the shrouded fantail
	var fn := M.part(S, 2)
	M.prism(fn, T, [Vector3(-5.0, -0.07, 2.05), Vector3(-6.4, -0.07, 3.45), Vector3(-7.25, -0.07, 3.45), Vector3(-7.15, -0.07, 1.85)],
		Vector3(0, 0.14, 0), rp)
	for s in [-1.0, 1.0]:
		var n := Vector3(0, s, 0)
		var c := Vector3(-6.45, s * 0.075, 2.4)
		for i in 12:
			var a := TAU * i / 12.0
			var b := TAU * (i + 1) / 12.0
			M.dline(fn, T, c + Vector3(cos(a) * 0.55, 0, sin(a) * 0.55), c + Vector3(cos(b) * 0.55, 0, sin(b) * 0.55), C.ca(rp[0], 0.85), n)
		for bl in 6:
			var a := k * 0.5 + TAU * bl / 6.0 + (0.3 if fname.ends_with("_b") else 0.0)
			M.dline(fn, T, c, c + Vector3(cos(a) * 0.48, 0, sin(a) * 0.48), C.ca(rp[1], 0.7), n)
		M.dpoly(fn, T, [Vector3(-6.6, s * 0.075, 3.0), Vector3(-7.1, s * 0.075, 3.0), Vector3(-7.15, s * 0.075, 3.35), Vector3(-6.7, s * 0.075, 3.35)],
			TEAMG, n, true)
	M.dpx(fn, T, Vector3(-7.2, 0, 3.47), Color8(255, 255, 255))


static func gear(S: Array, T: Dictionary) -> void:
	var pt := M.part(S, 0.5)
	var dk: Array = C.ramp(Color8(44, 46, 48))
	var tr: Array = C.ramp(Color8(36, 36, 34))
	for g in [Vector3(4.6, 0, 0), Vector3(-0.3, -0.85, 0), Vector3(-0.3, 0.85, 0)]:
		M.box(pt, T, Vector3(g.x, g.y, 0.55), Vector3(0.06, 0.06, 0.25), dk)
		M.cyl(pt, T, Vector3(g.x, g.y, 0.26), Vector3(0, 1, 0), 0.26, 0.09, 8, tr, {"cap_t": 1})


# ------------------------------------------------------------------ hardpoint items (local +x = the mount's arc)
static func _pylon(S: Array, T: Dictionary, rp: Array) -> void:
	var pt := M.part(S, 0.8)
	M.box(pt, T, Vector3(0, 0, 0.12), Vector3(0.42, 0.06, 0.14), rp)


static func _flash(pt: Dictionary, T: Dictionary, at: Vector3, big: float) -> void:
	M.dpx(pt, T, at, Color.WHITE)
	for i in 6:
		var a := TAU * i / 6.0
		M.dpx(pt, T, at + Vector3(cos(a) * 0.2 * big, sin(a) * 0.2 * big, 0.08 * sin(a * 2.0)), FLASH)
		M.dpx(pt, T, at + Vector3(cos(a + 0.5) * 0.36 * big + 0.15, sin(a + 0.5) * 0.3 * big, 0.0), FLASH2)
	M.dline(pt, T, at, at + Vector3(0.6 * big, 0, 0), FLASH)


static func item(S: Array, T: Dictionary, slot: String, it: String, rp: Array, fire: bool) -> void:
	var dk: Array = C.ramp(GUNM)
	var pt := M.part(S, 1.1)
	match it:
		"cannon":
			M.cyl(pt, T, Vector3(0, 0, -0.12), Vector3(0, 0, 1), 0.3, 0.14, 10, dk)
			M.box(pt, T, Vector3(0.22, 0, -0.33), Vector3(0.36, 0.13, 0.11), dk)
			M.cyl(pt, T, Vector3(1.05, 0, -0.35), Vector3(1, 0, 0), 0.05, 0.62, 6, dk, {"edge": false})
			M.box(pt, T, Vector3(1.68, 0, -0.35), Vector3(0.07, 0.07, 0.07), dk)
			if fire:
				_flash(M.part(S, 3), T, Vector3(1.85, 0, -0.35), 1.2)
		"missiles":
			if slot != "nose":
				_pylon(S, T, rp)
			var mp := C.ramp(Color8(196, 198, 184))
			var tubes := [Vector3(0.1, -0.17, -0.18), Vector3(0.1, 0.17, -0.18), Vector3(0.1, -0.17, -0.44), Vector3(0.1, 0.17, -0.44)]
			if slot == "nose":
				tubes = [Vector3(0.2, -0.24, -0.2), Vector3(0.2, 0.24, -0.2)]
			M.box(pt, T, Vector3(0.0, 0, -0.04), Vector3(0.62, 0.3 if slot != "nose" else 0.34, 0.04), dk)
			for i in tubes.size():
				if fire and i == tubes.size() - 1:
					continue   # this one is away
				var c: Vector3 = tubes[i]
				M.cyl(pt, T, c, Vector3(1, 0, 0), 0.12, 0.78, 6, mp)
				M.dpx(pt, T, c + Vector3(0.75, 0, 0), Color8(220, 220, 210))
				M.dline(pt, T, c + Vector3(-0.62, 0, 0.1), c + Vector3(-0.72, 0, 0.16), C.ca(mp[0], 0.8))
			if fire:
				var fx := M.part(S, 3)
				var c: Vector3 = tubes[tubes.size() - 1] + Vector3(2.4, 0, 0.05)
				M.cyl(fx, T, c, Vector3(1, 0, 0), 0.08, 0.45, 6, mp)
				_flash(fx, T, c - Vector3(0.6, 0, 0), 0.8)
				for i in 8:
					M.dpx(fx, T, c - Vector3(0.9 + i * 0.28, 0, -0.02 * i), Color(SMOKE.r, SMOKE.g, SMOKE.b, 0.6 - i * 0.06))
		"gun":
			if slot == "side":
				_pylon(S, T, rp)
				M.box(pt, T, Vector3(0.05, 0, -0.24), Vector3(0.55, 0.15, 0.14), dk)
				M.cyl(pt, T, Vector3(0.85, 0, -0.26), Vector3(1, 0, 0), 0.045, 0.32, 6, dk, {"edge": false})
				if fire:
					_flash(M.part(S, 3), T, Vector3(1.22, 0, -0.26), 1.0)
			else:   # rear remote gun turret (tail stinger)
				M.cyl(pt, T, Vector3(0, 0, -0.1), Vector3(0, 0, 1), 0.22, 0.1, 8, dk)
				M.box(pt, T, Vector3(0.15, 0, -0.26), Vector3(0.26, 0.1, 0.09), dk)
				M.cyl(pt, T, Vector3(0.7, 0, -0.27), Vector3(1, 0, 0), 0.04, 0.34, 6, dk, {"edge": false})
				if fire:
					_flash(M.part(S, 3), T, Vector3(1.08, 0, -0.27), 0.9)
		"anti_drone":
			if slot == "side":
				_pylon(S, T, rp)
			M.box(pt, T, Vector3(0, 0, -0.1), Vector3(0.18, 0.16, 0.08), dk)
			M.box(pt, T, Vector3(0.05, 0, -0.33), Vector3(0.22, 0.18, 0.15), C.ramp(Color8(82, 86, 92)))
			M.dpx(pt, T, Vector3(0.28, -0.06, -0.33), Color8(110, 230, 255), Vector3(1, 0, 0))
			M.dpx(pt, T, Vector3(0.28, 0.07, -0.36), Color8(255, 120, 90), Vector3(1, 0, 0))
			M.box(pt, T, Vector3(-0.22, 0, -0.42), Vector3(0.03, 0.2, 0.14), dk)   # RF defeat panel
			if fire:
				var fx := M.part(S, 3)
				M.dline(fx, T, Vector3(0.3, -0.06, -0.33), Vector3(3.6, -0.06, -0.6), LASER)
				M.dline(fx, T, Vector3(0.3, -0.05, -0.32), Vector3(3.6, -0.05, -0.59), Color(1, 1, 1, 0.7))
				M.dpx(fx, T, Vector3(0.3, -0.06, -0.33), Color.WHITE)
		"drones":
			_pylon(S, T, rp)
			M.box(pt, T, Vector3(0.0, 0, -0.3), Vector3(0.62, 0.3, 0.2), dk)
			for f in [-0.3, 0.3]:
				for i in 8:
					var a := TAU * i / 8.0
					M.dpx(pt, T, Vector3(f + cos(a) * 0.18, sin(a) * 0.18, -0.09), C.ca(dk[3], 0.9), Vector3(0, 0, 1))
			if fire:   # a defence drone popping out of the near cell
				var fx := M.part(S, 3)
				var c := Vector3(0.3, 0, 0.55)
				M.box(fx, T, c, Vector3(0.18, 0.1, 0.05), C.ramp(Color8(58, 62, 64)))
				for a4 in 4:
					var t := PI / 4.0 + a4 * PI / 2.0
					var tip := c + Vector3(cos(t) * 0.36, sin(t) * 0.36, 0.03)
					M.dline(fx, T, c, tip, Color8(34, 36, 38))
					M.dpx(fx, T, tip, Color(0.85, 0.87, 0.85, 0.7))
				M.dpx(fx, T, c + Vector3(0.2, 0, -0.04), Color8(255, 220, 120))
		"flares":
			for s in [-1.0, 1.0]:
				M.box(pt, T, Vector3(0.0, s * 0.3, -0.05), Vector3(0.24, 0.1, 0.16), dk)
				for row in 3:
					for col in 3:
						M.dpx(pt, T, Vector3(0.24, s * (0.24 + col * 0.06), -0.12 + row * 0.07), Color8(26, 26, 28), Vector3(1, 0, 0))
			if fire:
				var fx := M.part(S, 3)
				for i in 6:
					var s := -1.0 if i % 2 == 0 else 1.0
					var c := Vector3(0.8 + i * 0.42, s * (0.5 + i * 0.22), -0.3 - i * 0.18)
					M.dpx(fx, T, c, Color.WHITE)
					M.dpx(fx, T, c + Vector3(0.06, 0, 0), FLASH)
					M.dpx(fx, T, c + Vector3(0, 0.06, 0), FLASH2)
					M.dline(fx, T, Vector3(0.25, s * 0.3, -0.05), c, Color(0.75, 0.74, 0.70, 0.35))
		"deterrents":
			M.cyl(pt, T, Vector3(0, 0, -0.08), Vector3(0, 0, 1), 0.2, 0.08, 8, dk)
			M.cyl(pt, T, Vector3(0.05, 0, -0.28), Vector3(0, 0, 1), 0.16, 0.12, 8, C.ramp(Color8(96, 100, 104)))
			M.dpx(pt, T, Vector3(0.21, 0, -0.28), Color8(255, 60, 50), Vector3(1, 0, 0))
			for s in [-1.0, 1.0]:
				M.box(pt, T, Vector3(-0.1, s * 0.34, -0.06), Vector3(0.2, 0.07, 0.07), dk)
			if fire:
				var fx := M.part(S, 3)
				M.dline(fx, T, Vector3(0.22, 0, -0.28), Vector3(3.8, 0.4, -1.2), Color(1.0, 0.25, 0.2, 0.8))
				for i in 10:
					M.dpx(fx, T, Vector3(0.5 + P.hn(i, 3, 7) * 2.0, (P.hn(i, 5, 9) - 0.5) * 1.6, -0.2 - P.hn(i, 7, 11) * 0.8),
						Color(0.85, 0.88, 0.9, 0.8))


# ------------------------------------------------------------------ one frame
static func craft(cv, k: int, fname: String, o: Vector2, lo: Array, nfac := 8) -> void:
	var a := k * TAU / float(nfac)
	var alt: float = ALT.get(fname, 0.0)
	var flying := fname.begins_with("flight")
	var tilt := PI * 0.32 if flying else 0.0
	var fire := fname == "fire"
	var T := M.pose(o, a, Vector3(0, 0, alt), -0.05 if flying else 0.0)
	var S: Array = []
	var rp: Array = C.ramp(HULL)
	airframe(S, T, rp, tilt, k + (3 if fname.ends_with("_b") else 0), fname)
	if fname == "landed" or fname.begins_with("hover"):
		gear(S, T)
	if String(lo[0]) != "":
		item(S, M.sub(T, NOSE_M), "nose", String(lo[0]), rp, fire)
	if String(lo[1]) != "":
		for s in [-1.0, 1.0]:
			item(S, M.sub(T, Vector3(SIDE_M.x, s * SIDE_M.y, SIDE_M.z)), "side", String(lo[1]), rp, fire)
	if String(lo[2]) != "":
		item(S, M.sub(T, REAR_M, PI), "rear", String(lo[2]), rp, fire)
	if fname == "damaged":
		_damage(S, T, k)
	M.shadow(cv, S, o, 0.34, Vector2(0.25, -0.06))
	M.render_z(cv, S, o, 71 + k)


static func _damage(S: Array, T: Dictionary, k: int) -> void:
	var pt := M.part(S, 3)
	for i in 14:   # scorch on the hull top
		M.dpx(pt, T, Vector3(-1.5 + P.hn(i, k, 3) * 3.0, (P.hn(i, k, 5) - 0.5) * 1.2, 2.55), Color(0.08, 0.07, 0.06, 0.8), Vector3(0, 0, 1))
	for i in 22:   # smoke trailing up and back from the right fan / engine bay
		var t := float(i) / 22.0
		var c := Vector3(-0.8 - t * 3.0, 0.6 + t * 0.6, 2.7 + t * 2.2)
		M.dpx(pt, T, c + Vector3(P.hn(i, k, 7) * 0.3, P.hn(i, k, 9) * 0.3, 0), Color(SMOKE.r, SMOKE.g, SMOKE.b, 0.7 - t * 0.5))
		M.dpx(pt, T, c + Vector3(0.15, -0.12, 0.1), Color(SMOKE.r * 0.8, SMOKE.g * 0.8, SMOKE.b * 0.8, 0.6 - t * 0.45))
	for i in 4:
		M.dpx(pt, T, Vector3(-0.7 + i * 0.1, 0.62, 2.55 + i * 0.06), FLASH2 if i % 2 == 0 else FLASH)


## Wreck: the airframe down on its belly, broken behind the cockpit, fans torn off, burnt.
static func wreck(cv, k: int, o: Vector2) -> void:
	var a := k * PI / 4.0
	var S: Array = []
	var rp: Array = C.ramp(Color8(44, 42, 40))
	var T := M.pose(o, a, Vector3(0, 0, -0.65), 0.0, 0.12)
	var fus := M.part(S, 1)
	var secs := _secs()
	M.loft(fus, T, secs.slice(0, 6), rp)
	var T2 := M.pose(o, a + 0.35, Vector3(-0.6, -0.4, -0.75), 0.06, -0.1)
	M.loft(M.part(S, 1), T2, secs.slice(5, 9), rp)
	for i in 30:
		M.dpx(fus, T, Vector3(4.0 - P.hn(i, k, 3) * 6.0, (P.hn(i, k, 5) - 0.5) * 1.4, 2.3), Color(0.05, 0.05, 0.05, 0.85), Vector3(0, 0, 1))
	var dk: Array = C.ramp(Color8(38, 38, 38))
	var fp := M.part(S, 0.5)
	M.cyl(fp, M.pose(o, a), Vector3(1.0, 3.6, 0.15), Vector3(0.3, 0.2, 1).normalized(), 0.62, 0.14, 12, dk)
	M.cyl(fp, M.pose(o, a), Vector3(-1.4, -3.1, 0.12), Vector3(-0.2, 0.3, 1).normalized(), 0.62, 0.14, 12, dk)
	var sm := M.part(S, 3)
	for i in 18:
		var t := float(i) / 18.0
		M.dpx(sm, M.pose(o, 0.0), Vector3(-0.4 - t * 1.4, 0.2 + t * 0.8, 2.0 + t * 4.0), Color(SMOKE.r, SMOKE.g, SMOKE.b, 0.65 - t * 0.5))
	M.shadow(cv, S, o, 0.3, Vector2(0.2, -0.05))
	M.render_z(cv, S, o, 91 + k)


# ------------------------------------------------------------------ sheets
static func sheet(out: Dictionary, id: String, nfac: int, frames: Array, lo: Array, extra: Dictionary, with_wreck := false) -> void:
	var img := Image.create(FW * frames.size(), FH * nfac, false, Image.FORMAT_RGBA8)
	var msk := Image.create(FW * frames.size(), FH * nfac, false, Image.FORMAT_RGBA8)
	var o := Vector2(PIV)
	for k in nfac:
		for i in frames.size():
			var cv = P.Canvas.new(FW, FH)
			craft(cv, k, String(frames[i]), o, lo, nfac)
			C.selout(cv)
			img.blit_rect(cv.img, Rect2i(0, 0, FW, FH), Vector2i(i * FW, k * FH))
			msk.blit_rect(cv.mask, Rect2i(0, 0, FW, FH), Vector2i(i * FW, k * FH))
	out.images["units/%s.png" % id] = img
	out.images["units/%s_mask.png" % id] = msk
	var man: Dictionary = out.manifest.get("vehicles", {})
	var g7 := {"detail_level": C.VERSION, "class": "air", "bytes": C.packed_bytes(img, FW, FH, -1) if nfac == 8 else img.get_width() * img.get_height() * 4,
		"raw_bytes": img.get_width() * img.get_height() * 4, "budget": int(C.BUDGET.air), "mirror": -1}
	g7.merge(extra)
	man[id] = {"file": "units/%s.png" % id, "mask": "units/%s_mask.png" % id, "fw": FW, "fh": FH, "pivot": [PIV.x, PIV.y],
		"frames": frames.duplicate(), "facings": nfac, "g7": g7, "altitude": 150.0, "bob": 1.0,
		"anim": {"air": ["hover", "hover_b"], "move": ["flight", "flight_b"]}, "anim_fps": 6}
	out.manifest["vehicles"] = man
	var sp: Dictionary = out.manifest.get("specials", {})
	sp[id] = {"parked": "landed"}
	out.manifest["specials"] = sp
	if nfac == 8:
		C.icon(out, id, img, FW, FH, 1)
	if with_wreck:
		var wi := Image.create(FW, FH * 8, false, Image.FORMAT_RGBA8)
		for k in 8:
			var cw = P.Canvas.new(FW, FH)
			wreck(cw, k, o)
			C.selout(cw)
			wi.blit_rect(cw.img, Rect2i(0, 0, FW, FH), Vector2i(0, k * FH))
		out.images["wrecks/%s_wreck.png" % id] = wi


static func combos(which: String) -> Array:
	if which == "default":
		return [DEFAULT]
	var r: Array = []
	for n in SLOTS.nose:
		for s in SLOTS.side:
			for q in SLOTS.rear:
				r.append([n, s, q])
	return r


static func generate(which: String) -> Dictionary:
	var out := {"images": {}, "manifest": {"version": 1, "tile": [64, 32], "group": "g7_vanta", "g7_detail_level": C.DL.duplicate(true)}}
	var fx := {"sample": "air", "line": "counter_nanite", "size_m": [14.0, 6.7, 3.5], "scale": "4 m/tile, 9.8 px/m (fact art.scale)",
		"mounts_m": {"nose": [NOSE_M.x, NOSE_M.y, NOSE_M.z], "side": [SIDE_M.x, SIDE_M.y, SIDE_M.z], "rear": [REAR_M.x, REAR_M.y, REAR_M.z]},
		"altitude_m": ALT, "deck_note": "drawn on the barracks roof deck at render alt 0.76 (114 of 150 px)"}
	for lo in combos(which):
		var id := "g7_vanta_%s_%s_%s" % lo
		sheet(out, id, 8, FRAMES, lo, fx.merged({"loadout": {"nose": lo[0], "side": lo[1], "rear": lo[2]}}))
	var did := "g7_vanta_%s_%s_%s" % DEFAULT
	sheet(out, "g7_vanta_16", 16, ["hover", "flight", "landed"], DEFAULT, fx.merged({"note": "16-facing showcase of the default loadout (the renderer draws 8 facings today)"}))
	var wid := "g7_vanta_bare"
	sheet(out, wid, 8, ["hover", "landed"], ["", "", ""], fx.merged({"note": "bare airframe (no hardpoint items): reference"}), true)
	var man: Dictionary = out.manifest.vehicles
	var vw := {}
	for cid in ["cn_vanta_a", "cn_vanta_b"]:   # content defs draw the default loadout until e.art_def is set
		var e: Dictionary = (man[did] as Dictionary).duplicate(true)
		man[cid] = e
		out.manifest.specials[cid] = {"parked": "landed"}
		vw[cid] = {"file": "wrecks/%s_wreck.png" % wid, "fw": FW, "fh": FH, "pivot": [PIV.x, PIV.y], "frames": ["wreck"], "facings": 8}
	out.manifest["vehicle_wrecks"] = vw
	return out


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var which := "all"
	var out_dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--combos="):
			which = a.substr(9)
		elif a.begins_with("--out="):
			out_dir = a.substr(6)
	var r := generate(which)
	var dir := "res://assets/art/g7_vanta/" if out_dir == "" else out_dir.path_join("g7_vanta") + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	for sub in ["units", "wrecks", "icons"]:   # only this generator's own folder
		var d := DirAccess.open(ProjectSettings.globalize_path(dir).path_join(sub))
		if d != null:
			for f in d.get_files():
				if f.ends_with(".png") and (f.begins_with("g7_vanta") or f.begins_with("cn_vanta")):
					d.remove(f)
	var files: int = GEN.save(r, dir)
	var over := 0
	var ids: Array = (r.