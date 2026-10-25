extends RefCounted
## G5 aircraft art (agent ART-AIR): shared aircraft parts built on g5_air_mesh (model space: x nose,
## y right, z up; lu / px) and the three faction palettes.
##   Human A "modern"      light blue-grey composite skin, faint panel lines, dark glass, team fin / band
##   Human B "industrial"  olive drab over pale-blue belly, heavy seams, rivet rows, rust, boxy sections
##   Machine               graphite with cyan seams and cyan sensor glass, ducted fans
const MS = preload("res://tools/art/g5_air_mesh.gd")
const SH = preload("res://tools/art/g5_air_sheet.gd")

const PAL_A := {
	"body": Color8(150, 158, 163), "body2": Color8(120, 128, 134), "under": Color8(172, 178, 180),
	"dark": Color8(58, 62, 66), "glass": Color8(38, 62, 80), "metal": Color8(98, 102, 106),
	"team": Color8(200, 200, 200), "rotor": Color8(34, 36, 38), "engine": Color8(70, 72, 74),
	"cargo": Color8(112, 116, 90), "lamp": Color8(255, 240, 200), "glow": Color8(255, 170, 70),
	"cable": Color8(30, 30, 30), "tyre": Color8(30, 30, 32), "ord": Color8(214, 214, 206),
}
const PAL_B := {
	"body": Color8(100, 106, 72), "body2": Color8(80, 84, 58), "under": Color8(128, 140, 140),
	"dark": Color8(48, 46, 38), "glass": Color8(56, 78, 72), "metal": Color8(90, 86, 74),
	"team": Color8(200, 200, 200), "rotor": Color8(36, 34, 30), "engine": Color8(62, 60, 50),
	"cargo": Color8(110, 94, 64), "lamp": Color8(255, 220, 150), "glow": Color8(255, 150, 60),
	"cable": Color8(34, 30, 26), "tyre": Color8(30, 28, 26), "ord": Color8(96, 104, 70),
}
const PAL_M := {
	"body": Color8(60, 64, 70), "body2": Color8(44, 47, 52), "under": Color8(72, 76, 82),
	"dark": Color8(26, 28, 32), "glass": Color8(30, 120, 132), "metal": Color8(86, 92, 98),
	"team": Color8(200, 200, 200), "rotor": Color8(30, 32, 36), "engine": Color8(40, 44, 48),
	"cargo": Color8(66, 70, 76), "lamp": Color8(150, 250, 255), "glow": Color8(90, 235, 255),
	"cyan": Color8(80, 230, 240), "cable": Color8(24, 26, 30), "tyre": Color8(22, 24, 26), "ord": Color8(70, 76, 84),
}


## Run f with m.xf temporarily composed with t (sub-assembly transforms: tilting nacelles, open ramps).
static func with(m, t: Transform3D, f: Callable) -> void:
	var old: Transform3D = m.xf
	m.xf = old * t
	f.call()
	m.xf = old


static func at(p: Vector3, b := Basis.IDENTITY) -> Transform3D:
	return Transform3D(b, p)


## Main rotor: mast + hub + disc (normal up). blades, radius r.
static func main_rotor(m, st: Dictionary, hub: Vector3, r: float, blades: int, mast := 3.0, base := 0.6) -> void:
	MS.cyl(m, hub - Vector3(0, 0, mast), hub, 1.0, "metal", 0.8, 5)
	MS.box(m, hub + Vector3(0, 0, 0.5), Vector3(1.4, 1.4, 0.7), "dark")
	m.disc(hub + Vector3(0, 0, 1.2), Vector3(0, 0, 1), r, blades, SH.blade_ph(st, blades, base), st.spin)


## Tail rotor in the vertical x-z plane at hub (normal y).
static func tail_rotor(m, st: Dictionary, hub: Vector3, r: float, blades := 4) -> void:
	MS.box(m, hub, Vector3(0.8, 0.6, 0.8), "dark")
	m.disc(hub, Vector3(0, 1, 0), r, blades, SH.blade_ph(st, blades, 0.2) * 1.7, st.spin)


## Helicopter skids: two rails at +-y from x0 to x1 on the ground, struts up to the belly at zb.
static func skids(m, x0: float, x1: float, y: float, zb: float, mat := "metal") -> void:
	for s: float in [-1.0, 1.0]:
		MS.box(m, Vector3((x0 + x1) * 0.5, y * s, 0.6), Vector3((x1 - x0) * 0.5, 0.5, 0.5), mat)
		m.line(Vector3(x0 + 2.0, y * s, 0.8), Vector3(x0 + 3.0, y * s * 0.6, zb), mat)
		m.line(Vector3(x1 - 2.5, y * s, 0.8), Vector3(x1 - 3.0, y * s * 0.6, zb), mat)


## Wheel (short dark cylinder on a y axle) whose bottom touches z = 0; strut up to zt.
static func wheel(m, x: float, y: float, r: float, zt: float, mat := "metal") -> void:
	MS.cyl(m, Vector3(x, y - 0.6, r), Vector3(x, y + 0.6, r), r, "tyre", -1.0, 6)
	m.line(Vector3(x, y, r), Vector3(x, y, zt), mat)


## Retractable tricycle gear (jets / VTOLs): only drawn when st.gear.
static func gear(m, st: Dictionary, nose_x: float, main_x: float, main_y: float, zt: float, r := 1.3) -> void:
	if not bool(st.gear):
		return
	wheel(m, nose_x, 0.0, r * 0.85, zt)
	for s: float in [-1.0, 1.0]:
		wheel(m, main_x, main_y * s, r, zt)
		MS.slab(m, [Vector2(main_x + 2.0, main_y * s * 0.7), Vector2(main_x + 2.0, main_y * s * 0.95),
			Vector2(main_x - 1.0, main_y * s * 0.95), Vector2(main_x - 1.0, main_y * s * 0.7)], zt - 1.0, 0.5, "dark")


## Rocket pod (front face dark tubes) along +x centred at p.
static func rocket_pod(m, p: Vector3, ln: float, r: float, mat := "body2") -> void:
	MS.cyl(m, p - Vector3(ln * 0.5, 0, 0), p + Vector3(ln * 0.5, 0, 0), r, mat, r * 0.9, 6)
	MS.box(m, p + Vector3(ln * 0.5 + 0.3, 0, 0), Vector3(0.3, r * 0.6, r * 0.6), "dark")


## Air-to-air missile / bomb body along +x at p.
static func missile(m, p: Vector3, ln: float, r := 0.6, mat := "ord") -> void:
	MS.cyl(m, p - Vector3(ln * 0.5, 0, 0), p + Vector3(ln * 0.4, 0, 0), r, mat, -1.0, 4)
	MS.cyl(m, p + Vector3(ln * 0.4, 0, 0), p + Vector3(ln * 0.5 + 0.8, 0, 0), r, "dark", 0.1, 4)


## Sling load under a lifter: st.sling 1 = cables + a generic slung load (net-wrapped crate / light
## vehicle shape), 2 = taut cables + hook only (the renderer hangs the real vehicle under it).
static func sling(m, st: Dictionary, belly: float, w := 3.0) -> void:
	if int(st.sling) == 0:
		return
	var hook := Vector3(0, 0, belly - 1.0)
	m.line(Vector3(0, 0, belly), hook, "cable", true)
	var top := belly - float(SH.SLING_DY)
	if int(st.sling) == 2:
		for c in [Vector3(4, 3, top), Vector3(-4, 3, top), Vector3(4, -3, top), Vector3(-4, -3, top)]:
			m.line(hook, c, "cable", true)
		MS.box(m, Vector3(0, 0, top + 0.6), Vector3(0.8, 0.8, 0.6), "dark")
		return
	MS.box(m, Vector3(0, 0, top - 3.0), Vector3(6.5, w, 3.0), "cargo")
	MS.box(m, Vector3(0, 0, top - 0.2), Vector3(6.6, w + 0.1, 0.3), "team")
	for c in [Vector3(6, w, top), Vector3(-6, w, top), Vector3(6, -w, top), Vector3(-6, -w, top)]:
		m.line(hook, c, "cable", true)


## Navigation lights: red port (-y) / green starboard (+y) wingtips, optional white tail.
static func nav(m, x: float, y: float, z: float) -> void:
	m.mark(Vector3(x, -y, z), "navr")
	m.mark(Vector3(x, y, z), "navg")


## Rear ramp hinged at h (extends toward -x): closed tilts up under the tail, open drops to the ground
## and shows the dark cabin.
static func ramp(m, st: Dictionary, h: Vector3, ln: float, hw: float) -> void:
	var a := asin(clampf(-h.z / ln, -1.0, 1.0)) if st.open else 0.38
	with(m, at(h, Basis(Vector3(0, 1, 0), a)), func() -> void:
		MS.box(m, Vector3(-ln * 0.5, 0, 0), Vector3(ln * 0.5, hw, 0.4), "body2"))
	if st.open:
		MS.box(m, Vector3(h.x - 0.4, 0, h.z + 3.5), Vector3(0.5, hw - 0.4, 3.2), "dark")
