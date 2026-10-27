extends RefCounted
## DL7-3 sample dropships (owner: ARTCN7; rev3 = owner rev2 decision: "make it feel like a true vtol", G7_REFERENCE
## 6.9 incl. the C-17-style loading line). Modelled in real metres on the ONE scale (fact art.scale) through
## g7_cn_mesh.gd:
##   g7_cn_stealth_dropship  19.6 m faceted, chined stealth fuselage with a sharp nose and wrap canopy, swept
##                           blended wings, a V-tail, flush dorsal intakes, and FOUR tilting ducted lift fans
##                           (two on canard stubs, two at the wingtips) that swivel from vertical (hover / landing)
##                           through 45 deg (transition) to horizontal thrust (flight). Retractable gear.
##   g7_a_vtol_dropship_xl   the regular Human A heavy VTOL: rounded fuselage with a big glazed nose, cabin windows,
##                           a high straight wing with two tilting proprotor nacelles, gear sponsons and a T-tail.
## Both: a 10 m x 4.2 m cargo bay (deck 1.3 m) behind a C-17-style rear door: the fuselage ends in a tall rear
## aperture under an upswept tail boom, closed in flight, open with the ramp lowered to the ground.
## rev4 (ARTCN7-5, owner rev3 notes): no see-through cutaway. Loading is shown only through the open rear door: a lit
## bay, the strike APC (g7_cn_vehicles model, 8 m) driving up the ramp and in, soldiers walking up in a file and in.
## Every frame is drawn with real per-pixel depth (M.render_z): any part of a vehicle or soldier behind the hull, a
## wing, a fan, a nacelle or the door frame is hidden, in all 8 facings. Load sequences live on their own sheets
## (<id>_apcload: apc_load_0..5; <id>_squadload: squad_load_0..3; <id>_squadunload: squad_unload_0..3), see build().
## Each sheet fits one atlas page (<= 2560 x 2048).
const P = preload("res://tools/art/pix.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")
const M = preload("res://tools/art/g7_cn_mesh.gd")
const GR = preload("res://tools/art/g7_cn_gear.gd")
const V = preload("res://tools/art/g7_cn_vehicles.gd")
const FIG = preload("res://tools/art/g7_cn_fig.gd")
const SO = preload("res://tools/art/g7_cn_soldiers.gd")

const FW := 284
const FH := 256
const PIV := Vector2i(142, 166)
## Frame 0 is what the catalog shows for an idle / flying air unit: hover (fans vertical, gear down) reads as a VTOL.
const FRAMES := ["hover", "flight", "transition", "landed", "ramp_down", "apc_ramp", "bay_open", "squad_in", "drones"]
const FRAME_ALIAS := {"fly": "flight", "takeoff": "transition", "descend": "hover"}
const ALT := {"flight": 2.4, "transition": 2.0, "hover": 1.4, "landed": 0.0, "ramp_down": 0.0, "apc_ramp": 0.0,
	"bay_open": 0.0, "squad_in": 0.0, "drones": 1.1}
const TILT := {"flight": PI / 2.0, "transition": PI / 4.0}
const STEALTH := Color8(74, 80, 90)
const VTOL := Color8(100, 108, 82)
const GLASS := Color8(40, 58, 70)
const INTERIOR := Color8(122, 116, 100)   # lit bay walls (warm work lights)
const DECK := Color8(84, 82, 74)
const GLOW := Color(1.0, 0.84, 0.52, 0.20)
## rev4 load sheets: wider cell so the APC lined up behind the ramp foot fits in every facing.
const LFW := 412
const LFH := 256
const LPIV := Vector2i(206, 144)
const APC_LOAD_FA := [-9.8, -8.0, -6.0, -3.6, -1.2, 0.95]   # front-axle f per apc_load frame (0.95 = parked)
const WALK4 := ["walk_a", "walk_2", "walk_b", "walk_5"]
const FILE_SP := 1.2          # soldier spacing in the file (m); one spacing per 4-frame loop
const FILE_F0 := -10.4        # where a walking soldier enters / leaves the sheet (just behind the ramp foot)
const FILE_F1 := -2.6         # deep in the bay: hidden behind the door frame from every facing
const HAZ := Color8(226, 184, 40)
const BAY_LIT := Color8(250, 214, 140)
const TEAMG := Color8(152, 152, 152)
const DUST := Color(0.58, 0.52, 0.42, 0.32)
## Geometry (metres; u = tiles for the manifest): bay deck f 4.6 .. -6.0 at z 1.3, half width 1.9; ramp hinge
## f -6.0, foot f -9.8 on the ground, half width 1.8; APC parked at f -1.6.
const DECK_Z := 1.3
const BAY_F0 := 4.6
const HINGE_F := -6.0
const DOOR_F := -6.6          # top of the rear aperture (tail boom starts here, 4.5 m up: clears the APC's pods)
const FOOT_F := -9.8
const TAIL_F := -8.4          # short upswept tail cone: a long boom would hide the open door from behind
const RAMP_HW := 1.8
const APC_F := -1.6
const SEATS := [3.4, 2.0, 0.6, -0.8, -2.2]
const BAY := {"u0": 1.15, "u1": -1.5, "hw": 0.475, "deck_m": 1.3, "height_m": 3.4}
const RAMP := {"hinge": -1.5, "foot": -2.45, "hw": 0.45, "len_m": 4.0}
const SQUAD := ["cn_team_leader", "cn_radio", "cn_deploy", "cn_scanner", "cn_ew", "cn_gunner", "cn_medic",
	"cn_gunner", "cn_deploy", "cn_gunner"]


static func _secs(stealth: bool) -> Array:
	var src: Array
	if stealth:
		var mid := [Vector2(2.0, 1.0), Vector2(3.0, 2.2), Vector2(2.3, 3.7), Vector2(1.3, 4.8)]
		src = [[9.8, [Vector2(0.1, 2.0), Vector2(0.3, 2.15), Vector2(0.15, 2.35), Vector2(0.05, 2.4)]],
			[8.0, [Vector2(0.9, 1.4), Vector2(1.6, 2.1), Vector2(1.1, 2.9), Vector2(0.5, 3.25)]],
			[6.2, [Vector2(1.6, 1.1), Vector2(2.5, 2.15), Vector2(1.9, 3.5), Vector2(0.95, 4.3)]],
			[4.6, mid], [HINGE_F, mid],
			[DOOR_F, [Vector2(1.75, 4.62), Vector2(2.15, 4.7), Vector2(1.75, 4.82), Vector2(1.0, 4.95)]],
			[TAIL_F, [Vector2(0.5, 4.78), Vector2(0.8, 4.85), Vector2(0.6, 5.0), Vector2(0.3, 5.08)]]]
	else:
		var mid := [Vector2(1.6, 1.0), Vector2(2.25, 1.6), Vector2(2.45, 3.0), Vector2(2.15, 4.4), Vector2(1.2, 5.0)]
		src = [[9.8, [Vector2(0.2, 2.2), Vector2(0.3, 2.5), Vector2(0.32, 2.9), Vector2(0.25, 3.2), Vector2(0.1, 3.3)]],
			[8.6, [Vector2(0.9, 1.5), Vector2(1.4, 2.0), Vector2(1.5, 2.9), Vector2(1.3, 3.7), Vector2(0.6, 4.0)]],
			[6.8, [Vector2(1.5, 1.05), Vector2(2.1, 1.6), Vector2(2.35, 2.9), Vector2(2.05, 4.3), Vector2(1.1, 4.9)]],
			[5.0, mid], [HINGE_F, mid],
			[DOOR_F, [Vector2(1.55, 4.62), Vector2(1.85, 4.68), Vector2(1.95, 4.8), Vector2(1.75, 4.97), Vector2(1.0, 5.1)]],
			[TAIL_F, [Vector2(0.5, 4.8), Vector2(0.65, 4.86), Vector2(0.68, 4.98), Vector2(0.55, 5.1), Vector2(0.3, 5.16)]]]
	var out: Array = []
	for s in src:
		out.append([float(s[0]), V.mir(s[1])])
	return out


## Quad indices j of one loft segment: bottom, roof, and the near-side wall (cutaway) for each fuselage.
static func _bottom(stealth: bool) -> int:
	return 3 if stealth else 4


static func _roof(stealth: bool) -> int:
	return 7 if stealth else 9


static func _near_wall(stealth: bool, right: bool) -> Array:
	if stealth:
		return [4, 5, 6] if right else [0, 1, 2]
	return [5, 6, 7, 8] if right else [0, 1, 2, 3]


# ------------------------------------------------------------------ lift fans / proprotors
## Tilting ducted fan (stealth) or proprotor nacelle (XL) at local c; tilt 0 = lift (axis up), PI/2 = thrust.
static func fan(S: Array, T: Dictionary, c: Vector3, R: float, tilt: float, rp: Array, ducted: bool, k: int, shaft_r: float) -> void:
	var pt := M.part(S, 1)
	var Td := M.sub(T, c, 0.0, -tilt)
	var dk: Array = C.ramp(Color8(30, 32, 34))
	M.cyl(pt, T, Vector3(c.x, (c.y + shaft_r) * 0.5, c.z), Vector3(0, 1, 0), 0.16, absf(c.y - shaft_r) * 0.5, 6, rp, {"edge": false})
	var spin := k * 0.37
	if ducted:
		M.cyl(pt, Td, Vector3.ZERO, Vector3(0, 0, 1), R, 0.42, 14, rp, {"cap_t": 0})
		for i in 14:   # the duct lip catches light; the fan disk turns inside it
			var t := TAU * i / 14.0
			var q := Vector3(cos(t) * R * 0.97, sin(t) * R * 0.97, 0.43)
			M.dpx(pt, Td, q, rp[3] if sin(t - 2.3) > 0.2 else rp[1], Vector3(0, 0, 1))
		for b in 5:
			var t := spin + TAU * b / 5.0
			M.dline(pt, Td, Vector3(0, 0, 0.43), Vector3(cos(t) * R * 0.82, sin(t) * R * 0.82, 0.43), C.ca(rp[2], 0.55), Vector3(0, 0, 1))
		M.dpx(pt, Td, Vector3(0, 0, 0.44), rp[3], Vector3(0, 0, 1))
		M.box(pt, Td, Vector3(0, 0, -0.5), Vector3(0.08, R * 0.9, 0.04), rp)   # exhaust vane
	else:
		M.cyl(pt, Td, Vector3(0, 0, 0.0), Vector3(0, 0, 1), 0.48, 1.0, 8, rp, {"cap_t": 2})
		M.cyl(pt, Td, Vector3(0, 0, 1.12), Vector3(0, 0, 1), 0.22, 0.14, 6, dk, {"edge": false})
		var disc: Array = []
		for i in 18:
			var t := TAU * i / 18.0
			disc.append(Vector3(cos(t) * R, sin(t) * R, 1.2))
		M.dpoly(pt, Td, disc, Color(0.80, 0.82, 0.78, 0.26))
		for i in 18:   # blade-tip ring
			M.dline(pt, Td, disc[i], disc[(i + 1) % 18], Color(0.86, 0.88, 0.84, 0.45))
		for b in 3:   # proprotor blades (motion blurred)
			var t := spin + TAU * b / 3.0
			M.dline(pt, Td, Vector3(0, 0, 1.2), Vector3(cos(t) * R, sin(t) * R, 1.2), Color(0.12, 0.13, 0.12, 0.9))
			M.dline(pt, Td, Vector3(0, 0, 1.21), Vector3(cos(t + 0.12) * R * 0.95, sin(t + 0.12) * R * 0.95, 1.21), Color(0.2, 0.2, 0.19, 0.6))
			M.dline(pt, Td, Vector3(0, 0, 1.22), Vector3(cos(t + 0.26) * R * 0.9, sin(t + 0.26) * R * 0.9, 1.22), Color(0.3, 0.3, 0.28, 0.3))


## Landing gear legs + wheels (down when landed / hovering / descending).
static func gear(S: Array, T: Dictionary, stealth: bool) -> void:
	var pt := M.part(S, 0.5)
	var dk: Array = C.ramp(Color8(44, 46, 48))
	var tr: Array = C.ramp(Color8(36, 36, 34))
	for g in [Vector3(7.0, 0, 0), Vector3(-1.0, -1.55, 0), Vector3(-1.0, 1.55, 0), Vector3(-3.4, -1.55, 0), Vector3(-3.4, 1.55, 0)]:
		M.box(pt, T, Vector3(g.x, g.y, 0.75), Vector3(0.08, 0.08, 0.35), dk)
		M.cyl(pt, T, Vector3(g.x, g.y, 0.36), Vector3(0, 1, 0), 0.36, 0.13, 8, tr, {"cap_t": 1})


# ------------------------------------------------------------------ airframe
## Wings, canards / tail surfaces, fans, flush intakes, lights, panel lines and team marks.
static func airframe(S: Array, T: Dictionary, stealth: bool, rp: Array, tilt: float, k: int, flying: bool) -> void:
	var dk: Array = C.ramp(Color8(30, 32, 34))
	if stealth:
		for s in [-1.0, 1.0]:
			var w := M.part(S, 1)   # swept blended wing with a faceted top
			M.prism(w, T, [Vector3(3.0, s * 2.7, 2.4), Vector3(-1.3, s * 5.85, 2.55), Vector3(-3.5, s * 5.85, 2.5),
				Vector3(-5.6, s * 2.7, 2.3)], Vector3(0, 0, -0.32), rp)
			M.dline(w, T, Vector3(1.2, s * 3.6, 2.46), Vector3(-4.4, s * 3.6, 2.36), C.ca(rp[0], 0.5), Vector3(0, 0, 1))
			M.dline(w, T, Vector3(-4.0, s * 2.9, 2.36), Vector3(-3.0, s * 4.6, 2.45), C.ca(rp[4], 0.35), Vector3(0, 0, 1))
			M.dpoly(w, T, [Vector3(-1.5, s * 5.0, 2.54), Vector3(-1.3, s * 5.7, 2.56), Vector3(-3.3, s * 5.7, 2.51),
				Vector3(-3.5, s * 5.0, 2.49)], TEAMG, Vector3(0, 0, 1), true)
			M.dpx(w, T, Vector3(-1.45, s * 5.82, 2.6), Color8(255, 70, 50) if s < 0 else Color8(80, 255, 120))
			var cn := M.part(S, 1)   # canard stub carrying the front fan
			M.prism(cn, T, [Vector3(6.2, s * 2.3, 2.15), Vector3(5.8, s * 3.5, 2.2), Vector3(4.8, s * 3.5, 2.18),
				Vector3(4.4, s * 2.3, 2.1)], Vector3(0, 0, -0.22), rp)
			fan(S, T, Vector3(5.3, s * 4.45, 2.2), 1.0, tilt, rp, true, k, s * 3.4)
			fan(S, T, Vector3(-2.4, s * 7.1, 2.5), 1.25, tilt, rp, true, k + 2, s * 5.8)
			# V-tail (rev4): ruddervators canted 68 deg from vertical with clipped (not pointed) tips, rooted on the
			# short tail cone: nose-on they read as small swept tail surfaces beside the cone, not two upright "ears".
			var fn := M.part(S, 2)
			var Tf := M.sub(T, Vector3(-7.0, s * 0.45, 4.85), 0.0, 0.0, -s * 1.19)
			M.prism(fn, Tf, [Vector3(1.0, -0.05, 0.0), Vector3(-0.75, -0.05, 1.55), Vector3(-2.05, -0.05, 1.55),
				Vector3(-1.75, -0.05, 0.0)], Vector3(0, 0.1, 0), rp)
			M.dpoly(fn, Tf, [Vector3(-0.8, s * 0.06, 0.95), Vector3(-1.85, s * 0.06, 0.95), Vector3(-1.95, s * 0.06, 1.35),
				Vector3(-0.95, s * 0.06, 1.35)], TEAMG, Vector3(0, s, 0), true)
			M.dline(fn, Tf, Vector3(0.9, s * 0.06, 0.04), Vector3(-0.72, s * 0.06, 1.5), C.ca(rp[4], 0.45), Vector3(0, s, 0))
			M.dline(fn, Tf, Vector3(-1.75, s * 0.06, 0.3), Vector3(-2.0, s * 0.06, 1.5), C.ca(rp[0], 0.6), Vector3(0, s, 0))
	else:
		var w := M.part(S, 2)   # high straight wing across the roof
		M.prism(w, T, [Vector3(1.3, -5.5, 5.35), Vector3(1.3, 5.5, 5.35), Vector3(-1.1, 5.5, 5.3), Vector3(-1.1, -5.5, 5.3)],
			Vector3(0, 0, -0.32), rp)
		for s in [-1.0, 1.0]:
			M.dline(w, T, Vector3(-0.6, s * 1.6, 5.36), Vector3(-0.6, s * 5.3, 5.33), C.ca(rp[0], 0.6), Vector3(0, 0, 1))
			M.dpoly(w, T, [Vector3(0.9, s * 3.9, 5.36), Vector3(0.9, s * 4.9, 5.36), Vector3(-0.8, s * 4.9, 5.33),
				Vector3(-0.8, s * 3.9, 5.33)], TEAMG, Vector3(0, 0, 1), true)
			M.dpx(w, T, Vector3(1.2, s * 5.45, 5.38), Color8(255, 70, 50) if s < 0 else Color8(80, 255, 120))
			fan(S, T, Vector3(0.0, s * 6.0, 5.2), 2.4, tilt, rp, false, k + (0 if s < 0 else 1), s * 5.4)
			var sp := M.part(S, 1)   # gear sponsons
			M.box(sp, T, Vector3(-1.9, s * 2.35, 1.6), Vector3(2.3, 0.38, 0.6), rp, Vector3(0.6, 0.6, 0.18))
		var fn := M.part(S, 2)   # T-tail
		M.prism(fn, T, [Vector3(-6.2, -0.07, 4.95), Vector3(-7.5, -0.07, 7.1), Vector3(-8.3, -0.07, 7.1), Vector3(-8.3, -0.07, 4.95)],
			Vector3(0, 0.14, 0), rp)
		M.prism(fn, T, [Vector3(-7.3, -2.7, 7.25), Vector3(-7.3, 2.7, 7.25), Vector3(-8.4, 2.7, 7.2), Vector3(-8.4, -2.7, 7.2)],
			Vector3(0, 0, -0.16), rp)
	if flying:   # engine glow at the tail exhausts
		var g := M.part(S, 2)
		for s in [-1.0, 1.0]:
			M.dpx(g, T, Vector3(TAIL_F - 0.05, s * 0.4, 4.9 if stealth else 5.0), Color8(255, 170, 90))


## Hull furniture on the fuselage part: intakes, canopy frame, windows, doors, ID panel, panel lines.
static func hull_marks(pt: Dictionary, T: Dictionary, stealth: bool, rp: Array) -> void:
	var line := C.ca(rp[0], 0.55)
	var roof := 4.8 if stealth else 5.0
	M.dpoly(pt, T, [Vector3(-1.4, -0.55, roof + 0.004), Vector3(-1.4, 0.55, roof + 0.004), Vector3(-3.0, 0.55, roof + 0.004),
		Vector3(-3.0, -0.55, roof + 0.004)], TEAMG, Vector3(0, 0, 1), true)
	for s in [-1.0, 1.0]:
		var n := Vector3(0, s * 0.6, 0.8).normalized()
		if stealth:   # flush dorsal intakes (stealth engines) and sawtooth panel joints
			M.dpoly(pt, T, [Vector3(3.4, s * 1.35, 4.75), Vector3(1.0, s * 1.3, 4.78), Vector3(1.0, s * 2.0, 4.15), Vector3(3.0, s * 2.0, 4.15)],
				Color8(20, 22, 26), n)
			for f in [-0.6, -2.6, -4.6]:
				M.dline(pt, T, Vector3(f, s * 1.35, 4.75), Vector3(f - 0.5, s * 2.2, 3.85), line, n)
			M.dline(pt, T, Vector3(7.8, s * 1.0, 2.95), Vector3(4.8, s * 2.1, 4.0), C.ca(rp[4], 0.5), n)
		else:   # cabin windows, crew door, roundel stripe
			for i in 6:
				M.dpx(pt, T, Vector3(3.0 - i * 1.15, s * 2.46, 3.4), Color8(30, 40, 48), Vector3(0, s, 0))
			var dr := [Vector3(4.4, s * 2.46, 1.7), Vector3(3.6, s * 2.46, 1.7), Vector3(3.6, s * 2.46, 3.6), Vector3(4.4, s * 2.46, 3.6)]
			for i in 4:
				M.dline(pt, T, dr[i], dr[(i + 1) % 4], line, Vector3(0, s, 0))
		for f in [2.0, -2.0]:   # frame seams on the walls
			M.dline(pt, T, Vector3(f, s * (2.9 if stealth else 2.45), 2.3 if stealth else 2.7), Vector3(f, s * (2.35 if stealth else 2.16), 3.6 if stealth else 4.5), line, Vector3(0, s, 0.2))


# ------------------------------------------------------------------ bay, cargo, ramp
## Height of the loading surface at local f: ground behind the ramp foot, the ramp, then the bay deck.
static func deck_h(f: float) -> float:
	if f <= FOOT_F:
		return 0.0
	if f >= HINGE_F:
		return DECK_Z
	return DECK_Z * (f - FOOT_F) / (HINGE_F - FOOT_F)


## Pose of the strike APC (g7_cn_vehicles model, axles at +2.55 / -2.25 m) with its front axle at local f = fa:
## both axles sit on the loading surface, so it pitches up the ramp and levels out on the deck.
static func apc_at(G: Dictionary, fa: float) -> Dictionary:
	var ra := fa - 4.8
	var hf := deck_h(fa)
	var hr := deck_h(ra)
	var pitch := atan2(hf - hr, 4.8)
	return M.sub(G, Vector3(fa - 2.55, 0, hr + 2.25 * tan(pitch)), 0.0, pitch)


## Lateral offset of the boarding file at local f: up the right half of the ramp, then along the right wall of
## the bay beside the parked APC.
static func file_r(f: float, stealth: bool) -> float:
	var r_in := 1.9 if stealth else 1.82
	if f <= HINGE_F:
		return 0.85
	return lerpf(0.85, r_in, clampf((f - HINGE_F) / 1.2, 0.0, 1.0))


## Bay interior, lit by work lights: inner walls, roof, front bulkhead and door frame (a flipped loft over the bay
## and door segments, seen only through the open rear door), the deck slab with tie-down rails, wall light strips,
## warm light pools on the deck and amber door-frame lights.
static func interior(S: Array, T: Dictionary, stealth: bool) -> void:
	var pt := M.part(S, 0.4)
	var b := _bottom(stealth)
	M.loft(pt, T, _secs(stealth).slice(3, 6), C.ramp(INTERIOR), {"flip": true, "cap0": true, "cap1": true,
		"skip": [[0, b], [1, b]], "edge": false})
	var wr := 2.3 if stealth else 2.28
	for s in [-1.0, 1.0]:
		M.dline(pt, T, Vector3(3.8, s * wr, 3.6), Vector3(HINGE_F + 0.3, s * wr, 3.6), BAY_LIT, Vector3(0, -s, 0))
		for f in [3.0, 1.5, 0.0, -1.5, -3.0, -4.5]:   # wall ribs
			M.dline(pt, T, Vector3(f, s * (wr + 0.05), 2.0), Vector3(f, s * (wr - 0.1), 4.2), C.ca(C.ramp(INTERIOR)[0], 0.5), Vector3(0, -s, 0))
		M.dpx(pt, T, Vector3(HINGE_F + 0.1, s * 1.85, DECK_Z + 0.25), HAZ, Vector3(0, -s, 0))
		M.dpx(pt, T, Vector3(DOOR_F + 0.1, s * 1.55, 4.35), HAZ)
	var dk := M.part(S, 0.45)
	M.prism(dk, T, [Vector3(BAY_F0, -1.9, DECK_Z), Vector3(BAY_F0, 1.9, DECK_Z), Vector3(HINGE_F, 1.9, DECK_Z),
		Vector3(HINGE_F, -1.9, DECK_Z)], Vector3(0, 0, -0.3), C.ramp(DECK), {"edge": false})
	for r in [-1.2, -0.4, 0.4, 1.2]:
		M.dline(dk, T, Vector3(BAY_F0 - 0.2, r, DECK_Z + 0.004), Vector3(HINGE_F + 0.1, r, DECK_Z + 0.004), C.ca(C.ramp(DECK)[3], 0.6), Vector3(0, 0, 1))
	for f in [3.0, 0.0, -3.0, -5.2]:
		M.dpoly(dk, T, [Vector3(f + 0.9, -1.6, DECK_Z + 0.006), Vector3(f + 0.9, 1.6, DECK_Z + 0.006),
			Vector3(f - 0.9, 1.6, DECK_Z + 0.006), Vector3(f - 0.9, -1.6, DECK_Z + 0.006)], GLOW, Vector3(0, 0, 1))


## A soldier sprite (the DL7-3 18 px figure) at local point p facing local yaw ya, in pose fname.
static func trooper(S: Array, T: Dictionary, kit_id: String, p: Vector3, ya: float, fname: String, layer: float, bias := 0.0) -> void:
	var w := M.wm(T, p)
	var yaw := float(T.yaw) + ya
	var par = T.par
	while par != null:
		yaw += float(par.yaw)
		par = par.par
	var kk := posmod(int(round(yaw / (PI / 4.0))), 8)
	var kt: Dictionary = SO.kit(kit_id)
	var o: Vector2 = T.o
	M.sprite(S, w, func(cv): FIG.draw(cv, kt, kk, fname, M.scr_w(o, w).floor()), layer, bias)


## The ten soldiers seated along the bay walls (5 a side, facing in), beside the parked APC.
static func seated(S: Array, T: Dictionary, stealth: bool) -> void:
	for i in 10:
		var s := -1.0 if i < 5 else 1.0
		trooper(S, T, String(SQUAD[i]), Vector3(SEATS[i % 5], s * (2.0 if stealth else 1.85), DECK_Z), -s * PI / 2.0, "crouch", 0.7)


## The boarding file for loop frame i (0..3): one spacing per loop, all in step, so frame 3 -> 0 is seamless.
## A soldier enters the sheet at FILE_F0 (just behind the ramp foot, where the sim hands its walking unit over) and
## leaves it at FILE_F1, deep in the bay where the door frame hides it from every facing. out = walking down.
static func file(S: Array, G: Dictionary, i: int, out: bool, stealth: bool) -> void:
	var j := 0
	while true:
		var d := (float(j) + float(i) / 4.0) * FILE_SP
		var f := (FILE_F1 - d) if out else (FILE_F0 + d)
		if (out and f < FILE_F0) or (not out and f > FILE_F1):
			break
		trooper(S, G, "cn_deploy", Vector3(f, file_r(f, stealth) * (1.0 if not out else 1.0), deck_h(f)), PI if out else 0.0,
			String(WALK4[i % 4]), 1.0)
		j += 1


## Rear ramp from the hinge (deck height) down to the ground (or half open in flight): hazard chevrons, side curbs,
## hydraulic jacks to the door frame, light spilling out of the bay onto its upper half.
static func ramp(S: Array, T: Dictionary, rp: Array, pitch: float) -> void:
	var pt := M.part(S, 1, 0.3)
	var Tr := M.sub(T, Vector3(HINGE_F, 0, DECK_Z), PI, -pitch)
	M.box(pt, Tr, Vector3(2.0, 0, -0.07), Vector3(2.0, RAMP_HW, 0.07), rp)
	for i in 5:
		var f := 0.5 + i * 0.75
		M.dline(pt, Tr, Vector3(f, -1.5, 0.004), Vector3(f + 0.3, 0.0, 0.004), C.ca(HAZ, 0.85), Vector3(0, 0, 1))
		M.dline(pt, Tr, Vector3(f + 0.3, 0.0, 0.004), Vector3(f, 1.5, 0.004), C.ca(HAZ, 0.85), Vector3(0, 0, 1))
	var dk: Array = C.ramp(Color8(40, 42, 44))
	for s in [-1.0, 1.0]:
		M.box(pt, Tr, Vector3(2.0, s * (RAMP_HW - 0.06), 0.05), Vector3(1.95, 0.06, 0.05), rp)
		var a := Vector3(HINGE_F - 1.7 * cos(pitch), s * 1.7, DECK_Z - 1.7 * sin(pitch) + 0.08)
		var b := Vector3(HINGE_F - 0.12, s * 2.0, 2.5)
		M.cyl(pt, T, (a + b) * 0.5, b - a, 0.05, a.distance_to(b) * 0.5, 4, dk, {"edge": false})
	M.dpoly(pt, Tr, [Vector3(0.1, -1.6, 0.006), Vector3(0.1, 1.6, 0.006), Vector3(1.6, 1.3, 0.006), Vector3(1.6, -1.3, 0.006)],
		GLOW, Vector3(0, 0, 1))


## Five defence drones launched during an extraction (3 kamikaze, 2 machine-gun).
static func drones(S: Array, T: Dictionary) -> void:
	var at := [Vector3(-11.0, -3.0, 3.2), Vector3(-9.5, 4.5, 4.4), Vector3(2.0, -7.5, 3.6), Vector3(6.0, 6.2, 2.8), Vector3(-4.0, 8.0, 5.0)]
	for i in at.size():
		var pt := M.part(S, 2)
		var c: Vector3 = at[i]
		var mg := i >= 3
		M.box(pt, T, c, Vector3(0.28 if mg else 0.4, 0.18 if mg else 0.1, 0.09), C.ramp(Color8(58, 62, 64)))
		for a in 4:
			var t := PI / 4.0 + a * PI / 2.0
			var tip := c + Vector3(cos(t) * 0.55, sin(t) * 0.55, 0.05)
			M.dline(pt, T, c, tip, Color8(34, 36, 38))
			M.dpx(pt, T, tip, Color(0.8, 0.82, 0.8, 0.6))
		M.dpx(pt, T, c + Vector3(0.3, 0, -0.05), Color8(255, 70, 50) if not mg else Color8(255, 220, 120))
		var sh := M.part(S, -1)
		sh.dec.append({"k": "px", "a": M.wm(T, Vector3(c.x + c.z * 0.25, c.y, 0.0)), "col": Color(0.03, 0.04, 0.03, 0.35), "n": Vector3.ZERO})


static func _dust(S: Array, T: Dictionary, k: int) -> void:
	var pt := M.part(S, -1)
	for i in 70:
		var t := TAU * P.hn(i, k, 41)
		var r := 7.0 + P.hn(i, k, 43) * 5.0
		var w := M.wm(T, Vector3(cos(t) * r * 0.9 - 1.0, sin(t) * r, 0.0))
		pt.dec.append({"k": "px", "a": Vector3(w.x, w.y, 0.0), "col": DUST, "n": Vector3.ZERO})


static func _apc(S: Array, Tp: Dictionary, fname: String) -> void:
	var S2: Array = []
	V.model(S2, Tp, true, fname, false, true)
	M.merge(S, S2, 0.6, 0.0, 1)


# ------------------------------------------------------------------ the frame
## One frame. Main-sheet frames: FRAMES. Load-sheet frames: apc_load_0..5, squad_load_0..3, squad_unload_0..3.
static func craft(cv, k: int, fname: String, o: Vector2, stealth: bool) -> void:
	fname = String(FRAME_ALIAS.get(fname, fname))
	var a := k * PI / 4.0
	var alt: float = ALT.get(fname, 0.0)
	var tilt: float = TILT.get(fname, 0.0)
	var T := M.pose(o, a, Vector3(0, 0, alt))
	var G := M.pose(o, a)
	var S: Array = []
	var rp: Array = C.ramp(STEALTH if stealth else VTOL)
	var gl: Array = C.ramp(GLASS)
	var load_n := int(fname.get_slice("_", fname.get_slice_count("_") - 1)) if fname.contains("_load_") or fname.contains("_unload_") else -1
	var open := fname in ["ramp_down", "apc_ramp", "bay_open", "squad_in", "drones"] or load_n >= 0
	var flying := fname in ["flight", "transition"]
	var skip: Array = []
	if open:
		skip.append([4, _bottom(stealth)])
		interior(S, T, stealth)
	if fname == "apc_ramp":
		_apc(S, apc_at(G, float(APC_LOAD_FA[3])), "move")   # = apc_load_3 (fits the main cell)
	elif fname.begins_with("apc_load_"):
		_apc(S, apc_at(G, float(APC_LOAD_FA[load_n])), "idle" if load_n == APC_LOAD_FA.size() - 1 else ("move" if load_n % 2 == 0 else "move_1"))
	elif fname == "bay_open":
		_apc(S, apc_at(G, float(APC_LOAD_FA[-1])), "idle")
		seated(S, G, stealth)
	elif fname == "squad_in" or fname.begins_with("squad_load_") or fname.begins_with("squad_unload_"):
		_apc(S, apc_at(G, float(APC_LOAD_FA[-1])), "idle")
		file(S, G, maxi(0, load_n), fname.begins_with("squad_unload_"), stealth)
	var mats := {}
	var nv := 8 if stealth else 10
	for j in ([0, 6, 7] if stealth else [0, 1, 7, 8, 9]):
		mats["1,%d" % j] = gl
	mats["2,%d" % (nv - 1)] = gl
	if not stealth:
		mats["0,9"] = gl
		mats["0,0"] = gl
		mats["0,8"] = gl
	var fus := M.part(S, 1)
	M.loft(fus, T, _secs(stealth), rp, {"skip": skip, "mats": mats})
	hull_marks(fus, T, stealth, rp)
	if not open:   # closed rear door: frame, clamshell seam, hinge line, two position lights
		var bw := 2.0 if stealth else 1.6
		var tw := 1.75 if stealth else 1.55
		var dn := Vector3(-(4.62 - 1.0), 0, -(HINGE_F - DOOR_F)).normalized()
		var q := [Vector3(HINGE_F - 0.01, -bw + 0.12, 1.05), Vector3(HINGE_F - 0.01, bw - 0.12, 1.05),
			Vector3(DOOR_F + 0.01, tw - 0.1, 4.55), Vector3(DOOR_F + 0.01, -tw + 0.1, 4.55)]
		for i in 4:
			M.dline(fus, T, q[i], q[(i + 1) % 4], C.ca(rp[0], 0.8), dn)
		M.dline(fus, T, Vector3(HINGE_F - 0.01, 0, 1.05), Vector3(DOOR_F + 0.01, 0, 4.55), C.ca(rp[0], 0.6), dn)
		M.dline(fus, T, Vector3(HINGE_F - 0.03, -bw + 0.3, 1.35), Vector3(HINGE_F - 0.03, bw - 0.3, 1.35), C.ca(rp[3], 0.5), dn)
		for sd in [-1.0, 1.0]:
			M.dpx(fus, T, Vector3(DOOR_F + 0.02, sd * (tw - 0.25), 4.4), Color8(255, 70, 50) if sd < 0 else Color8(80, 255, 120), dn)
	airframe(S, T, stealth, rp, tilt, k, flying)
	if not flying:
		gear(S, T, stealth)
	if open:
		ramp(S, T, rp, 0.15 if fname == "drones" else asin(DECK_Z / 4.0))
	if fname == "drones":
		drones(S, T)
	if fname in ["hover", "transition", "drones"]:
		_dust(S, G, k)
	M.shadow(cv, S, o, 0.36, Vector2(0.25, -0.06))
	M.render_z(cv, S, o, 53 + k)


static func apc_frames() -> Array:
	var r: Array = []
	for i in APC_LOAD_FA.size():
		r.append("apc_load_%d" % i)
	return r


static func squad_frames(out := false) -> Array:
	var r: Array = []
	for i in 4:
		r.append(("squad_unload_%d" if out else "squad_load_%d") % i)
	return r


## Unload aliases: the APC reverses down the ramp (apc_load played backwards); squads have their own walk-out loop.
static func load_alias() -> Dictionary:
	var al := {}
	var n := APC_LOAD_FA.size()
	for i in n:
		al["apc_unload_%d" % i] = "apc_load_%d" % (n - 1 - i)
	return al


static func build(out: Dictionary) -> void:
	var strip := ["flight", "transition", "hover", "landed", "ramp_down", "apc_ramp", "bay_open", "squad_in", "ramp_down", "drones"]
	var fx := {"footprint_tiles": [4.9, 4.2], "size_m": [19.6, 16.7, 6.4], "bay": BAY, "ramp": RAMP, "deck_px": DECK_Z * M.ZP,
		"roof_px": 4.6 * M.ZP, "apc_u": APC_F / M.MT, "scale": "4 m/tile, 9.8 px/m (fact art.scale)",
		"cargo": "1 strike APC (g7_cn_strike_apc, 8.0 x 2.9 m = 2.0 x 0.73 tiles) + 10 seated soldiers", "frame_alias": FRAME_ALIAS,
		"altitude_m": ALT, "fan_tilt_rad": {"flight": PI / 2.0, "transition": PI / 4.0, "other": 0.0},
		"depth": "per-pixel z-buffer (M.render_z): cargo / soldiers hidden wherever the hull is in front",
		"bay_open": "rev4: APC parked in the lit bay seen through the open rear door (no cutaway)"}
	for st in [true, false]:
		var stealth: bool = st
		var id := "g7_cn_stealth_dropship" if stealth else "g7_a_vtol_dropship_xl"
		var e := {"sample": "air", "line": "strike_team" if stealth else "human_a", "key_frames": FRAMES.duplicate(),
			"anim_strip": strip, "load_sheets": {"apc": id + "_apcload", "squad": id + "_squadload", "squad_out": id + "_squadunload"}}
		if not stealth:
			e["upgrades"] = "a_vtol_dropship"
			e["size_m"] = [19.6, 15.6, 7.25]
		C.unit_sheet(out, id, "vehicles", "air_large", FW, FH, PIV, FRAMES,
			func(cv, k, f, o): craft(cv, k, f, o, stealth), e.merged(fx))
		var lfx := {"sample": "air", "line": e.line, "load_sheet_of": id, "scale": fx.scale, "bay": BAY, "ramp": RAMP,
			"depth": fx.depth, "pivot_note": "same world point as the main sheet pivot (craft origin); wider cell for the APC behind the ramp"}
		C.unit_sheet(out, id + "_apcload", "vehicles", "air_large", LFW, LFH, LPIV, apc_frames(),
			func(cv, k, f, o): craft(cv, k, f, o, stealth),
			lfx.merged({"key_frames": apc_frames(), "anim_strip": apc_frames(), "loop": false, "frame_alias": load_alias(),
			"apc_front_axle_f_m": APC_LOAD_FA, "note": "apc_load_0: APC on the ground lined up behind the craft, front wheels at the ramp foot; _5: parked in the bay (= bay_open). Unload: apc_unload_i = apc_load_(5-i) (reverses down the ramp)"}))
		for o2 in [false, true]:
			var sf := squad_frames(o2)
			C.unit_sheet(out, id + ("_squadunload" if o2 else "_squadload"), "vehicles", "air_large", LFW, LFH, LPIV, sf,
				func(cv, k, f, o): craft(cv, k, f, o, stealth),
				lfx.merged({"key_frames": sf.duplicate(), "anim_strip": sf.duplicate(), "loop": true,
				"file": {"spacing_m": FILE_SP, "enter_f_m": FILE_F0, "leave_f_m": FILE_F1, "per_loop_m": FILE_SP},
				"note": ("squad_unload_0..3 loops while a squad leaves: one soldier walks down the ramp per loop and is handed to the sim at the ramp foot (leave at enter_f)." if o2 else
				"squad_load_0..3 loops while a squad boards (APC already aboard): one soldier walks up the ramp per loop. The sim hides each walking unit when it reaches the ramp foot (enter_f).")}))
