extends SceneTree
## G7 ART7F (13.9c): finished counter-nanite facility art + the facility wall autotile + the upgraded dropship pad.
## Same faceted per-pixel-depth renderer and real-metre scale as the ART7E facility (g7_cn_facility.gd: 4 m per
## 64x32 tile, light from the upper left, hard outline). Writes its own group assets/art/g7_fac7f/ (manifest.json),
## so it never touches another generator's files. Deterministic: re-running reproduces byte-identical files.
##   godot --headless --path . -s tools/art/g7_fac7f.gd                 # writes assets/art/g7_fac7f/
##   godot --headless --path . -s tools/art/g7_fac7f.gd -- --out=<abs dir>
## Buildings (manifest "buildings"):
##   g7_fac_wall      2x2 blast-wall autotile SHEET: column = neighbour mask m (N1 E2 S4 W8), row 0 intact, 1 damaged.
##                    Arms run from the core to the cell edge (T-wall slabs, razor wire), straight runs continue the
##                    slab line, corners / T / cross / ends get a hardened pillar (lamp + camera on corners).
##   g7_fac_planning  mission planning room (hardened TOC: blast-door vestibule, antenna farm, satcom radome, HVAC,
##                    generator, T-wall screen on the long side)
##   g7_fac_dronebay  overwatch drone bay (small hangar + roll-up door, workbench under an awning, launch pad with
##                    the overwatch quadcopter, charging cabinets, relay mast)
##   g7_fac_workshop  APC workshop (high-bay shed sized for the 8 m strike APC, open door with a lit bay and lift,
##                    gantry crane, wheel / armour-plate yard, drone assembly bench)
##   g7_fac_range     simulation range (kill house with catwalk, earth berms, Machine replica targets, range tower)
##   g7_fac_lab       package lab (only when the json has a lab zone)
##   a_g7_vtol_pad    6x6 dropship landing site for the XL VTOL / stealth dropship (flat; rot_<f> = approach side)
## Zone buildings: states rot_<f> and rot_<f>_lockdown, f = door side (0 +x, 1 +y, 2 -x, 3 -y), drawn at the zone
## size read from content/g7/defs_g7_facility.json at generation time (entity_layer centres them on the zone and picks
## f toward the compound centre). "built" / "lockdown" alias rot_0.
const GEN = preload("res://tools/gen_art.gd")
const P = preload("res://tools/art/pix.gd")
const K = preload("res://tools/art/g5_bld_lib.gd")
const H = preload("res://tools/art/g6_lib.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")
const M = preload("res://tools/art/g7_cn_mesh.gd")
const GR = preload("res://tools/art/g7_cn_gear.gd")
const RO = preload("res://tools/art/g7_rollout.gd")
const FAC = preload("res://tools/art/g7_cn_facility.gd")
const TU = preload("res://tools/art/g7_turrets2.gd")
const GROUP := "g7_fac7f"
const DEFS := "res://content/g7/defs_g7_facility.json"

const CONC := Color8(150, 148, 138)
const CONC_D := Color8(118, 116, 108)
const STEEL := Color8(84, 90, 96)
const DARK := Color8(46, 50, 52)
const ASPH := Color8(74, 76, 78)
const OLIVE := Color8(96, 104, 84)
const SAND := Color8(150, 132, 96)
const EARTH := Color8(112, 98, 72)
const YEL := Color8(226, 184, 40)
const SIGN := Color8(38, 42, 44)
const STENCIL := Color8(226, 226, 214)
const CN_BLUE := Color8(110, 180, 255)
const AMBER := Color8(246, 178, 60)
const LAMP_G := Color8(150, 255, 170)
const LAMP_R := Color8(255, 70, 50)
const LAMP_W := Color8(255, 244, 210)
const GLASS := Color8(40, 64, 78)
const POOL := Color(1.0, 0.95, 0.78, 0.14)
const X := Vector3(1, 0, 0)
const Y := Vector3(0, 1, 0)
const Z := Vector3(0, 0, 1)
const ZS := 0.125   # slab top (m)


func _init() -> void:
	var dir := "res://assets/art/%s/" % GROUP
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			dir = String(a).substr(6)
	var t0 := Time.get_ticks_msec()
	var out := build()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var n := GEN.save(out, dir)
	var ids: Array = (out.manifest.buildings as Dictionary).keys()
	ids.sort()
	for id in ids:
		var b: Dictionary = out.manifest.buildings[id]
		print("G7_FAC7F %s states=%d fw=%d fh=%d fits=%s" % [id, (b.states as Dictionary).size(), int(b.fw), int(b.fh), str(b.get("fits", ""))])
	print("G7_FAC7F files=%d ms=%d" % [n, Time.get_ticks_msec() - t0])
	quit()


static func conf() -> Dictionary:
	var f := FileAccess.open(DEFS, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return (d.get("_g7_facility", {}) as Dictionary) if d is Dictionary else {}


static func build() -> Dictionary:
	var out := {"images": {}, "manifest": {"version": 1, "tile": [64, 32], "group": GROUP, "buildings": {}}}
	build_wall(out)
	build_tower(out)
	var c := conf()
	for z in [["planning", "g7_fac_planning", "planning"], ["drone_bay", "g7_fac_dronebay", "dronebay"],
			["workshop", "g7_fac_workshop", "workshop"], ["range", "g7_fac_range", "range"], ["lab", "g7_fac_lab", "lab"],
			["gate_outer", "g7_fac_gate_outer", "gate"], ["gate_inner", "g7_fac_gate_inner", "gate"],
			["apc_wash", "g7_fac_wash", "wash"], ["decon_hall", "g7_fac_deconhall", "hall"]]:
		var r: Array = c.get(z[0], [])
		if r.size() == 4:
			build_zone(out, String(z[1]), int(r[2]), int(r[3]), String(z[2]))
		elif ENTRY_DEFAULT.has(z[0]):   # 13.9c-2 zones not in the json yet: PROVISIONAL default size (re-run after BASE7-3)
			var d: Array = ENTRY_DEFAULT[z[0]]
			build_zone(out, String(z[1]), int(d[0]), int(d[1]), String(z[2]))
			out.manifest.buildings[String(z[1])]["provisional"] = true
	build_vtol_pad(out)
	return out


static func _put(out: Dictionary, entry: Dictionary, id: String, nm: String, cv) -> void:
	var f := "buildings/%s_%s.png" % [id, nm]
	var mk := "buildings/%s_%s_mask.png" % [id, nm]
	out.images[f] = cv.img
	out.images[mk] = cv.mask
	entry.states[nm] = {"file": f, "mask": mk}


# ================================================================ wall autotile (2 x 2 tiles = 8 x 8 m)
const WALL_TOP := 44
const ARM := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]   # N E S W (bit 0..3), tile axes


## One T-wall slab centred at c (local metres) running along `al` (X or Y), width 1.6 m, 3.6 m tall.
static func _slab(pt: Dictionary, T: Dictionary, c: Vector3, al: Vector3, i: int, seed: int) -> void:
	var nl := Y if al == X else X
	var conc: Array = C.ramp(CONC)
	var hx := Vector3(0.8, 0.65, 0.3) if al == X else Vector3(0.65, 0.8, 0.3)
	var sx := Vector3(0.8, 0.17, 1.5) if al == X else Vector3(0.17, 0.8, 1.5)
	var sk := 0.97 + 0.03 * P.hn(i, seed, 7)
	M.box(pt, T, c + Z * 0.3, hx, conc)
	M.box(pt, T, c + Z * (2.1 * sk), Vector3(sx.x, sx.y, 1.5 * sk), conc, Vector3(0.0, 0.0, 0.05))
	for s in [-1.0, 1.0]:
		var f: Vector3 = c + nl * (0.18 * s)
		M.dline(pt, T, f + Z * 0.62 - al * 0.78, f + Z * 0.62 + al * 0.78, C.ca(conc[1], 0.8), nl * s)
		M.dline(pt, T, f + Z * 1.4 - al * 0.5, f + Z * 1.4 + al * 0.5, C.ca(conc[1], 0.6), nl * s)
		M.dline(pt, T, f - al * 0.79 + Z * 0.65, f - al * 0.79 + Z * 3.5, C.ca(conc[0], 0.7), nl * s)   # slab joint
		for j in 3:   # grime streaks
			var rr := -0.6 + 1.2 * P.hn(i, j * 2 + (1 if s > 0 else 0), seed)
			M.dline(pt, T, f + al * rr + Z * 3.4, f + al * rr + Z * (2.4 - P.hn(j, i, seed + 5)), Color(0.25, 0.24, 0.2, 0.35), nl * s)
		var cz := 0.9 + 2.0 * P.hn(i, seed, 11)
		M.dpx(pt, T, f + al * (-0.5 + P.hn(seed, i, 13)) + Z * cz, Color8(120, 70, 44), nl * s)   # chip + rebar
	M.dpx(pt, T, c + Z * 3.62, C.ramp(CONC)[0])   # lifting eye
	if i % 5 == 2:
		RO.quad(pt, T, c + nl * 0.182 + Z * 1.6, al * 0.3, Z * 0.2, YEL, nl)   # warning plate (outer face)


## Wall piece for neighbour mask m: arms to every linked edge, a pillar wherever the run turns, ends or branches.
static func wall_piece(cv, o: Vector2, m: int, seed: int) -> void:
	var S: Array = []
	var T := M.pose(o, 0.0)
	var straight_ns := m == 5
	var straight_ew := m == 10
	var arms: Array = []
	for b in 4:
		if m & (1 << b):
			arms.append(b)
	var k := 0
	if straight_ns or straight_ew:
		var al := Y if straight_ns else X
		for i in 5:
			_slab(M.part(S, 0), T, al * (-3.2 + i * 1.6), al, i, seed)
		_wall_kit(M.part(S, 0), T, Vector3.ZERO, al, 4.0)   # ART7F-2: continuous footing + capping beam
		RO.wire(M.part(S, 1), T, al * -4.0, al * 4.0, 3.8)
		_fin_piece(cv, S, o, seed + m)
		return
	for b in arms:   # arm slabs from the pillar face (1.0 m) to the cell edge (4 m): centres 1.8 (w 1.6) + 3.2 trimmed
		var d := Vector3(ARM[b].x, ARM[b].y, 0)
		var al := X if absf(d.x) > 0.5 else Y
		for c in [1.8, 3.2]:
			_slab(M.part(S, 0), T, d * c, al, k, seed)
			k += 1
		_wall_kit(M.part(S, 0), T, d * 2.5, al, 1.5)
		RO.wire(M.part(S, 1), T, d * 1.0, d * 4.0, 3.8)
	if m == 0:   # free-standing segment (neighbours lost): three slabs N-S
		for i in 3:
			_slab(M.part(S, 0), T, Y * (-1.6 + i * 1.6), Y, i, seed)
		RO.wire(M.part(S, 1), T, Y * -2.4, Y * 2.4, 3.62)
	else:
		_pillar(S, T, m, arms.size(), seed)
	_fin_piece(cv, S, o, seed + m)


## Hardened junction pillar (2 x 2 m, 4.2 m): cap, hazard band on ends, floodlight + camera on corners / T-joins.
static func _pillar(S: Array, T: Dictionary, m: int, n: int, seed: int) -> void:
	var pp := M.part(S, 0)
	var cd: Array = C.ramp(CONC_D)
	M.box(pp, T, Vector3(0, 0, 0.35), Vector3(1.1, 1.1, 0.35), cd, Vector3(0.05, 0.05, 0.05))
	M.box(pp, T, Vector3(0, 0, 2.3), Vector3(0.95, 0.95, 1.6), C.ramp(CONC), Vector3(0.03, 0.03, 0.03))
	M.box(pp, T, Vector3(0, 0, 4.0), Vector3(1.05, 1.05, 0.12), cd)
	for nl in [X, Y, -X, -Y]:
		M.dline(pp, T, nl * 0.952 + Z * 0.75 - RO._along(nl) * 0.9, nl * 0.952 + Z * 0.75 + RO._along(nl) * 0.9, C.ca(cd[0], 0.8), nl)
		M.dline(pp, T, nl * 0.952 + Z * 3.2 + RO._along(nl) * (0.5 - P.hn(seed, m, 3)), nl * 0.952 + Z * 2.2, Color(0.22, 0.21, 0.18, 0.3), nl)
	if n == 1:   # wall end: hazard chevrons on the open face
		var b := 0
		for i in 4:
			if m & (1 << i):
				b = i
		var face := -Vector3(ARM[b].x, ARM[b].y, 0)
		FAC._jamb(pp, T, face * 0.95, face, 0.7, 0.4, 3.6)
	var pl := M.part(S, 1)
	M.cyl(pl, T, Vector3(0, 0, 4.45), Z, 0.12, 0.35, 6, C.ramp(STEEL), {"cap_t": 2})
	if n >= 2:   # floodlight on the outer corner + a pan-tilt camera
		M.box(pl, T, Vector3(0.0, 0.0, 4.9), Vector3(0.3, 0.18, 0.12), C.ramp(STEEL))
		M.dpx(pl, T, Vector3(0.32, 0.0, 4.86), LAMP_W, X)
		M.dpx(pl, T, Vector3(0.0, 0.2, 4.86), LAMP_W, Y)
		M.box(pl, T, Vector3(-0.5, -0.5, 4.3), Vector3(0.18, 0.1, 0.09), C.ramp(Color8(210, 210, 200)))
		M.dpx(pl, T, Vector3(-0.31, -0.5, 4.3), Color8(60, 200, 255), X)
	else:
		M.dpx(pl, T, Vector3(0, 0, 4.82), LAMP_R)


static func _fin_piece(cv, S: Array, o: Vector2, seed: int) -> void:
	M.shadow(cv, S, o)
	M.render_z(cv, S, o, seed)


static func build_wall(out: Dictionary) -> void:
	var co: Array = K.canvas(2, WALL_TOP)
	var o: Vector2 = co[1]
	var fw: int = co[0].w
	var fh: int = co[0].h
	var sheet := P.Canvas.new(fw * 16, fh * 2)
	for m in 16:
		var cv = K.canvas(2, WALL_TOP)[0]
		wall_piece(cv, o, m, 4100 + m * 7)
		var base = H.copy(cv)
		C.selout(cv)
		var dm = H.copy(base)
		K.damage(dm, o, 2, 9100 + m * 13)
		C.selout(dm)
		for row in 2:
			var src = cv if row == 0 else dm
			(sheet.img as Image).blit_rect(src.img, Rect2i(0, 0, fw, fh), Vector2i(m * fw, row * fh))
			(sheet.mask as Image).blit_rect(src.mask, Rect2i(0, 0, fw, fh), Vector2i(m * fw, row * fh))
	var entry := {"size": 2, "pivot": [int(o.x), int(o.y)], "fw": fw, "fh": fh, "states": {},
		"sheet": {"cols": "conn mask m = N1 E2 S4 W8 (tile axes)", "rows": ["intact", "damaged"]},
		"fits": "cn_blast_wall 2x2 segment, pivot = segment centre; arms reach the cell edge so linked segments join"}
	_put(out, entry, "g7_fac_wall", "sheet", sheet)
	entry.states["built"] = (entry.states["sheet"] as Dictionary).duplicate()
	out.manifest.buildings["g7_fac_wall"] = entry


# ================================================================ hardened tower autotile (2 x 2 tiles = 8 x 8 m)
## ART7F-2 (13.9c-3): the cn_tower drawn as part of the wall ring. Column = neighbour mask m (N1 E2 S4 W8), row 0
## intact / 1 damaged. A 4.8 m square reinforced-concrete bastion (chamfered footing, corner pilasters, firing slits
## on every face, armoured blast door on a free face) fills the middle of the cell; on every linked side a T-wall slab
## with the same footing and capping beam runs from the bastion face to the cell edge, so the wall meets the tower
## flush on both sides. Above: a thick shaft with slits and a caged ladder, an armoured cab with vision blocks under
## an overhanging roof slab, an armoured cupola with a remote weapon station, searchlight, camera, red obstruction lamp.
const TOWER_TOP := 140
const TB := 2.4    # bastion half width (m): arm slabs fill TB..4.0 exactly


static func _wall_kit(pt: Dictionary, T: Dictionary, c: Vector3, al: Vector3, hl: float) -> void:
	var nl := Y if al == X else X
	var cd: Array = C.ramp(CONC_D)
	M.box(pt, T, c + Z * 0.22, (al * hl + nl * 1.15 + Z * 0.22).abs(), cd, Vector3(0.0, 0.0, 0.06))   # footing
	M.box(pt, T, c + Z * 3.68, (al * hl + nl * 0.32 + Z * 0.1).abs(), cd)   # capping beam


static func tower_piece(cv, o: Vector2, m: int, seed: int) -> void:
	var S: Array = []
	var T := M.pose(o, 0.0)
	var conc: Array = C.ramp(CONC)
	var cd: Array = C.ramp(CONC_D)
	var st: Array = C.ramp(STEEL)
	var arm: Array = C.ramp(Color8(98, 104, 98))
	var k := 0
	for b in 4:   # wall arms to the cell edge
		if not (m & (1 << b)):
			continue
		var d := Vector3(ARM[b].x, ARM[b].y, 0)
		var al := X if absf(d.x) > 0.5 else Y
		_slab(M.part(S, 0), T, d * 3.2, al, k, seed)
		_wall_kit(M.part(S, 0), T, d * 3.2, al, 0.8)
		RO.wire(M.part(S, 1), T, d * TB, d * 4.0, 3.8)
		k += 1
	var pb := M.part(S, 0)   # bastion
	M.box(pb, T, Vector3(0, 0, 0.3), Vector3(TB + 0.25, TB + 0.25, 0.3), cd, Vector3(0.2, 0.2, 0.0))
	M.box(pb, T, Vector3(0, 0, 2.55), Vector3(TB, TB, 1.95), conc, Vector3(0.04, 0.04, 0.04))
	for nl in [X, Y, -X, -Y]:
		var al := RO._along(nl)
		FAC._wall(pb, T, nl * TB, al, TB * 2.0, 4.5, nl, conc, seed + int(nl.x * 3.0 + nl.y * 7.0))
		for s in [-1.0, 1.0]:   # firing slits clear of the arm slab
			RO.quad(pb, T, nl * (TB + 0.012) + al * (s * 1.55) + Z * 2.9, al * 0.38, Z * 0.07, Color8(20, 22, 24), nl)
			M.dline(pb, T, nl * (TB + 0.016) + al * (s * 1.55 - 0.42) + Z * 3.0, nl * (TB + 0.016) + al * (s * 1.55 + 0.42) + Z * 3.0, C.ca(cd[0], 0.9), nl)
	for cx in [-1.0, 1.0]:   # corner pilasters
		for cy in [-1.0, 1.0]:
			M.box(pb, T, Vector3(cx * (TB - 0.05), cy * (TB - 0.05), 2.4), Vector3(0.3, 0.3, 2.1), cd)
	var dface := -1   # armoured blast door on the first free face the camera sees (S, E, then W, N)
	for b in [2, 1, 3, 0]:
		if not (m & (1 << b)):
			dface = b
			break
	if dface >= 0:
		var nl := Vector3(ARM[dface].x, ARM[dface].y, 0)
		var al := RO._along(nl)
		RO.quad(pb, T, nl * (TB + 0.014) + Z * 1.15, al * 0.6, Z * 1.05, st[1], nl)
		for i in 5:
			M.dline(pb, T, nl * (TB + 0.018) + al * -0.55 + Z * (0.3 + i * 0.4), nl * (TB + 0.018) + al * 0.55 + Z * (0.3 + i * 0.4), C.ca(st[3], 0.9), nl)
		FAC._jamb(pb, T, nl * TB + al * 0.75, nl, 0.1, 0.1, 2.2)
		FAC._jamb(pb, T, nl * TB - al * 0.75, nl, 0.1, 0.1, 2.2)
		M.dpx(pb, T, nl * (TB + 0.02) + Z * 2.45, LAMP_W, nl)
	var pr := M.part(S, 1)   # bastion parapet
	for e in [[Vector3(0, -TB + 0.15, 4.62), Vector3(TB, 0.15, 0.12)], [Vector3(0, TB - 0.15, 4.62), Vector3(TB, 0.15, 0.12)],
			[Vector3(-TB + 0.15, 0, 4.62), Vector3(0.15, TB - 0.3, 0.12)], [Vector3(TB - 0.15, 0, 4.62), Vector3(0.15, TB - 0.3, 0.12)]]:
		M.box(pr, T, e[0], e[1], cd)
	var ps := M.part(S, 1)   # shaft z 4.5..8.8
	M.box(ps, T, Vector3(-0.2, -0.2, 6.65), Vector3(1.4, 1.4, 2.15), conc, Vector3(0.03, 0.03, 0.03))
	for nl in [X, Y]:
		var al := RO._along(nl)
		var c1: Vector3 = Vector3(-0.2, -0.2, 0) + nl * 1.412
		for i in 3:
			M.dline(ps, T, c1 + Z * (5.2 + i * 1.3) - al * 1.4, c1 + Z * (5.2 + i * 1.3) + al * 1.4, C.ca(conc[1], 0.9), nl)
		RO.quad(ps, T, c1 + Z * 7.0 + al * 0.6, al * 0.3, Z * 0.06, Color8(20, 22, 24), nl)
		for j in 3:
			var u := P.hn(j, seed, 13) * 2.4 - 1.2
			M.dline(ps, T, c1 + al * u + Z * 8.7, c1 + al * u + Z * (7.4 - P.hn(j, 1, 7) * 2.0), Color(0.22, 0.21, 0.18, 0.28), nl)
	var pl := M.part(S, 2)   # caged ladder on +y
	for k2 in 8:
		M.dline(pl, T, Vector3(-0.9, 1.25, 4.9 + k2 * 0.5), Vector3(-0.3, 1.25, 4.9 + k2 * 0.5), C.ca(st[0], 1.0), Y)
	for s in [-0.95, -0.25]:
		M.dline(pl, T, Vector3(s, 1.3, 4.7), Vector3(s, 1.3, 8.8), st[2], Y)
	var pc := M.part(S, 2)   # armoured cab z 8.8..10.6, overhanging roof
	M.box(pc, T, Vector3(0, 0, 8.85), Vector3(2.05, 2.05, 0.1), cd)
	M.box(pc, T, Vector3(0, 0, 9.75), Vector3(1.75, 1.75, 0.85), arm, Vector3(0.1, 0.1, 0.0))
	for nl in [X, Y, -X, -Y]:
		var al := RO._along(nl)
		var c1: Vector3 = nl * 1.762
		M.dline(pc, T, c1 + Z * 9.1 - al * 1.7, c1 + Z * 9.1 + al * 1.7, C.ca(arm[0], 0.9), nl)
		for i in 3:   # vision blocks
			var u := -1.0 + i * 1.0
			RO.quad(pc, T, c1 + al * u + Z * 10.0, al * 0.26, Z * 0.13, Color8(26, 34, 40), nl)
			M.dline(pc, T, c1 + nl * 0.004 + al * (u - 0.2) + Z * 10.06, c1 + nl * 0.004 + al * (u + 0.05) + Z * 10.06, Color(0.75, 0.9, 1.0, 0.55), nl)
		for i in 4:   # bolted armour plate seams
			M.dline(pc, T, c1 + al * (-1.3 + i * 0.87) + Z * 9.0, c1 + al * (-1.3 + i * 0.87) + Z * 9.75, C.ca(arm[1], 0.8), nl)
	M.box(pc, T, Vector3(0, 0, 10.72), Vector3(2.15, 2.15, 0.12), cd)   # roof slab
	M.box(pc, T, Vector3(-0.9, 0.8, 10.85), Vector3(0.5, 0.5, 0.012), C.ramp(CONC), Vector3.ZERO, {"team": true})
	var pq := M.part(S, 3)   # armoured cupola + remote weapon station
	var Tr := M.sub(T, Vector3(0.6, -0.5, 10.84), 0.0)
	M.cyl(pq, Tr, Vector3(0, 0, 0.3), Z, 0.8, 0.3, 12, arm, {"cap_t": 2})
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		M.dpx(pq, Tr, Vector3(cos(a) * 0.81, sin(a) * 0.81, 0.36), Color8(26, 34, 40), Vector3(cos(a), sin(a), 0))
	M.box(pq, Tr, Vector3(0.0, 0, 0.78), Vector3(0.38, 0.28, 0.18), C.ramp(Color8(104, 112, 100)), Vector3(0.15, 0.0, 0.06))
	M.box(pq, Tr, Vector3(0.05, -0.33, 0.9), Vector3(0.1, 0.07, 0.08), C.ramp(DARK))
	M.dpx(pq, Tr, Vector3(0.16, -0.33, 0.92), GLASS, X)
	TU.barrel(pq, Tr, 0.34, 1.5, 0.0, 0.8, 0.045, 0.0, DARK, true)
	M.cyl(pq, T, Vector3(1.75, 1.45, 11.05), Vector3(1, 0.4, -0.3), 0.2, 0.18, 8, st, {"cap_t": 4})   # searchlight
	M.dpx(pq, T, Vector3(1.97, 1.53, 11.0), LAMP_W)
	M.box(pq, T, Vector3(-1.75, -1.75, 10.6), Vector3(0.18, 0.1, 0.09), C.ramp(Color8(210, 210, 200)))   # camera
	M.dpx(pq, T, Vector3(-1.55, -1.75, 10.6), Color8(60, 200, 255), X)
	M.cyl(pq, T, Vector3(-1.2, -1.2, 11.8), Z, 0.03, 0.95, 4, C.ramp(DARK), {"edge": false})
	M.dpx(pq, T, Vector3(-1.2, -1.2, 12.8), LAMP_R)
	_fin_piece(cv, S, o, seed + m)


static func build_tower(out: Dictionary) -> void:
	var co: Array = K.canvas(2, TOWER_TOP)
	var o: Vector2 = co[1]
	var fw: int = co[0].w
	var fh: int = co[0].h
	var sheet := P.Canvas.new(fw * 16, fh * 2)
	for m in 16:
		var cv = K.canvas(2, TOWER_TOP)[0]
		tower_piece(cv, o, m, 5100 + m * 7)
		var base = H.copy(cv)
		C.selout(cv)
		var dm = H.copy(base)
		K.damage(dm, o, 2, 9300 + m * 13)
		C.selout(dm)
		for row in 2:
			var src = cv if row == 0 else dm
			(sheet.img as Image).blit_rect(src.img, Rect2i(0, 0, fw, fh), Vector2i(m * fw, row * fh))
			(sheet.mask as Image).blit_rect(src.mask, Rect2i(0, 0, fw, fh), Vector2i(m * fw, row * fh))
	var entry := {"size": 2, "pivot": [int(o.x), int(o.y)], "fw": fw, "fh": fh, "states": {},
		"sheet": {"cols": "conn mask m = N1 E2 S4 W8 (tile axes)", "rows": ["intact", "damaged"]},
		"fits": "cn_tower 2x2 hardened tower in the wall ring, pivot = cell centre; 4.8 m bastion + wall arms to the cell edge on linked sides"}
	_put(out, entry, "g7_fac_tower", "sheet", sheet)
	entry.states["built"] = (entry.states["sheet"] as Dictionary).duplicate()
	out.manifest.buildings["g7_fac_tower"] = entry


# ================================================================ zone buildings (any w x h tiles)
const TOPS := {"planning": 100, "dronebay": 84, "workshop": 96, "range": 76, "lab": 96, "gate": 80, "wash": 66, "hall": 80}
## ART7F-2: 13.9c-2 entry zones (w, h tiles) used until defs_g7_facility.json carries them. PROVISIONAL.
const ENTRY_DEFAULT := {"gate_outer": [4, 2], "gate_inner": [4, 2], "apc_wash": [4, 4], "decon_hall": [5, 3]}


static func build_zone(out: Dictionary, id: String, w: int, h: int, kind: String) -> void:
	var s := int(ceil(float(w + h) * 0.5))
	var top: int = TOPS.get(kind, 90)
	var co: Array = K.canvas(s, top)
	var o: Vector2 = co[1]
	var entry := {"size": s, "pivot": [int(o.x), int(o.y)], "fw": int(co[0].w), "fh": int(co[0].h), "states": {},
		"zone": [w, h], "fits": "%s zone %dx%d tiles, pivot = zone centre; rot_<f> door side 0 +x 1 +y 2 -x 3 -y" % [kind, w, h]}
	for f in 4:
		var ex := float(w if f % 2 == 0 else h) * 2.0
		var ey := float(h if f % 2 == 0 else w) * 2.0
		for lock in [false, true]:
			var cv = K.canvas(s, top)[0]
			var S: Array = []
			var T := M.pose(o, float(f) * PI / 2.0)
			var seed := 300 + f * 17 + (5 if lock else 0) + absi(kind.hash()) % 97
			match kind:
				"planning":
					planning(S, T, ex, ey, lock, seed)
				"dronebay":
					dronebay(S, T, ex, ey, lock, seed)
				"workshop":
					workshop(S, T, ex, ey, lock, seed)
				"range":
					range_(S, T, ex, ey, lock, seed)
				"lab":
					lab(S, T, ex, ey, lock, seed)
				"gate":
					gate_layer(S, T, ex, ey, lock, seed + (31 if id.ends_with("inner") else 0))
				"wash":
					apc_wash(S, T, ex, ey, lock, seed)
				"hall":
					decon_hall(S, T, ex, ey, lock, seed)
			M.shadow(cv, S, o)
			M.render_z(cv, S, o, seed)
			C.selout(cv)
			_put(out, entry, id, "rot_%d%s" % [f, "_lockdown" if lock else ""], cv)
	entry.states["built"] = (entry.states["rot_0"] as Dictionary).duplicate()
	entry.states["lockdown"] = (entry.states["rot_0_lockdown"] as Dictionary).duplicate()
	out.manifest.buildings[id] = entry


## Zone apron: concrete slab over the whole zone, expansion joints, wear. Returns the ground part.
static func _apron(S: Array, T: Dictionary, ex: float, ey: float, seed: int, col := CONC_D) -> Dictionary:
	var pa := M.part(S, -2)
	var cd: Array = C.ramp(col)
	M.box(pa, T, Vector3(0, 0, 0.06), Vector3(ex - 0.08, ey - 0.08, 0.06), cd, Vector3(0.04, 0.04, 0.04))
	var nx := maxi(1, int(ex / 2.0))
	for i in range(1, nx):
		var t := -ex + float(i) * 2.0 * ex / nx
		M.dline(pa, T, Vector3(t, -ey + 0.2, ZS + 0.002), Vector3(t, ey - 0.2, ZS + 0.002), C.ca(cd[0], 0.5), Z)
	var ny := maxi(1, int(ey / 2.0))
	for i in range(1, ny):
		var t := -ey + float(i) * 2.0 * ey / ny
		M.dline(pa, T, Vector3(-ex + 0.2, t, ZS + 0.002), Vector3(ex - 0.2, t, ZS + 0.002), C.ca(cd[0], 0.5), Z)
	for j in int(ex * ey * 0.5):
		M.dpx(pa, T, Vector3((P.hn(j, seed, 3) - 0.5) * 2.0 * (ex - 0.3), (P.hn(j, seed, 5) - 0.5) * 2.0 * (ey - 0.3), ZS + 0.002),
			C.ca(cd[4], 0.3) if j % 3 == 0 else Color(0.1, 0.1, 0.09, 0.2), Z)
	return pa


## Building block (centre c at ground, half extents hx, hy, height hz) with dressed walls; returns [shell, roof, parapet].
static func _block(S: Array, T: Dictionary, c: Vector3, hx: float, hy: float, hz: float, col: Color, seed: int) -> Array:
	var pm := M.part(S, 0)
	var rp: Array = C.ramp(col)
	M.box(pm, T, c + Z * hz * 0.5, Vector3(hx, hy, hz * 0.5), rp, Vector3(0.06, 0.06, 0.06))
	FAC._wall(pm, T, c + X * hx, Y, hy * 2.0, hz, X, rp, seed)
	FAC._wall(pm, T, c - X * hx, Y, hy * 2.0, hz, -X, rp, seed + 1)
	FAC._wall(pm, T, c + Y * hy, X, hx * 2.0, hz, Y, rp, seed + 2)
	FAC._wall(pm, T, c - Y * hy, X, hx * 2.0, hz, -Y, rp, seed + 3)
	var pr := M.part(S, 2)
	var cd: Array = C.ramp(P.mul(col, 0.85))
	for e in [[c + Vector3(0, -hy + 0.12, hz + 0.12), Vector3(hx, 0.12, 0.12)], [c + Vector3(0, hy - 0.12, hz + 0.12), Vector3(hx, 0.12, 0.12)],
			[c + Vector3(-hx + 0.12, 0, hz + 0.12), Vector3(0.12, hy - 0.24, 0.12)], [c + Vector3(hx - 0.12, 0, hz + 0.12), Vector3(0.12, hy - 0.24, 0.12)]]:
		M.box(pr, T, e[0], e[1], cd)   # parapet
	var rf := M.part(S, 1)
	var nseam := maxi(2, int(hx / 1.8))
	for i in range(1, nseam):
		var t := c.x - hx + float(i) * 2.0 * hx / nseam
		M.dline(rf, T, Vector3(t, c.y - hy + 0.3, c.z + hz + 0.005), Vector3(t, c.y + hy - 0.3, c.z + hz + 0.005), C.ca(cd[1], 0.7), Z)
	for j in int(hx * hy * 0.6):
		M.dpx(rf, T, c + Vector3((P.hn(j, seed, 71) - 0.5) * 2.0 * (hx - 0.3), (P.hn(j, seed, 73) - 0.5) * 2.0 * (hy - 0.3), hz + 0.006), Color(0.2, 0.2, 0.18, 0.25), Z)
	return [pm, rf, pr]


## Side-face dressing at face point c (ground), along al, outward normal nl: personnel door with lamp + LED,
## louvre panel and a conduit, so every face of a block reads as a working building from any angle.
static func _side(pt: Dictionary, T: Dictionary, c: Vector3, al: Vector3, nl: Vector3, lock: bool) -> void:
	var f := c + nl * 0.012
	RO.quad(pt, T, f + Z * 1.05, al * 0.5, Z * 1.05, C.ramp(STEEL)[1], nl)
	M.dline(pt, T, f + al * 0.3 + Z * 0.95, f + al * 0.4 + Z * 0.95, C.ca(C.ramp(STEEL)[4], 0.9), nl)
	M.dpx(pt, T, f + al * 0.7 + Z * 1.3, LAMP_R if lock else GR.LED_G, nl)
	M.box(pt, T, c + nl * 0.2 + Z * 2.35, (al * 0.6 + nl * 0.2 + Z * 0.05).abs(), C.ramp(STEEL))
	M.dpx(pt, T, c + nl * 0.42 + Z * 2.28, LAMP_W)
	RO.quad(pt, T, f + al * 2.2 + Z * 2.6, al * 0.6, Z * 0.4, Color8(52, 56, 60), nl)
	for j in 4:
		M.dline(pt, T, f + al * 1.65 + Z * (2.32 + j * 0.18), f + al * 2.75 + Z * (2.32 + j * 0.18), Color8(92, 98, 102), nl)
	M.cyl(pt, T, c + nl * 0.08 - al * 1.4 + Z * 1.8, Z, 0.06, 1.7, 4, C.ramp(STEEL), {"edge": false})


## Rooftop HVAC unit with fan grille at c (roof height in c.z).
static func _hvac(pt: Dictionary, T: Dictionary, c: Vector3) -> void:
	M.box(pt, T, c + Z * 0.4, Vector3(0.7, 0.55, 0.4), C.ramp(Color8(150, 154, 156)), Vector3(0.03, 0.03, 0.03))
	M.cyl(pt, T, c + Z * 0.82, Z, 0.42, 0.02, 10, C.ramp(DARK), {"cap_t": 0})
	for k in 3:
		M.dline(pt, T, c + Vector3(-0.71, -0.4 + k * 0.4, 0.65), c + Vector3(-0.71, -0.4 + k * 0.4, 0.15), C.ca(DARK, 0.7), -X)


## Door on the +x face of a block at (x, y), half width hw, height hz: open = lit interior, lockdown = sealed red.
static func _door(S: Array, pa: Dictionary, T: Dictionary, x: float, y: float, hw: float, hz: float, lock: bool, open: bool) -> void:
	var pd := M.part(S, 1)
	var st: Array = C.ramp(STEEL)
	if lock:
		M.box(pd, T, Vector3(x + 0.05, y, hz * 0.5), Vector3(0.06, hw, hz * 0.5), C.ramp(Color8(122, 70, 58)))
		FAC._hz(pd, T, Vector3(x + 0.12, y - hw + 0.1, 0.2), Vector3(x + 0.12, y + hw - 0.1, hz - 0.2), X, 10)
		FAC._hz(pd, T, Vector3(x + 0.12, y - hw + 0.1, hz - 0.2), Vector3(x + 0.12, y + hw - 0.1, 0.2), X, 10)
		for s in [-1.0, 1.0]:
			M.dpx(pd, T, Vector3(x + 0.13, y + s * (hw + 0.25), hz - 0.1), LAMP_R, X)
	elif open:
		RO.quad(pd, T, Vector3(x + 0.012, y, hz * 0.5), Y * hw, Z * hz * 0.5, Color8(28, 30, 32), X)
		M.dline(pd, T, Vector3(x + 0.015, y - hw + 0.1, hz - 0.15), Vector3(x + 0.015, y + hw - 0.1, hz - 0.15), Color8(220, 210, 170), X)
		M.dpoly(pa, T, [Vector3(x, y - hw, ZS + 0.004), Vector3(x + 1.8, y - hw - 0.6, ZS + 0.004), Vector3(x + 1.8, y + hw + 0.6, ZS + 0.004), Vector3(x, y + hw, ZS + 0.004)], POOL, Z)
		for s in [-1.0, 1.0]:
			M.dpx(pd, T, Vector3(x + 0.13, y + s * (hw + 0.25), hz - 0.1), LAMP_G, X)
	else:
		M.box(pd, T, Vector3(x + 0.04, y, hz * 0.5), Vector3(0.04, hw, hz * 0.5), st)
		for i in int(hz / 0.3):
			M.dline(pd, T, Vector3(x + 0.085, y - hw + 0.05, 0.2 + i * 0.3), Vector3(x + 0.085, y + hw - 0.05, 0.2 + i * 0.3), C.ca(st[1], 0.9), X)
	for s in [-1.0, 1.0]:   # hazard jambs
		FAC._jamb(pd, T, Vector3(x + 0.02, y + s * (hw + 0.08), 0), X, 0.1, 0.2, hz)


# ---------------------------------------------------------------- mission planning room (hardened TOC)
## A windowless reinforced block (4.4 m) with a baffled blast-door vestibule on the door side, armoured slit
## windows lit by the briefing screens, a T-wall blast screen behind it, satcom radome, whip antennas, a lattice
## mast with a dish, HVAC and a generator skid with its fuel tank. Lockdown: door sealed, screens dark, red beacon.
static func planning(S: Array, T: Dictionary, ex: float, ey: float, lock: bool, seed: int) -> void:
	var pa := _apron(S, T, ex, ey, seed)
	var hx := minf((2.0 * ex - 5.0) * 0.5, 7.0)
	var cx := -ex + 1.6 + hx
	var hy := minf(ey - 1.6, 8.0)
	var hz := 4.4
	var parts := _block(S, T, Vector3(cx, 0, 0), hx, hy, hz, CONC, seed)
	var rf: Dictionary = parts[1]
	var xf := cx + hx
	var vb := _block(S, T, Vector3(xf + 1.1, 0, 0), 1.1, 1.9, 3.2, CONC_D, seed + 9)
	_door(S, pa, T, xf + 2.2, 0.0, 0.9, 2.5, lock, not lock)
	var pv: Dictionary = vb[0]
	RO.quad(pv, T, Vector3(xf + 2.212, 0, 2.85), Y * 1.2, Z * 0.18, SIGN, X)
	M.dline(pv, T, Vector3(xf + 2.216, -1.0, 2.75), Vector3(xf + 2.216, 1.0, 2.75), CN_BLUE, X)
	FAC._stencil(pv, T, Vector3(xf + 2.212, 0, 2.9), Y, X, 3, 0.14)
	RO.flood(pv, pa, T, Vector3(xf, -hy * 0.6, 3.9), X)
	RO.flood(pv, pa, T, Vector3(xf, hy * 0.6, 3.9), X)
	for s in [-1.0, 1.0]:   # armoured slit windows, lit by the briefing screens inside
		for k in 2:
			var wy: float = s * (3.0 + k * 2.4)
			if absf(wy) < hy - 0.9:
				RO.quad(parts[0], T, Vector3(xf + 0.012, wy, 2.9), Y * 0.8, Z * 0.22, Color8(24, 30, 36) if lock else GLASS, X)
				if not lock:
					M.dline(parts[0], T, Vector3(xf + 0.016, wy - 0.6, 2.85), Vector3(xf + 0.016, wy + 0.6, 2.85), C.ca(CN_BLUE, 0.85), X)
	for sd in [Y, -Y]:   # emergency exits on the flanks
		_side(parts[0], T, Vector3(cx - hx * 0.3, 0, 0) + sd * hy, X, sd, lock)
	var n := int((2.0 * hy) / 1.6)   # T-wall blast screen along the back
	for i in n:
		_slab(M.part(S, 0), T, Vector3(-ex + 0.75, -hy + 0.8 + i * 1.6 + (2.0 * hy - n * 1.6) * 0.5, 0), Y, i, seed)
	var pr := M.part(S, 2)
	var rc := Vector3(cx - hx * 0.45, -hy * 0.45, hz)   # satcom radome on its plinth
	M.box(pr, T, rc + Z * 0.25, Vector3(0.9, 0.9, 0.25), C.ramp(STEEL))
	M.cyl(pr, T, rc + Z * 1.35, Z, 1.0, 0.85, 12, C.ramp(Color8(214, 214, 206)), {"cap_t": 3})
	M.cyl(pr, T, rc + Z * 2.3, Z, 0.7, 0.12, 12, C.ramp(Color8(224, 224, 216)), {"cap_t": 4})
	for k in 3:   # whip antennas
		var ac := Vector3(cx - hx + 1.0 + k * 1.3, hy - 1.0, hz)
		M.cyl(pr, T, ac + Z * 0.3, Z, 0.08, 0.3, 4, C.ramp(DARK), {"edge": false})
		M.dline(pr, T, ac + Z * 0.6, ac + Z * (3.6 + k * 0.7), Color8(40, 42, 44))
		M.dpx(pr, T, ac + Z * (3.6 + k * 0.7), LAMP_R)
	var mc := Vector3(cx + hx * 0.4, hy * 0.5, hz)   # lattice mast with a microwave dish
	for k in 4:
		var z0 := 0.2 + k * 1.2
		M.dline(pr, T, mc + Vector3(-0.25, -0.25, z0), mc + Vector3(0.25, 0.25, z0 + 1.2), Color8(70, 74, 78))
		M.dline(pr, T, mc + Vector3(0.25, -0.25, z0), mc + Vector3(-0.25, 0.25, z0 + 1.2), Color8(70, 74, 78))
	M.cyl(pr, T, mc + Z * 2.6, Z, 0.06, 2.5, 4, C.ramp(STEEL), {"edge": false})
	M.cyl(pr, T, mc + Vector3(0.45, 0, 4.2), X, 0.55, 0.06, 10, C.ramp(Color8(200, 200, 194)), {"cap_t": 3})
	M.dpx(pr, T, mc + Z * 5.2, LAMP_R)
	for k in 2:
		_hvac(pr, T, Vector3(cx + hx * 0.35 - k * 2.2, -hy * 0.5, hz))
	M.box(rf, T, Vector3(cx, hy * 0.15, hz + 0.08), Vector3(hx * 0.8, 0.15, 0.06), C.ramp(STEEL))   # cable tray
	M.box(rf, T, Vector3(cx + hx * 0.2, -0.4, hz + 0.01), Vector3(1.0, 1.0, 0.012), C.ramp(CONC), Vector3.ZERO, {"team": true})
	M.cyl(pr, T, Vector3(xf - 0.4, hy - 0.4, hz + 0.2), Z, 0.15, 0.2, 6, C.ramp(LAMP_R if lock else Color8(150, 120, 70)), {"cap_t": 4})
	var gx := ex - 1.6   # generator skid + fuel tank on the front apron
	var gy := (hy + 0.2) * 0.55 + 1.2
	if gy + 1.7 < ey and gx - 0.8 > xf + 2.4:
		var pg := M.part(S, 0)
		M.box(pg, T, Vector3(gx, gy, 0.95), Vector3(0.75, 1.5, 0.8), C.ramp(OLIVE), Vector3(0.04, 0.04, 0.04))
		for k in 5:
			M.dline(pg, T, Vector3(gx + 0.76, gy - 1.1 + k * 0.5, 0.5), Vector3(gx + 0.76, gy - 1.1 + k * 0.5, 1.5), C.ca(DARK, 0.8), X)
		M.cyl(pg, T, Vector3(gx - 0.3, gy + 1.0, 2.0), Z, 0.09, 0.3, 6, C.ramp(DARK), {"cap_t": 0})
		M.dpx(pg, T, Vector3(gx + 0.77, gy + 0.9, 1.4), AMBER if lock else LAMP_G, X)
		M.cyl(M.part(S, 0), T, Vector3(gx, -gy, 0.75), Y, 0.6, 1.2, 10, C.ramp(Color8(80, 92, 74)), {"cap_t": 2})


# ---------------------------------------------------------------- overwatch drone bay
## Small hangar (roll-up door, lit bay with the drone cradle) with the launch / recovery pad in front of its door
## (the overwatch quadcopter sits on it, folded away under lockdown), a workbench under an awning, charging
## cabinets and a relay mast. Lays itself out for any zone shape (pad beside the hangar when the zone is shallow).
static func dronebay(S: Array, T: Dictionary, ex: float, ey: float, lock: bool, seed: int) -> void:
	var pa := _apron(S, T, ex, ey, seed)
	var deep := 2.0 * ex >= 15.0
	var hx := minf(4.0, (2.0 * ex - (7.2 if deep else 1.6)) * 0.5)
	var cx := -ex + 0.8 + hx
	var hy := minf(ey - 1.0, 4.4) if deep else minf(ey * 0.5 - 0.6, 4.4)
	var cy := 0.0 if deep else -ey + 0.8 + hy
	var hz := 4.0
	var parts := _block(S, T, Vector3(cx, cy, 0), hx, hy, hz, Color8(138, 140, 134), seed)
	var xf := cx + hx
	_door(S, pa, T, xf, cy, 2.0, 3.0, lock, not lock)
	RO.quad(parts[0], T, Vector3(xf + 0.012, cy, 3.5), Y * 1.6, Z * 0.2, SIGN, X)
	M.dline(parts[0], T, Vector3(xf + 0.016, cy - 1.4, 3.4), Vector3(xf + 0.016, cy + 1.4, 3.4), CN_BLUE, X)
	RO.flood(parts[0], pa, T, Vector3(xf, cy + hy - 0.6, 3.6), X)
	_hvac(parts[2], T, Vector3(cx - hx * 0.4, cy, hz))
	_side(parts[0], T, Vector3(cx - hx * 0.1, cy + hy, 0), X, Y, lock)
	_side(parts[0], T, Vector3(cx - hx, cy, 0), Y, -X, lock)
	var pc := Vector3(xf + 3.5, cy, 0) if deep else Vector3(cx, ey * 0.5 + 0.2, 0)   # launch / recovery pad
	var pp := M.part(S, -1)
	RO.quad(pp, T, pc + Z * (ZS + 0.004), X * 2.7, Y * 2.7, Color8(70, 74, 74), Z)
	for e in [[Vector3(-2.5, -2.5, 0), Vector3(2.5, -2.5, 0)], [Vector3(2.5, -2.5, 0), Vector3(2.5, 2.5, 0)], [Vector3(2.5, 2.5, 0), Vector3(-2.5, 2.5, 0)], [Vector3(-2.5, 2.5, 0), Vector3(-2.5, -2.5, 0)]]:
		M.dline(pp, T, pc + (e[0] as Vector3) + Z * (ZS + 0.006), pc + (e[1] as Vector3) + Z * (ZS + 0.006), YEL, Z)
	var ring: Array = []
	for i in 16:
		ring.append(pc + Vector3(cos(TAU * i / 16.0) * 1.6, sin(TAU * i / 16.0) * 1.6, ZS + 0.006))
	for i in 16:
		M.dline(pp, T, ring[i], ring[(i + 1) % 16], STENCIL, Z)
	M.dline(pp, T, pc + Vector3(-0.8, 0, ZS + 0.007), pc + Vector3(0.8, 0, ZS + 0.007), STENCIL, Z)
	M.dline(pp, T, pc + Vector3(0, -0.8, ZS + 0.007), pc + Vector3(0, 0.8, ZS + 0.007), STENCIL, Z)
	for s in [Vector3(-2.6, -2.6, 0), Vector3(2.6, -2.6, 0), Vector3(2.6, 2.6, 0), Vector3(-2.6, 2.6, 0)]:
		M.dpx(pp, T, pc + s + Z * 0.15, LAMP_R if lock else LAMP_G)
	if not lock:   # the overwatch quadcopter on its pad (~1.6 m span)
		var pq := M.part(S, 1)
		var gr: Array = C.ramp(Color8(70, 76, 72))
		M.box(pq, T, pc + Z * 0.42, Vector3(0.36, 0.24, 0.12), gr, Vector3(0.04, 0.04, 0.04))
		M.box(pq, T, pc + Vector3(0.28, 0, 0.3), Vector3(0.08, 0.1, 0.08), C.ramp(DARK))
		M.dpx(pq, T, pc + Vector3(0.37, 0, 0.3), Color8(60, 200, 255), X)
		for a in [Vector3(0.6, 0.6, 0), Vector3(0.6, -0.6, 0), Vector3(-0.6, 0.6, 0), Vector3(-0.6, -0.6, 0)]:
			M.dline(pq, T, pc + Z * 0.48, pc + a + Z * 0.5, Color8(40, 42, 44))
			M.cyl(pq, T, pc + a + Z * 0.56, Z, 0.42, 0.01, 10, [C.ca(DARK, 0.35), C.ca(DARK, 0.35), C.ca(DARK, 0.35), C.ca(DARK, 0.35), C.ca(DARK, 0.35)], {"cap_t": 0})
		for s in [-1.0, 1.0]:
			M.dline(pq, T, pc + Vector3(-0.3, s * 0.2, 0.3), pc + Vector3(-0.35, s * 0.32, ZS + 0.01), Color8(36, 38, 38))
			M.dline(pq, T, pc + Vector3(0.3, s * 0.2, 0.3), pc + Vector3(0.35, s * 0.32, ZS + 0.01), Color8(36, 38, 38))
	var sy := cy + hy + 0.4   # workbench under an awning on the free side
	var room := ey - sy
	if room >= 1.8:
		var bc := Vector3(cx + hx * 0.1, sy + room * 0.5, 0)
		var pw := M.part(S, 0)
		M.box(pw, T, bc + Z * 0.85, Vector3(1.6, 0.4, 0.05), C.ramp(Color8(120, 96, 64)))
		for l in [Vector3(-1.5, -0.32, 0), Vector3(1.5, -0.32, 0), Vector3(-1.5, 0.32, 0), Vector3(1.5, 0.32, 0)]:
			M.dline(pw, T, bc + l + Z * 0.8, bc + l + Z * 0.1, Color8(50, 52, 54))
		M.box(pw, T, bc + Vector3(-0.8, 0, 1.0), Vector3(0.3, 0.22, 0.1), C.ramp(Color8(70, 76, 72)))   # airframe on the bench
		M.box(pw, T, bc + Vector3(0.9, 0.1, 0.98), Vector3(0.12, 0.1, 0.08), C.ramp(Color8(150, 40, 36)))   # toolbox
		for k in 4:
			M.dpx(pw, T, bc + Vector3(0.2 + k * 0.18, -0.2, 0.93), Color8(200, 200, 190))
		var paw := M.part(S, 2)
		M.box(paw, T, bc + Z * 2.7, Vector3(2.1, minf(room * 0.5 - 0.1, 1.2), 0.05), C.ramp(Color8(96, 104, 84)))
		for l in [Vector3(-2.0, -0.9, 0), Vector3(2.0, -0.9, 0), Vector3(-2.0, 0.9, 0), Vector3(2.0, 0.9, 0)]:
			M.dline(paw, T, bc + l * Vector3(1, minf(1.0, (room * 0.5 - 0.2) / 0.9), 1) + Z * 2.65, bc + l * Vector3(1, minf(1.0, (room * 0.5 - 0.2) / 0.9), 1) + Z * 0.12, Color8(60, 64, 66))
	var ky := cy - hy - 0.6   # charging cabinets + relay mast on the other side (or behind the hangar)
	if ky - 1.0 > -ey:
		for k in 3:
			var cc := Vector3(cx - hx + 1.0 + k * 1.0, ky, 0)
			M.box(M.part(S, 0), T, cc + Z * 0.6, Vector3(0.38, 0.28, 0.6), C.ramp(Color8(110, 116, 112)), Vector3(0.02, 0.02, 0.02))
			M.dpx(M.part(S, 1), T, cc + Vector3(0.39, 0.0, 0.95), LAMP_G if not lock else LAMP_R, X)
	var mp := Vector3(cx - hx + 0.6, cy - hy + 0.6, hz)
	M.cyl(parts[2], T, mp + Z * 2.4, Z, 0.07, 2.4, 4, C.ramp(STEEL), {"edge": false})
	for k in 2:
		M.box(parts[2], T, mp + Vector3(0.12, 0.0, 3.6 + k * 0.9), Vector3(0.05, 0.22, 0.35), C.ramp(Color8(200, 200, 194)))
	M.dpx(parts[2], T, mp + Z * 4.9, LAMP_R)


# ---------------------------------------------------------------- APC workshop (repair, upgrades, drone builds)
## High-bay shed (6.5 m) set back from the zone edge (service alleys, standoff from the perimeter wall) with two
## vehicle doors sized for the 8 m strike APC (5.2 x 4.6 m): one open on a lit bay with an APC on the lift, one shut.
## Front apron: gantry crane. ART7F-2: the faces the camera sees when the door looks away are finished too: a lit
## high-bay window band on every non-door face, a painted bay sign with the team stripe, wall extraction fans, a
## compressor / parts lean-to with its own door on the back, and the yard work in the alleys (wheel stack, armour-
## plate rack, engine on a stand, parts container, oil skip, drums). Roof: clerestory, vents, beacon.
## Lockdown: both doors sealed, window band dark.
static func workshop(S: Array, T: Dictionary, ex: float, ey: float, lock: bool, seed: int) -> void:
	var pa := _apron(S, T, ex, ey, seed)
	var hx := minf((2.0 * ex - 8.6) * 0.5, 8.0)
	var cx := -ex + 3.4 + hx
	var hy := minf(ey - 3.0, 9.5)
	var hz := 6.5
	var parts := _block(S, T, Vector3(cx, 0, 0), hx, hy, hz, Color8(132, 136, 132), seed)
	var xf := cx + hx
	var xb := cx - hx
	var dy: Array = [-hy * 0.5, hy * 0.5] if hy >= 6.0 else [0.0]
	for i in dy.size():
		_door(S, pa, T, xf, float(dy[i]), 2.6, 4.6, lock, i == 0 and not lock)
		RO.quad(parts[0], T, Vector3(xf + 0.012, float(dy[i]), 5.3), Y * 1.8, Z * 0.22, SIGN, X)
		FAC._stencil(parts[0], T, Vector3(xf + 0.016, float(dy[i]), 5.3), Y, X, 2, 0.16)
		FAC._stains(pa, T, Vector3(xf + 1.4, float(dy[i]), ZS), Vector2(1.2, 2.0), 6, seed + i)
	if not lock:   # APC on the lift inside the open bay (hull, wheels, lift posts)
		var pv := M.part(S, 1)
		var hull: Array = C.ramp(P.mul(Color8(104, 112, 100), 0.62))
		var y0 := float(dy[0])
		M.box(pv, T, Vector3(xf - 1.2, y0, 1.6), Vector3(0.9, 1.4, 0.75), hull)
		M.box(pv, T, Vector3(xf - 0.5, y0, 1.15), Vector3(0.14, 1.3, 0.35), hull, Vector3(0.0, 0.0, 0.1))
		for s in [-1.0, 1.0]:
			M.cyl(pv, T, Vector3(xf - 0.8, y0 + s * 1.3, 0.75), Y, 0.48, 0.18, 8, C.ramp(Color8(36, 38, 38)), {"cap_t": 1})
			M.box(pv, T, Vector3(xf - 0.3, y0 + s * 1.8, 1.0), Vector3(0.12, 0.12, 0.9), C.ramp(GR.HAZ))
		M.dpx(pv, T, Vector3(xf - 0.37, y0 - 1.0, 1.4), LAMP_W, X)
	var pg := M.part(S, 1)   # gantry crane over the door apron
	var gx := minf(xf + 2.3, ex - 0.5)
	var gy := hy - 0.4
	for s in [-1.0, 1.0]:
		M.box(pg, T, Vector3(gx, s * gy, 2.9), Vector3(0.14, 0.14, 2.9), C.ramp(GR.HAZ))
		M.dline(pg, T, Vector3(gx, s * gy, 0.2), Vector3(gx, s * (gy - 1.0), 2.6), Color8(60, 60, 56))
	var pgb := M.part(S, 2)
	M.box(pgb, T, Vector3(gx, 0, 5.95), Vector3(0.2, gy + 0.15, 0.18), C.ramp(GR.HAZ))
	var hy0 := float(dy[dy.size() - 1])
	M.box(pgb, T, Vector3(gx, hy0, 5.5), Vector3(0.3, 0.35, 0.25), C.ramp(DARK))
	M.dline(pgb, T, Vector3(gx, hy0, 5.25), Vector3(gx, hy0, 1.9), Color8(30, 30, 30))
	M.box(M.part(S, 1), T, Vector3(gx, hy0, 1.1), Vector3(0.08, 1.0, 0.8), C.ramp(Color8(92, 100, 88)))   # armour plate on the hook
	var pm: Dictionary = parts[0]
	# high-bay window band on the back and both flanks (lit from inside), bay sign + team stripe on each
	for fc in [[Vector3(xb, 0, 0), Y, -X, hy], [Vector3(cx, hy, 0), X, Y, hx], [Vector3(cx, -hy, 0), X, -Y, hx]]:
		var c0: Vector3 = fc[0]
		var al: Vector3 = fc[1]
		var nl: Vector3 = fc[2]
		var hl: float = float(fc[3]) - 1.0
		var f0 := c0 + nl * 0.014
		RO.quad(pm, T, f0 + Z * 5.15, al * hl, Z * 0.42, Color8(22, 28, 34) if lock else GLASS, nl)
		var nm := int(hl / 0.9)
		for k in range(-nm, nm + 1):
			M.dline(pm, T, f0 + al * (k * 0.9) + Z * 4.74, f0 + al * (k * 0.9) + Z * 5.56, C.ramp(STEEL)[1], nl)
		M.dline(pm, T, f0 - al * hl + Z * 4.72, f0 + al * hl + Z * 4.72, C.ramp(STEEL)[3], nl)
		if not lock:
			M.dline(pm, T, f0 - al * (hl - 0.3) + Z * 4.95, f0 + al * (hl - 0.3) + Z * 4.95, Color(1.0, 0.86, 0.55, 0.55), nl)
		RO.quad(pm, T, f0 + al * (hl * 0.45) + Z * 3.7, al * 1.5, Z * 0.32, SIGN, nl)   # bay sign + team stripe
		FAC._stencil(pm, T, f0 + al * (hl * 0.45) + Z * 3.72, al, nl, 4, 0.2)
		M.box(pm, T, c0 + nl * 0.06 - al * (hl * 0.45) + Z * 3.7, (al * 1.2 + nl * 0.04 + Z * 0.1).abs(), C.ramp(CONC), Vector3.ZERO, {"team": true})
		RO.flood(pm, pa, T, c0 + al * (hl * 0.8) + Z * 6.0, nl)
	for k in 2:   # extraction fans high on the back wall
		var fy := -hy * 0.55 + k * 1.6
		M.cyl(pm, T, Vector3(xb - 0.12, fy, 3.0), X, 0.55, 0.12, 10, C.ramp(STEEL), {"cap_t": 0})
		M.cyl(pm, T, Vector3(xb - 0.25, fy, 3.0), X, 0.42, 0.02, 10, C.ramp(DARK), {"cap_t": 0})
		M.dline(pm, T, Vector3(xb - 0.27, fy - 0.35, 3.0), Vector3(xb - 0.27, fy + 0.35, 3.0), C.ca(STEEL, 0.8), -X)
	# compressor / parts lean-to on the back (low annex with its own door, compressor + air receiver beside it)
	var ay := hy * 0.45
	var an := _block(S, T, Vector3(xb - 1.1, ay, 0), 1.1, 2.0, 2.8, Color8(120, 124, 118), seed + 21)
	_side(an[0], T, Vector3(xb - 2.2, ay, 0), Y, -X, lock)
	var ac := Vector3(xb - 1.3, ay - 3.2, 0)
	M.box(M.part(S, 0), T, ac + Z * 0.55, Vector3(0.7, 0.5, 0.55), C.ramp(Color8(60, 92, 120)), Vector3(0.03, 0.03, 0.03))
	M.cyl(M.part(S, 0), T, ac + Vector3(0, -1.2, 0.6), Y, 0.45, 0.5, 10, C.ramp(Color8(150, 40, 36)), {"cap_t": 2})
	M.dline(M.part(S, 1), T, ac + Vector3(0.7, 0, 0.9), Vector3(xb - 0.02, ac.y, 2.2), Color8(40, 42, 44))
	var yard := M.part(S, 0)
	var sy := hy + (ey - hy) * 0.5   # +y alley: wheel stack + armour-plate rack + engine on a stand
	for k in 3:
		M.cyl(yard, T, Vector3(cx + hx * 0.6, sy, 0.3 + k * 0.38), Z, 0.6, 0.18, 10, C.ramp(Color8(34, 36, 36)), {"cap_t": 1})
	for k in 3:
		M.box(yard, T, Vector3(cx + hx * 0.1 + k * 0.28, sy, 1.0), Vector3(0.05, 0.6, 0.9), C.ramp(Color8(92, 100, 88)))
	var ep := Vector3(cx - hx * 0.4, sy, 0)
	M.box(yard, T, ep + Z * 0.35, Vector3(0.5, 0.4, 0.05), C.ramp(GR.HAZ))
	for l in [Vector3(-0.45, -0.35, 0), Vector3(0.45, -0.35, 0), Vector3(-0.45, 0.35, 0), Vector3(0.45, 0.35, 0)]:
		M.dline(yard, T, ep + l + Z * 0.33, ep + l + Z * 0.05, Color8(50, 52, 54))
	M.box(yard, T, ep + Z * 0.85, Vector3(0.45, 0.32, 0.42), C.ramp(Color8(70, 74, 72)), Vector3(0.05, 0.05, 0.05))
	M.cyl(yard, T, ep + Vector3(0.0, 0.0, 1.35), Z, 0.12, 0.12, 6, C.ramp(DARK), {"cap_t": 0})
	FAC._stains(pa, T, ep + Z * ZS, Vector2(0.8, 0.6), 3, seed + 7)
	var ny := -sy   # -y alley: 20 ft parts container, oil skip, drums
	var pc := M.part(S, 0)
	var ct: Array = C.ramp(Color8(70, 92, 110))
	M.box(pc, T, Vector3(cx - hx * 0.3, ny, 1.3), Vector3(3.0, 1.15, 1.3), ct, Vector3(0.03, 0.03, 0.03))
	for k in 10:
		var t := cx - hx * 0.3 - 2.8 + k * 0.62
		M.dline(pc, T, Vector3(t, ny + 1.16, 0.15), Vector3(t, ny + 1.16, 2.5), C.ca(ct[1], 0.8), Y)
	FAC._stencil(pc, T, Vector3(cx - hx * 0.3 + 1.5, ny + 1.16, 2.0), X, Y, 3, 0.18)
	M.box(pc, T, Vector3(cx + hx * 0.55, ny, 0.6), Vector3(1.1, 0.75, 0.6), C.ramp(Color8(150, 112, 40)), Vector3(0.12, 0.12, 0.0))
	var dcol := [Color8(150, 40, 36), Color8(64, 92, 120), Color8(60, 80, 54)]
	for k in 3:
		M.cyl(pc, T, Vector3(cx + hx * 0.85 - float(k % 2) * 0.62, ny + 0.4 - float(k / 2) * 0.62, 0.55), Z, 0.3, 0.42, 8, C.ramp(dcol[k]), {"cap_t": 3})
	for sd in [Y, -Y]:
		_side(pm, T, Vector3(cx + hx * 0.55, 0, 0) + sd * hy, X, sd, lock)
	var pr: Dictionary = parts[2]   # clerestory ridge, vents, beacon
	M.box(pr, T, Vector3(cx, 0, hz + 0.45), Vector3(hx * 0.7, 0.9, 0.45), C.ramp(Color8(120, 124, 120)))
	for s in [-1.0, 1.0]:
		RO.quad(pr, T, Vector3(cx, s * 0.912, hz + 0.45), X * hx * 0.66, Z * 0.25, GLASS, Y * s)
	for k in 3:
		M.cyl(pr, T, Vector3(cx - hx * 0.6 + k * hx * 0.6, -hy * 0.6, hz + 0.35), Z, 0.3, 0.35, 8, C.ramp(STEEL), {"cap_t": 4})
	_hvac(pr, T, Vector3(cx - hx * 0.5, hy * 0.6, hz))
	M.cyl(pr, T, Vector3(xf - 0.5, -hy + 0.5, hz + 0.25), Z, 0.16, 0.2, 6, C.ramp(LAMP_R if lock else AMBER), {"cap_t": 4})
	M.box(parts[1], T, Vector3(cx + hx * 0.3, hy * 0.3, hz + 0.01), Vector3(1.2, 1.2, 0.012), C.ramp(CONC), Vector3.ZERO, {"team": true})


# ---------------------------------------------------------------- 13.9c-2: two-layer APC entry + infantry decon hall
## Local frame for these three: +x / -x = the travel axis through the entry (rot_<f> puts +x on the zone's door side),
## +-y across it. ex / ey = half extents (m).

## Reinforced gate layer (outer or inner): two hardened gate bastions, an overhead armoured beam with the lifting
## blast door housing (door up = open; lockdown = door down, ribbed steel with a hazard foot), a rising wedge barrier
## in the lane (flush when open, raised on lockdown), stop line + rumble strip, floodlights and cameras on the posts.
static func gate_layer(S: Array, T: Dictionary, ex: float, ey: float, lock: bool, seed: int) -> void:
	var pa := _apron(S, T, ex, ey, seed, Color8(112, 112, 108))
	var zt := ZS + 0.004
	var py := ey - 1.3   # bastion centre (across)
	var lw := py - 1.3   # clear lane half width
	for s in [-1.0, 1.0]:
		var c := Vector3(0, s * py, 0)
		var pb := M.part(S, 0)
		M.box(pb, T, c + Z * 0.3, Vector3(minf(ex, 3.2), 1.45, 0.3), C.ramp(CONC_D), Vector3(0.15, 0.15, 0.0))
		M.box(pb, T, c + Z * 2.9, Vector3(minf(ex, 3.2) - 0.25, 1.25, 2.6), C.ramp(CONC), Vector3(0.04, 0.04, 0.04))
		for nl in [X, -X]:
			FAC._wall(pb, T, c + nl * (minf(ex, 3.2) - 0.25), Y, 2.5, 5.5, nl, C.ramp(CONC), seed + int(s * 5.0))
			RO.quad(pb, T, c + nl * (minf(ex, 3.2) - 0.236) + Z * 3.2 - Y * s * 0.6, Y * 0.3, Z * 0.06, Color8(20, 22, 24), nl)   # firing slit
		var inner: Vector3 = c - Y * s * 1.25
		FAC._jamb(pb, T, inner + X * 0.0, -Y * s, minf(ex, 3.2) - 0.4, 0.3, 4.8)   # hazard chevrons on the lane faces
		var pt := M.part(S, 1)
		M.box(pt, T, c + Z * 5.7, Vector3(minf(ex, 3.2) - 0.15, 1.35, 0.15), C.ramp(CONC_D))
		RO.flood(pt, pa, T, c + X * (minf(ex, 3.2) - 0.25) + Z * 5.0, X)
		M.box(pt, T, c + Vector3(-minf(ex, 3.2) + 0.4, 0, 5.95), Vector3(0.18, 0.1, 0.09), C.ramp(Color8(210, 210, 200)))   # camera
		M.dpx(pt, T, c + Vector3(-minf(ex, 3.2) + 0.2, 0, 5.95), Color8(60, 200, 255), -X)
		M.dpx(pt, T, c + Z * 5.95, LAMP_R if lock else AMBER)
	var pg := M.part(S, 2)   # overhead armoured beam + door housing
	M.box(pg, T, Vector3(0, 0, 5.75), Vector3(0.75, lw + 0.2, 0.45), C.ramp(Color8(98, 104, 98)), Vector3(0.05, 0.05, 0.05))
	RO.quad(pg, T, Vector3(0.762, 0, 5.75), Y * 2.0, Z * 0.22, SIGN, X)
	FAC._stencil(pg, T, Vector3(0.766, 0, 5.77), Y, X, 5, 0.18)
	M.dline(pg, T, Vector3(0.766, -lw, 5.4), Vector3(0.766, lw, 5.4), CN_BLUE, X)
	var st: Array = C.ramp(Color8(92, 98, 100))
	var pd := M.part(S, 1)
	if lock:   # blast door down
		M.box(pd, T, Vector3(0, 0, 2.65), Vector3(0.22, lw, 2.65), st)
		for i in 8:
			M.dline(pd, T, Vector3(0.23, -lw + 0.1, 0.5 + i * 0.6), Vector3(0.23, lw - 0.1, 0.5 + i * 0.6), C.ca(st[0], 0.9), X)
		FAC._hz(pd, T, Vector3(0.235, -lw + 0.1, 0.3), Vector3(0.235, lw - 0.1, 0.3), X, 12)
		for s in [-1.0, 1.0]:   # raised wedge barrier in front of it
			M.box(pd, T, Vector3(2.0, 0, 0.45), Vector3(0.6, lw - 0.3, 0.4), C.ramp(GR.HAZ), Vector3(0.4, 0.0, 0.0))
	else:   # door up in its housing: the bottom edge shows under the beam
		M.box(pd, T, Vector3(0, 0, 5.05), Vector3(0.2, lw, 0.28), st)
		FAC._hz(pd, T, Vector3(0.21, -lw + 0.1, 4.82), Vector3(0.21, lw - 0.1, 4.82), X, 12)
		RO.quad(pa, T, Vector3(2.0, 0, zt + 0.001), X * 0.6, Y * (lw - 0.3), Color8(70, 70, 66), Z)   # flush wedge plate
		FAC._hz(pa, T, Vector3(2.6, -lw + 0.3, zt + 0.002), Vector3(2.6, lw - 0.3, zt + 0.002), Z, 10)
	RO.quad(pa, T, Vector3(ex - 0.6, 0, zt), X * 0.12, Y * lw, Color8(230, 230, 220), Z)   # stop line
	for i in int(lw * 2.0):   # rumble strip
		RO.quad(pa, T, Vector3(-ex + 0.8, -lw + 0.5 + i * 1.0, zt), X * 0.35, Y * 0.18, YEL, Z)
	FAC._stains(pa, T, Vector3(0, 0, ZS), Vector2(ex - 0.5, lw * 0.6), 6, seed)


## APC decontamination wash zone between the gate layers: drained wash bay, two spray gantries across the lane
## (nozzle bars on the posts and the beam; mist when running), wheel-wash troughs on the wheel tracks, water tank,
## pump skid and counter-nanite agent totes on the side. Lockdown: sprays off.
static func apc_wash(S: Array, T: Dictionary, ex: float, ey: float, lock: bool, seed: int) -> void:
	var pa := _apron(S, T, ex, ey, seed, Color8(104, 108, 108))
	var zt := ZS + 0.004
	var lw := minf(ey - 2.4, 3.2)   # lane half width (an APC is ~3 m wide)
	var ly := -(ey - lw - 2.4) * 0.5 if ey - lw > 3.0 else 0.0   # lane offset: room for the plant on +y
	RO.quad(pa, T, Vector3(0, ly, zt), X * (ex - 0.2), Y * lw, Color8(88, 94, 98), Z)
	for i in int(ex * 2.0 - 1.0):   # centre drain grate
		RO.quad(pa, T, Vector3(-ex + 0.8 + i * 1.0, ly, zt + 0.001), X * 0.4, Y * 0.18, Color8(40, 44, 46), Z)
	for s in [-1.0, 1.0]:   # wheel-wash troughs + wet sheen
		RO.quad(pa, T, Vector3(0, ly + s * 1.3, zt + 0.001), X * (ex - 1.2), Y * 0.45, Color(0.35, 0.55, 0.7, 0.55), Z)
		M.dline(pa, T, Vector3(-ex + 1.2, ly + s * 1.3 - 0.45, zt + 0.002), Vector3(ex - 1.2, ly + s * 1.3 - 0.45, zt + 0.002), YEL, Z)
	for j in 8:
		var p := Vector3((P.hn(j, seed, 3) - 0.5) * 2.0 * (ex - 1.0), ly + (P.hn(j, seed, 5) - 0.5) * 2.0 * (lw - 0.4), zt + 0.002)
		M.dpoly(pa, T, [p + Vector3(-0.5, -0.2, 0), p + Vector3(0.4, -0.3, 0), p + Vector3(0.6, 0.2, 0), p + Vector3(-0.3, 0.35, 0)], Color(0.55, 0.75, 0.9, 0.18), Z)
	var st: Array = C.ramp(Color8(180, 184, 186))
	for gx in [-ex * 0.45, ex * 0.45]:   # spray gantries
		var pg := M.part(S, 1)
		for s in [-1.0, 1.0]:
			M.box(pg, T, Vector3(gx, ly + s * (lw + 0.25), 2.2), Vector3(0.14, 0.14, 2.2), st)
			for k in 6:
				M.dpx(pg, T, Vector3(gx, ly + s * (lw + 0.1), 0.5 + k * 0.6), Color8(40, 60, 80), -Y * s)
		M.box(M.part(S, 2), T, Vector3(gx, ly, 4.45), Vector3(0.16, lw + 0.4, 0.14), st)
		M.box(M.part(S, 2), T, Vector3(gx, ly, 4.7), Vector3(0.1, lw * 0.6, 0.1), C.ramp(CN_BLUE))   # agent manifold
		for k in int(lw * 2.0):
			M.dpx(M.part(S, 2), T, Vector3(gx, ly - lw + 0.5 + k * 1.0, 4.28), Color8(40, 60, 80))
		if not lock:   # mist curtain
			var pm := M.part(S, 2, 0.5)
			for k in 5:
				var yy := ly - lw + 0.6 + k * (2.0 * lw - 1.2) / 4.0
				M.dpoly(pm, T, [Vector3(gx, yy, 4.25), Vector3(gx + 0.6, yy - 0.5, 0.3), Vector3(gx - 0.6, yy + 0.5, 0.3)], Color(0.82, 0.92, 1.0, 0.16), X)
			M.dpx(pm, T, Vector3(gx, ly + lw + 0.3, 4.0), LAMP_G)
		else:
			M.dpx(M.part(S, 2), T, Vector3(gx, ly + lw + 0.3, 4.0), LAMP_R)
	var sy := ly + lw + 1.3   # plant on the +y side
	if sy + 1.0 < ey:
		var pp := M.part(S, 0)
		M.cyl(pp, T, Vector3(-ex * 0.45, sy, 1.6), Z, 1.0, 1.5, 12, C.ramp(Color8(196, 200, 204)), {"cap_t": 3})   # water tank
		M.cyl(M.part(S, 1), T, Vector3(-ex * 0.45, sy, 1.6), Z, 1.02, 0.08, 12, C.ramp(CN_BLUE), {"cap_t": 0})
		M.box(pp, T, Vector3(ex * 0.1, sy, 0.6), Vector3(0.8, 0.6, 0.55), C.ramp(Color8(60, 92, 120)), Vector3(0.03, 0.03, 0.03))   # pump skid
		M.dpx(pp, T, Vector3(ex * 0.1 + 0.82, sy, 0.9), LAMP_R if lock else LAMP_G, X)
		for k in 2:   # agent IBC totes
			var tc := Vector3(ex * 0.55 + k * 1.3, sy, 0.6)
			M.box(pp, T, tc, Vector3(0.55, 0.5, 0.55), C.ramp(Color8(214, 220, 226)), Vector3(0.02, 0.02, 0.02))
			M.dline(pp, T, tc + Vector3(0.56, -0.5, 0.2), tc + Vector3(0.56, 0.5, 0.2), CN_BLUE, X)
		M.dline(M.part(S, 1), T, Vector3(ex * 0.1, sy - 0.6, 0.9), Vector3(ex * 0.1, ly + lw + 0.25, 0.4), Color8(40, 42, 44))


## Infantry decontamination hall: a long hall on the infantry path, dirty entry vestibule under a canopy on the
## door side (hazard floor, gear drop bins), clean exit door at the far end (green line), frosted window band with the
## shower lights, extraction stacks with filter housings, roof water tank, a drained wash-down apron.
static func decon_hall(S: Array, T: Dictionary, ex: float, ey: float, lock: bool, seed: int) -> void:
	var pa := _apron(S, T, ex, ey, seed)
	var hx := minf(ex - 2.2, 9.0)
	var cx := -ex + 0.6 + hx
	var hy := minf(ey - 1.2, 4.5)
	var hz := 4.2
	var parts := _block(S, T, Vector3(cx, 0, 0), hx, hy, hz, Color8(176, 180, 178), seed)
	var xf := cx + hx
	var xb := cx - hx
	_door(S, pa, T, xf, 0.0, 1.0, 2.4, lock, not lock)   # dirty entry
	var pc := M.part(S, 2)   # entry canopy
	M.box(pc, T, Vector3(xf + 0.9, 0, 3.0), Vector3(0.95, 1.8, 0.06), C.ramp(Color8(96, 104, 84)))
	for s in [-1.0, 1.0]:
		M.dline(pc, T, Vector3(xf + 1.75, s * 1.7, 2.95), Vector3(xf + 1.75, s * 1.7, 0.15), Color8(60, 64, 66))
	for i in 6:   # hazard floor of the dirty side
		M.dline(pa, T, Vector3(xf + 0.2 + i * 0.3, -1.6, ZS + 0.005), Vector3(xf + 0.2 + i * 0.3 + 0.4, 1.6, ZS + 0.005), GR.HAZ if i % 2 == 0 else GR.HAZ_D, Z)
	for k in 2:   # gear drop bins
		M.cyl(M.part(S, 0), T, Vector3(xf + 1.2, 2.4 + k * 0.7, 0.5), Z, 0.3, 0.42, 8, C.ramp(Color8(214, 176, 40)), {"cap_t": 3})
		M.dpx(M.part(S, 1), T, Vector3(xf + 1.5, 2.4 + k * 0.7, 0.6), CN_BLUE, X)
	var pm: Dictionary = parts[0]
	RO.quad(pm, T, Vector3(xf + 0.012, 0, 3.45), Y * 1.6, Z * 0.22, SIGN, X)
	FAC._stencil(pm, T, Vector3(xf + 0.016, 0, 3.47), Y, X, 5, 0.17)
	M.dline(pm, T, Vector3(xf + 0.016, -hy + 0.3, 3.95), Vector3(xf + 0.016, hy - 0.3, 3.95), CN_BLUE, X)
	for sd in [Y, -Y]:   # frosted window band with shower lights
		var f0: Vector3 = Vector3(cx, 0, 0) + sd * (hy + 0.014)
		RO.quad(pm, T, f0 + Z * 2.7, X * (hx - 1.0), Z * 0.28, Color8(150, 170, 180) if not lock else Color8(40, 46, 52), sd)
		for k in int(hx):
			M.dline(pm, T, f0 + X * (-hx + 1.0 + k * 2.0) + Z * 2.42, f0 + X * (-hx + 1.0 + k * 2.0) + Z * 2.98, C.ramp(STEEL)[1], sd)
	_side(pm, T, Vector3(xb, 0, 0), Y, -X, lock)   # clean exit
	M.dline(pa, T, Vector3(xb - 0.3, -1.0, ZS + 0.005), Vector3(xb - 0.3, 1.0, ZS + 0.005), LAMP_G, Z)
	var pr: Dictionary = parts[2]
	for k in 3:   # extraction stacks with filter housings
		var sc := Vector3(cx - hx * 0.6 + k * hx * 0.6, -hy * 0.5, hz)
		M.box(pr, T, sc + Z * 0.35, Vector3(0.45, 0.45, 0.35), C.ramp(Color8(150, 154, 156)))
		M.cyl(pr, T, sc + Z * 1.4, Z, 0.18, 0.7, 8, C.ramp(STEEL), {"cap_t": 2})
	M.cyl(pr, T, Vector3(cx + hx * 0.4, hy * 0.4, hz + 0.9), Z, 0.8, 0.8, 12, C.ramp(Color8(200, 204, 206)), {"cap_t": 3})   # water tank
	_hvac(pr, T, Vector3(cx - hx * 0.3, hy * 0.45, hz))
	M.box(parts[1], T, Vector3(cx, 0, hz + 0.01), Vector3(1.0, 1.0, 0.012), C.ramp(CONC), Vector3.ZERO, {"team": true})
	for j in int(hx * 2.0):   # wash-down drain along the flank
		RO.quad(pa, T, Vector3(cx - hx + 0.5 + j * 1.0, hy + 0.5, ZS + 0.005), X * 0.35, Y * 0.12, Color8(40, 44, 46), Z)


# ---------------------------------------------------------------- simulation range (drills vs Machine replicas)
## Earth berm behind the target line, low side berms, a roofless kill house with an overwatch catwalk, firing lanes
## with Machine replica targets (quadruped frames with sensor eyes), a firing line with mats, and the range control
## tower with the red range flag. Lockdown (base not secure): targets dropped, flag down, red lamp.
static func range_(S: Array, T: Dictionary, ex: float, ey: float, lock: bool, seed: int) -> void:
	var pa := _apron(S, T, ex, ey, seed, Color8(128, 116, 90))
	var earth: Array = C.ramp(EARTH)
	M.box(M.part(S, 0), T, Vector3(-ex + 1.5, 0, 1.1), Vector3(1.4, ey - 0.4, 1.1), earth, Vector3(1.0, 1.0, 0.0))
	for s in [-1.0, 1.0]:
		M.box(M.part(S, 0), T, Vector3(0.4, s * (ey - 0.5), 0.5), Vector3(ex - 2.6, 0.45, 0.5), earth, Vector3(0.0, 0.0, 0.3))
	var psc := M.part(S, 1)
	for j in int(ey * 3.0):   # scrub on the berm
		M.dpx(psc, T, Vector3(-ex + 1.5 + (P.hn(j, seed, 3) - 0.5) * 1.2, (P.hn(j, seed, 5) - 0.5) * 2.0 * (ey - 0.8), 2.2), Color8(84, 96, 58))
	var kx0 := -ex + 3.6   # kill house on the -y half
	var kx1 := ex - 2.8
	var ky0 := -ey + 1.2
	var ky1 := -0.8
	if kx1 - kx0 > 4.0 and ky1 - ky0 > 3.0:
		var pk := M.part(S, 0)
		var kw: Array = C.ramp(Color8(140, 136, 124))
		var mx := (kx0 + kx1) * 0.5
		var my := (ky0 + ky1) * 0.5
		var hxk := (kx1 - kx0) * 0.5
		var hyk := (ky1 - ky0) * 0.5
		var walls := [[Vector3(mx, ky0, 1.2), Vector3(hxk, 0.12, 1.2)], [Vector3(mx - 0.8, ky1, 1.2), Vector3(hxk - 0.8, 0.12, 1.2)],
			[Vector3(kx0, my, 1.2), Vector3(0.12, hyk, 1.2)], [Vector3(kx1, my - 0.6, 1.2), Vector3(0.12, hyk - 0.6, 1.2)],
			[Vector3(mx, ky0 + hyk * 0.6, 1.2), Vector3(0.12, hyk * 0.6, 1.2)], [Vector3(kx0 + hxk * 0.6, my + 0.6, 1.2), Vector3(hxk * 0.36, 0.12, 1.2)]]
		for wl in walls:
			M.box(pk, T, wl[0], wl[1], kw)
		var pc := M.part(S, 2)   # overwatch catwalk across the middle (grating on posts, railing)
		RO.quad(pc, T, Vector3(mx, my, 3.2), X * hxk, Y * 0.45, Color8(90, 96, 100), Z)
		for k in 3:
			var px := kx0 + (kx1 - kx0) * (0.15 + k * 0.35)
			M.dline(pc, T, Vector3(px, my - 0.4, 3.2), Vector3(px, my - 0.4, 0.2), Color8(70, 74, 78))
			M.dline(pc, T, Vector3(px, my + 0.4, 3.2), Vector3(px, my + 0.4, 0.2), Color8(70, 74, 78))
		for s in [-1.0, 1.0]:
			M.dline(pc, T, Vector3(kx0, my + s * 0.45, 4.1), Vector3(kx1, my + s * 0.45, 4.1), GR.HAZ)
	var nl := 3   # firing lanes on the +y half: targets in front of the berm, firing line at the door side
	var lw := (ey - 1.4) / float(nl)
	for i in nl:
		var ly := 0.4 + lw * (float(i) + 0.5)
		var tp := Vector3(-ex + 3.4, ly, 0)
		var pt := M.part(S, 1)
		var mk: Array = C.ramp(Color8(54, 56, 60))
		if lock:   # dropped
			M.box(pt, T, tp + Z * 0.25, Vector3(0.5, 0.6, 0.15), mk)
		else:
			M.box(pt, T, tp + Z * 1.1, Vector3(0.45, 0.35, 0.3), mk, Vector3(0.06, 0.06, 0.06))
			M.box(pt, T, tp + Vector3(0.4, 0, 1.35), Vector3(0.18, 0.2, 0.15), mk)
			M.dpx(pt, T, tp + Vector3(0.6, 0.06, 1.38), Color8(255, 60, 40), X)
			M.dpx(pt, T, tp + Vector3(0.6, -0.06, 1.38), Color8(255, 60, 40), X)
			for l in [Vector3(0.6, 0.6, 0), Vector3(0.6, -0.6, 0), Vector3(-0.6, 0.6, 0), Vector3(-0.6, -0.6, 0)]:
				M.dline(pt, T, tp + l * 0.4 + Z * 1.0, tp + l * 0.9 + Z * 1.3, Color8(40, 42, 46))
				M.dline(pt, T, tp + l * 0.9 + Z * 1.3, tp + l * 1.2 + Z * 0.15, Color8(40, 42, 46))
		if i > 0:
			RO.quad(pa, T, Vector3(0.0, ly - lw * 0.5, ZS + 0.004), X * (ex - 2.8), Y * 0.06, STENCIL, Z)
		RO.quad(pa, T, Vector3(ex - 3.0, ly, ZS + 0.005), X * 0.6, Y * 0.35, Color8(52, 60, 50), Z)   # firing mat
	RO.quad(pa, T, Vector3(ex - 3.8, ey * 0.5, ZS + 0.006), X * 0.08, Y * (ey * 0.5 - 0.6), Color8(220, 60, 50), Z)   # firing line
	var tc := Vector3(ex - 1.5, ey - 1.6, 0)   # range control tower (cabin on legs, flag pole)
	var ptw := M.part(S, 0)
	for l in [Vector3(-0.9, -0.9, 0), Vector3(0.9, -0.9, 0), Vector3(-0.9, 0.9, 0), Vector3(0.9, 0.9, 0)]:
		M.box(ptw, T, tc + l + Z * 1.6, Vector3(0.1, 0.1, 1.6), C.ramp(STEEL))
	M.box(ptw, T, tc + Z * 4.1, Vector3(1.15, 1.15, 0.9), C.ramp(Color8(150, 146, 132)), Vector3(0.04, 0.04, 0.04))
	M.box(ptw, T, tc + Z * 5.08, Vector3(1.35, 1.35, 0.08), C.ramp(DARK))
	for n2 in [X, -Y, Y, -X]:
		RO.quad(ptw, T, tc + n2 * 1.152 + Z * 4.3, RO._along(n2) * 0.85, Z * 0.32, GLASS, n2)
	var pf := M.part(S, 2)
	var fp := tc + Vector3(0.9, -0.9, 5.1)
	M.dline(pf, T, fp, fp + Z * 2.4, Color8(200, 200, 196))
	if not lock:
		M.dpoly(pf, T, [fp + Z * 2.35, fp + Vector3(0, -0.9, 2.2), fp + Vector3(0, -0.85, 1.75), fp + Z * 1.85], Color8(220, 40, 30), X)
	M.dpx(pf, T, tc + Vector3(1.16, 0, 4.7), LAMP_R if lock else LAMP_G, X)


# ---------------------------------------------------------------- package lab
## Clean-room block with an airlock entry, a loading-dock door, counter-nanite agent tanks with hazard bands and
## fume stacks. Lockdown: doors sealed, red lamps.
static func lab(S: Array, T: Dictionary, ex: float, ey: float, lock: bool, seed: int) -> void:
	var pa := _apron(S, T, ex, ey, seed)
	var hx := minf((2.0 * ex - 4.2) * 0.5, 8.0)
	var cx := -ex + 0.8 + hx
	var hy := minf(ey - 2.8, 8.0)
	var hz := 5.0
	var parts := _block(S, T, Vector3(cx, -1.0, 0), hx, hy, hz, Color8(176, 178, 174), seed)
	var xf := cx + hx
	_door(S, pa, T, xf, -1.0 - hy * 0.45, 1.8, 3.4, lock, false)
	_block(S, T, Vector3(xf + 0.9, -1.0 + hy * 0.45, 0), 0.9, 1.2, 3.0, Color8(160, 164, 160), seed + 5)
	_door(S, pa, T, xf + 1.8, -1.0 + hy * 0.45, 0.7, 2.3, lock, not lock)
	M.dline(parts[0], T, Vector3(xf + 0.016, -1.0 - hy + 0.4, 4.2), Vector3(xf + 0.016, -1.0 + hy - 0.4, 4.2), CN_BLUE, X)
	var ty := -1.0 + hy + 1.4   # agent tanks along the +y side
	for k in 3:
		var tp := Vector3(cx - hx + 1.4 + k * 2.2, ty, 0)
		M.cyl(M.part(S, 0), T, tp + Z * 1.9, Z, 0.9, 1.8, 12, C.ramp(Color8(214, 220, 226)), {"cap_t": 3})
		for zz in [0.8, 3.0]:
			M.cyl(M.part(S, 1), T, tp + Z * zz, Z, 0.92, 0.08, 12, C.ramp(GR.HAZ), {"cap_t": 0})
		M.dpx(M.part(S, 1), T, tp + Vector3(0.0, 0.93, 2.0), CN_BLUE, Y)
	for k in 2:
		M.cyl(parts[2], T, Vector3(cx - hx * 0.5 + k * 2.0, -1.0 - hy * 0.4, hz + 1.6), Z, 0.22, 1.6, 8, C.ramp(STEEL), {"cap_t": 2})
	_hvac(parts[2], T, Vector3(cx + hx * 0.4, -1.0, hz))


# ================================================================ dropship landing site (6 x 6 tiles = 24 m, flat)
## a_g7_vtol_pad: the XL VTOL / stealth dropship site. Kerbed concrete pad, FATO dashed edge, yellow TLOF square,
## touchdown circle, landing-direction arrow toward the approach side (+x at rot_0), green perimeter lights, white
## approach light bars running out along the approach edge, angled blast deflector fences on the two flanks, tie-
## downs, and the craft fan scorch circles. Everything stays under ~1.6 m. States rot_<f> (+ _damaged, _build_<n>).
const VPAD_TOP := 30


static func vtol_pad(cv, o: Vector2, f: int, opt: Dictionary) -> void:
	var S: Array = []
	var T := M.pose(o, float(f) * PI / 2.0)
	var e := 11.9
	var pa := _apron(S, T, e + 0.08, e + 0.08, 77 + f, Color8(112, 114, 112))
	var zt := ZS + 0.004
	for i in 26:   # FATO edge (white dashes)
		var a := -11.2 + i * 0.88
		for sg in [[Vector3(a, -11.2, zt), Vector3(a + 0.5, -11.2, zt)], [Vector3(a, 11.2, zt), Vector3(a + 0.5, 11.2, zt)], [Vector3(-11.2, a, zt), Vector3(-11.2, a + 0.5, zt)], [Vector3(11.2, a, zt), Vector3(11.2, a + 0.5, zt)]]:
			M.dline(pa, T, sg[0], sg[1], STENCIL, Z)
	var tl := 9.6
	for sg in [[Vector3(-tl, -tl, zt), Vector3(tl, -tl, zt)], [Vector3(tl, -tl, zt), Vector3(tl, tl, zt)], [Vector3(tl, tl, zt), Vector3(-tl, tl, zt)], [Vector3(-tl, tl, zt), Vector3(-tl, -tl, zt)]]:
		M.dline(pa, T, sg[0], sg[1], YEL, Z)
		M.dline(pa, T, (sg[0] as Vector3) * 0.985, (sg[1] as Vector3) * 0.985, YEL, Z)
	var ring: Array = []
	for i in 24:
		ring.append(Vector3(cos(TAU * i / 24.0) * 5.2, sin(TAU * i / 24.0) * 5.2, zt))
	for i in 24:
		M.dline(pa, T, ring[i], ring[(i + 1) % 24], YEL, Z)
	M.dpoly(pa, T, [Vector3(-8.4, 0, zt), Vector3(-6.6, 1.1, zt), Vector3(-6.6, 0.4, zt), Vector3(-5.8, 0.4, zt), Vector3(-5.8, -0.4, zt), Vector3(-6.6, -0.4, zt), Vector3(-6.6, -1.1, zt)], STENCIL, Z)   # landing direction = nose, away from the approach
	for fc in [Vector3(-5.28, -4.44, 1.0), Vector3(-5.28, 4.44, 1.0), Vector3(2.4, -7.12, 1.24), Vector3(2.4, 7.12, 1.24)]:   # craft nose -x, ramp +x
		var soot: Array = []
		for i in 12:
			soot.append(Vector3(fc.x + cos(TAU * i / 12.0) * fc.z * 1.5, fc.y + sin(TAU * i / 12.0) * fc.z * 1.5, zt - 0.001))
		M.dpoly(pa, T, soot, Color(0.08, 0.08, 0.07, 0.22), Z)
	for k in 8:   # tie-down rings
		var tx := -6.0 + float(k % 4) * 4.0
		M.dpx(pa, T, Vector3(tx, -2.5 if k < 4 else 2.5, zt + 0.001), Color8(40, 42, 42), Z)
	var pl := M.part(S, -1)   # perimeter lights (green), approach bars (white) out along +x
	for i in 8:
		var a := -11.6 + i * (23.2 / 7.0)
		for p in [Vector3(a, -11.45, 0.18), Vector3(a, 11.45, 0.18), Vector3(-11.6, a, 0.18)]:
			M.dpx(pl, T, p, LAMP_G)
	for i in 4:
		var bx := 11.75 - 0.2 - float(i) * 0.0
		var by := -3.0 + float(i) * 2.0
		M.box(pl, T, Vector3(bx, by, 0.16), Vector3(0.12, 0.6, 0.04), C.ramp(STEEL))
		M.dpx(pl, T, Vector3(bx + 0.13, by - 0.3, 0.2), LAMP_W, X)
		M.dpx(pl, T, Vector3(bx + 0.13, by + 0.3, 0.2), LAMP_W, X)
	for s in [-1.0, 1.0]:   # blast deflector fences on the flanks (angled steel panels on struts)
		var pd := M.part(S, 0)
		for k in 6:
			var px := -9.0 + k * 3.4
			M.box(pd, T, Vector3(px, s * 11.8, 0.8), Vector3(1.65, 0.08, 0.75), C.ramp(Color8(108, 112, 108)), Vector3(0.0, 0.0, 0.0))
			M.dline(pd, T, Vector3(px - 1.6, s * 11.72, 1.5), Vector3(px + 1.6, s * 11.72, 1.5), YEL, Y * s)
			M.dline(pd, T, Vector3(px, s * 11.98, 0.1), Vector3(px, s * 11.9, 1.3), Color8(60, 62, 62))
	_fin_piece(cv, S, o, 77 + f)


static func build_vtol_pad(out: Dictionary) -> void:
	var size := 6
	var co: Array = K.canvas(size, VPAD_TOP)
	var o: Vector2 = co[1]
	var entry := {"size": size, "pivot": [int(o.x), int(o.y)], "fw": int(co[0].w), "fh": int(co[0].h), "states": {},
		"g6": {"variants": "rot", "faction": "a"}, "flat": true,
		"fits": "6x6-tile (24 m) dropship site for g7_a_vtol_dropship_xl / g7_cn_stealth_dropship (craft centred, nose away from the approach bars, rear ramp toward the approach lane); rot_<f> approach side 0 +x 1 +y 2 -x 3 -y"}
	for f in 4:
		var cv = K.canvas(size, VPAD_TOP)[0]
		vtol_pad(cv, o, f, {})
		var base = H.copy(cv)
		C.selout(cv)
		_put(out, entry, "a_g7_vtol_pad", "rot_%d" % f, cv)
		var dm = H.copy(base)
		K.damage(dm, o, size, 5300 + f * 13)
		C.selout(dm)
		_put(out, entry, "a_g7_vtol_pad", "rot_%d_damaged" % f, dm)
		for st in 3:
			_put(out, entry, "a_g7_vtol_pad", "rot_%d_build_%d" % [f, st], H.stage(base, o, f, size, "a", st, 5300 + f))
	for nm in ["built", "damaged", "build_0", "build_1", "build_2"]:
		var src: String = "rot_0" if nm == "built" else "rot_0_" + nm
		entry.states[nm] = (entry.states[src] as Dictionary).duplicate()
	out.manifest.buildings["a_g7_vtol_pad"] = entry
