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
			["apc_wash", "g7_fac_wash", "wash"], ["decon_hall", "g7_fac_deconhall", "hall"],
			# FACB7-2 (13.9c-6): special ammo magazine, armory + suit bay, aid station + quarantine bay, Sentinel
			# barracks, fuel / rearm apron, wash runoff tank
			["magazine", "g7_fac_magazine", "magazine"], ["armory", "g7_fac_armory", "armory"], ["aid_station", "g7_fac_aid", "aid"],
			["barracks", "g7_fac_barracks", "barracks"], ["fuel_point", "g7_fac_fuel", "fuel"], ["runoff", "g7_fac_runoff", "runoff"]]:
		var r: Array = c.get(z[0], [])
		if r.size() == 4:
			build_zone(out, String(z[1]), int(r[2]), int(r[3]), String(z[2]))
		elif ENTRY_DEFAULT.has(z[0]):   # 13.9c-2 zones not in the json yet: PROVISIONAL default size (re-run after BASE7-3)
			var d: Array = ENTRY_DEFAULT[z[0]]
			build_zone(out, String(z[1]), int(d[0]), int(d[1]), String(z[2]))
			out.manifest.buildings[String(z[1])]["provisional"] = true
	build_vtol_pad(out)
	build_gatehouse(out)   # FACB7-2 (13.9c-8): foot entry control point (cn_checkpoint)
	build_linkwall(out)    # FACB7-2 (13.9c-9): enclosed APC wash link walls (cn_link_wall)
	build_baffle(out)      # FACB7-2 (13.9c-8): ECP serpentine baffles (cn_ecp_baffle)
	build_locker(out)      # FACB7-2 (13.9c-11): ready-ammo lockers (cn_ammo_locker)
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
	# FACB7-2 (LIFE7-2): the static roof RWS is gone; LIFE7's tracking cupola gun draws on this ring (fac_life7.gd)
	M.cyl(pq, Tr, Vector3(0, 0, 0.62), Z, 0.42, 0.03, 10, C.ramp(DARK), {"cap_t": 0})   # turret race
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
const TOPS := {"planning": 230, "dronebay": 84, "workshop": 96, "range": 130, "lab": 96, "gate": 80, "wash": 66, "hall": 80,
	"magazine": 76, "armory": 92, "aid": 80, "barracks": 160, "fuel": 30, "runoff": 46}
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
		for mode in ([0, 1, 2] if RUIN_KINDS.has(kind) else [0, 1]):   # FACB7-2: 2 = ruin (sim part destroyed)
			var lock: bool = mode == 1
			_ruin = mode == 2
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
				"magazine":
					magazine(S, T, ex, ey, lock, seed)
				"armory":
					armory(S, T, ex, ey, lock, seed)
				"aid":
					aid_station(S, T, ex, ey, lock, seed)
				"barracks":
					barracks(S, T, ex, ey, lock, seed)
				"fuel":
					fuel_point(S, T, ex, ey, lock, seed)
				"runoff":
					runoff(S, T, ex, ey, lock, seed)
			M.shadow(cv, S, o)
			M.render_z(cv, S, o, seed)
			C.selout(cv)
			_put(out, entry, id, "rot_%d%s" % [f, ["", "_lockdown", "_ruin"][mode]], cv)
	_ruin = false
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


# ---------------------------------------------------------------- FACB7-4 (owner 13.9c-14) shared helpers
## Ribbon window band on a face (f = face point at ground, along al, outward nl, length ln, from z0 to z1): dark reveal,
## armoured blue-grey glass with lit screens / desk light behind it, reflections and a sill; lockdown: slatted armour.
static func _ribbon(pt: Dictionary, T: Dictionary, f: Vector3, al: Vector3, nl: Vector3, ln: float, z0: float, z1: float, lock: bool, seed: int) -> void:
	var c := f + nl * 0.012
	var zc := (z0 + z1) * 0.5
	var hz := (z1 - z0) * 0.5
	RO.quad(pt, T, c + Z * zc, al * ln * 0.5, Z * (hz + 0.07), Color8(24, 28, 32), nl)
	if lock:
		RO.quad(pt, T, c + nl * 0.004 + Z * zc, al * (ln * 0.5 - 0.05), Z * hz, Color8(84, 90, 94), nl)
		for i in int(hz * 2.0 / 0.24):
			var zz := z0 + 0.12 + i * 0.24
			M.dline(pt, T, c + nl * 0.008 - al * (ln * 0.5 - 0.05) + Z * zz, c + nl * 0.008 + al * (ln * 0.5 - 0.05) + Z * zz, Color8(58, 62, 66), nl)
		return
	RO.quad(pt, T, c + nl * 0.004 + Z * zc, al * (ln * 0.5 - 0.05), Z * hz, Color8(34, 56, 72), nl)
	var n := maxi(1, int(ln / 1.4))
	for k in n:
		var u := -ln * 0.5 + (k + 0.5) * ln / n
		var h := P.hn(k, seed, 17)
		if h < 0.6:
			RO.quad(pt, T, c + nl * 0.006 + al * u + Z * (z0 + hz * 0.75), al * 0.42, Z * hz * 0.42, C.ca(CN_BLUE, 0.6) if h < 0.35 else C.ca(LAMP_W, 0.5), nl)
		M.dline(pt, T, c + nl * 0.008 + al * (u - 0.35) + Z * (z1 - 0.08), c + nl * 0.008 + al * (u + 0.05) + Z * (z1 - 0.55), Color(1, 1, 1, 0.3), nl)
	M.dline(pt, T, c + nl * 0.008 - al * ln * 0.5 + Z * (z0 - 0.06), c + nl * 0.008 + al * ln * 0.5 + Z * (z0 - 0.06), C.ca(Color8(204, 202, 194), 0.85), nl)


## Floor-edge band at height z around a block (centre c, half extents hx, hy): a proud slab nose with a cyan LED line
## (red under lockdown).
static func _band(pt: Dictionary, T: Dictionary, c: Vector3, hx: float, hy: float, z: float, lock: bool, col: Color) -> void:
	M.box(pt, T, Vector3(c.x, c.y, z), Vector3(hx + 0.1, hy + 0.1, 0.13), C.ramp(col))
	for nl in [X, Y, -X, -Y]:
		var al := RO._along(nl)
		var ln: float = (hy if absf(nl.x) > 0.5 else hx) + 0.1
		var fc: Vector3 = Vector3(c.x, c.y, 0) + nl * ((hx if absf(nl.x) > 0.5 else hy) + 0.112)
		M.dline(pt, T, fc - al * ln + Z * (z - 0.08), fc + al * ln + Z * (z - 0.08), C.ca(LAMP_R, 0.8) if lock else C.ca(Color8(120, 220, 255), 0.9), nl)


## Vertical blast / sun fins along a face (f = face point at ground), every step metres, from z0 to z1, depth dp.
static func _fins(pt: Dictionary, T: Dictionary, f: Vector3, al: Vector3, nl: Vector3, ln: float, z0: float, z1: float, step: float, dp: float, col: Color) -> void:
	var n := maxi(1, int(ln / step))
	for k in range(0, n + 1):
		var u := -ln * 0.5 + k * ln / float(n)
		M.box(pt, T, f + al * u + nl * dp * 0.5 + Z * (z0 + z1) * 0.5, (al * 0.06 + nl * dp * 0.5 + Z * (z1 - z0) * 0.5).abs(), C.ramp(col))


## Truncated pyramid (bottom half extents bh at z0, top th at z1) around c (ground); faces lean out when th > bh.
static func _frustum(pt: Dictionary, T: Dictionary, c: Vector3, bh: Vector2, th: Vector2, z0: float, z1: float, rp: Array) -> void:
	var b := [c + Vector3(-bh.x, -bh.y, z0), c + Vector3(bh.x, -bh.y, z0), c + Vector3(bh.x, bh.y, z0), c + Vector3(-bh.x, bh.y, z0)]
	var t := [c + Vector3(-th.x, -th.y, z1), c + Vector3(th.x, -th.y, z1), c + Vector3(th.x, th.y, z1), c + Vector3(-th.x, th.y, z1)]
	var ref := c + Z * (z0 + z1) * 0.5
	M.face(pt, T, t, ref, rp)
	M.face(pt, T, b, ref, rp)
	for i in 4:
		var k := (i + 1) % 4
		M.face(pt, T, [b[i], b[k], t[k], t[i]], ref, rp)


## Glazing on a leaning face: b0 -> b1 bottom edge, t0 -> t1 top edge, outward normal nl; mullions every ~1.5 m,
## lit consoles; lockdown: armour shutters.
static func _slant_glass(pt: Dictionary, T: Dictionary, b0: Vector3, b1: Vector3, t0: Vector3, t1: Vector3, nl: Vector3, lock: bool, seed: int) -> void:
	var q := func(u: float, v: float) -> Vector3: return b0.lerp(b1, u).lerp(t0.lerp(t1, u), v) + nl * 0.02
	M.dpoly(pt, T, [q.call(0.0, 0.08), q.call(1.0, 0.08), q.call(1.0, 0.9), q.call(0.0, 0.9)], Color8(80, 86, 90) if lock else Color8(30, 52, 70), nl)
	var n := maxi(2, int(b0.distance_to(b1) / 1.5))
	for k in range(0, n + 1):
		var u := float(k) / n
		M.dline(pt, T, q.call(u, 0.08), q.call(u, 0.9), Color8(44, 48, 52) if not lock else Color8(60, 64, 68), nl)
		if k < n and not lock:
			var h := P.hn(k, seed, 29)
			if h < 0.7:
				var u0 := u + 0.2 / n
				var u1 := u + 0.8 / n
				M.dpoly(pt, T, [q.call(u0, 0.12), q.call(u1, 0.12), q.call(u1, 0.42), q.call(u0, 0.42)], C.ca(CN_BLUE, 0.65) if h < 0.45 else C.ca(Color8(120, 255, 200), 0.45), nl)
			M.dline(pt, T, q.call(u + 0.15 / n, 0.85), q.call(u + 0.5 / n, 0.55), Color(1, 1, 1, 0.28), nl)
	if lock:
		for j in 6:
			var v := 0.12 + j * 0.13
			M.dline(pt, T, q.call(0.0, v), q.call(1.0, v), Color8(58, 62, 66), nl)
	M.dline(pt, T, q.call(0.0, 0.92), q.call(1.0, 0.92), C.ca(LAMP_R, 0.8) if lock else C.ca(Color8(120, 220, 255), 0.95), nl)


## Obstruction / warning lamp ON a fixture: a short bracket post standing on the surface at p (z = surface height) with
## the lamp housing on top (13.9c-14: nothing hovers).
static func _olamp(pt: Dictionary, T: Dictionary, p: Vector3, h: float, col: Color) -> void:
	M.cyl(pt, T, p + Z * h * 0.5, Z, 0.05, maxf(0.02, h * 0.5), 4, C.ramp(DARK), {"edge": false})
	M.cyl(pt, T, p + Z * (h + 0.09), Z, 0.11, 0.09, 6, C.ramp(Color8(150, 40, 34) if col == LAMP_R else Color8(60, 64, 66)), {"cap_t": 4})
	M.dpx(pt, T, p + Z * (h + 0.2), col)


# ---------------------------------------------------------------- command centre (FACB7-4, owner 13.9c-14)
## The facility's ops / planning building as a 4-storey futuristic tactical command centre on the same footprint, the
## facility's tallest: a hardened concrete ground floor (armoured slits, blast-door vestibule, COMMAND sign, bollards),
## two cantilevered planning floors in dark composite cladding with ribbon glazing (lit planning screens), vertical
## blast fins and cyan floor-edge LED bands, and a leaning faceted glass ops crown (the 4th-floor operations deck with
## live displays) under a thin overhanging roof brim. Roof: lift / stair penthouse with the satcom radome, HVAC, antenna
## farm and the comms / EW mast (13.9c-6 fold-in), red obstruction lamps on real fixtures. Generator skid and day tank
## on the forecourt. Lockdown: armour shutters over every pane, red bands, door sealed.
static func planning(S: Array, T: Dictionary, ex: float, ey: float, lock: bool, seed: int) -> void:
	var pa := _apron(S, T, ex, ey, seed)
	var cx := -1.2
	var c := Vector3(cx, 0, 0)
	var hx := minf(ex - 2.2, 5.8)
	var hy := minf(ey - 1.2, 4.8)
	var z1 := 4.2
	var z3 := 11.4
	var z4 := 15.2
	var g := _block(S, T, c, hx, hy, z1, Color8(146, 144, 136), seed)   # ground floor: hardened concrete
	var pg: Dictionary = g[0]
	for nl in [X, Y, -X, -Y]:
		var al := RO._along(nl)
		var ln: float = (hy if absf(nl.x) > 0.5 else hx) * 2.0
		var fc: Vector3 = c + nl * (hx if absf(nl.x) > 0.5 else hy)
		var nw := int(ln / 2.4)
		for k in nw:
			var u := -ln * 0.5 + (k + 0.5) * ln / nw
			if nl == X and absf(u) < 2.2:
				continue
			RO.quad(pg, T, fc + nl * 0.012 + al * u + Z * 2.7, al * 0.7, Z * 0.16, Color8(24, 30, 36) if lock else GLASS, nl)
			if not lock:
				M.dline(pg, T, fc + nl * 0.016 + al * (u - 0.55) + Z * 2.66, fc + nl * 0.016 + al * (u + 0.55) + Z * 2.66, C.ca(CN_BLUE, 0.8), nl)
	for sd in [Y, -Y]:
		_side(pg, T, c + sd * hy + X * (-hx * 0.4), X, sd, lock)
	var ux := hx + 0.5   # floors 2 + 3: cantilevered composite block
	var uy := minf(hy + 0.5, ey - 0.6)
	var clad := Color8(78, 86, 94)
	var pu := M.part(S, 0)
	M.box(pu, T, c + Z * (z1 + z3) * 0.5, Vector3(ux, uy, (z3 - z1) * 0.5), C.ramp(clad), Vector3(0.04, 0.04, 0.04))
	_band(M.part(S, 0), T, c, ux, uy, z1 + 0.1, lock, Color8(176, 178, 172))
	for fl in 2:
		var fz := z1 + fl * 3.6
		for nl in [X, Y, -X, -Y]:
			var al := RO._along(nl)
			var ln: float = (uy if absf(nl.x) > 0.5 else ux) * 2.0
			var fc: Vector3 = c + nl * (ux if absf(nl.x) > 0.5 else uy)
			_ribbon(pu, T, fc, al, nl, ln - 1.0, fz + 0.9, fz + 2.9, lock, seed + fl * 7 + int(nl.x * 3.0 + nl.y * 5.0))
			var ns := int(ln / 1.2)
			for k in ns:   # panel seams under the glazing
				var u := -ln * 0.5 + (k + 0.5) * ln / ns
				M.dline(pu, T, fc + nl * 0.014 + al * u + Z * (fz + 0.2), fc + nl * 0.014 + al * u + Z * (fz + 0.8), C.ca(C.ramp(clad)[0], 0.8), nl)
		_band(M.part(S, 1), T, c, ux, uy, fz + 3.5, lock, Color8(176, 178, 172))
	for nl in [X, Y]:   # blast fins on the two show faces
		var al := RO._along(nl)
		var ln: float = (uy if absf(nl.x) > 0.5 else ux) * 2.0
		_fins(M.part(S, 1), T, c + nl * (ux if absf(nl.x) > 0.5 else uy), al, nl, ln - 0.6, z1 + 0.3, z3 - 0.1, 2.4, 0.38, Color8(196, 198, 192))
	var bh := Vector2(ux - 0.3, uy - 0.3)   # ops crown: leaning faceted glass, 4th floor
	var th := Vector2(minf(ux + 0.7, ex - 1.6), minf(uy + 0.5, ey - 0.3))
	var pc := M.part(S, 1)
	_frustum(pc, T, c, bh, th, z3, z4, C.ramp(Color8(62, 70, 78)))
	var cr := [Vector3(-bh.x, -bh.y, z3), Vector3(bh.x, -bh.y, z3), Vector3(bh.x, bh.y, z3), Vector3(-bh.x, bh.y, z3)]
	var ct := [Vector3(-th.x, -th.y, z4), Vector3(th.x, -th.y, z4), Vector3(th.x, th.y, z4), Vector3(-th.x, th.y, z4)]
	var lean := Vector2(th.x - bh.x, th.y - bh.y)
	var dz := z4 - z3
	var nls := [Vector3(0, -dz, -lean.y).normalized(), Vector3(dz, 0, -lean.x).normalized(), Vector3(0, dz, -lean.y).normalized(), Vector3(-dz, 0, -lean.x).normalized()]
	for i in 4:
		var k := (i + 1) % 4
		_slant_glass(pc, T, c + cr[i], c + cr[k], c + ct[i], c + ct[k], nls[i], lock, seed + 40 + i)
	var pr := M.part(S, 2)   # roof brim + roof
	M.box(pr, T, c + Z * (z4 + 0.16), Vector3(th.x + 0.2, th.y + 0.2, 0.16), C.ramp(Color8(196, 198, 194)))
	for nl in [X, Y]:
		var al := RO._along(nl)
		var ln: float = (th.y if absf(nl.x) > 0.5 else th.x) + 0.2
		var fc: Vector3 = c + nl * ((th.x if absf(nl.x) > 0.5 else th.y) + 0.212)
		M.dline(pr, T, fc - al * ln + Z * (z4 + 0.16), fc + al * ln + Z * (z4 + 0.16), C.ca(LAMP_R, 0.9) if lock else C.ca(Color8(120, 220, 255), 0.95), nl)
	var zr := z4 + 0.32
	M.box(pr, T, c + Vector3(0, -th.y + 0.25, zr + 0.35), Vector3(th.x, 0.1, 0.35), C.ramp(Color8(170, 172, 168)))   # rear parapet screen
	var ph := c + Vector3(-th.x * 0.45, -th.y * 0.35, zr)   # lift / stair penthouse with the satcom radome
	M.box(pr, T, ph + Z * 1.2, Vector3(1.6, 1.3, 1.2), C.ramp(Color8(150, 152, 148)), Vector3(0.04, 0.04, 0.04))
	_rdoor(pr, T, ph + X * 1.6, Y, X, 0.45, 2.0, lock, false)
	M.box(pr, T, ph + Z * 2.55, Vector3(0.9, 0.9, 0.15), C.ramp(STEEL))
	M.cyl(pr, T, ph + Z * 3.5, Z, 1.0, 0.8, 12, C.ramp(Color8(214, 214, 206)), {"cap_t": 3})
	M.cyl(pr, T, ph + Z * 4.42, Z, 0.68, 0.12, 12, C.ramp(Color8(224, 224, 216)), {"cap_t": 4})
	for k in 3:
		_hvac(pr, T, c + Vector3(th.x * 0.15 + k * 1.7, th.y * 0.35, zr))
	for k in 4:   # antenna farm on the roof
		var ac := c + Vector3(th.x * 0.55 - k * 1.1, -th.y * 0.62, zr)
		M.cyl(pr, T, ac + Z * 0.2, Z, 0.08, 0.2, 4, C.ramp(DARK), {"edge": false})
		M.dline(pr, T, ac + Z * 0.4, ac + Z * (2.6 + k * 0.6), Color8(40, 42, 44))
	var ew := c + Vector3(th.x - 1.4, th.y - 1.4, zr)   # comms / EW mast (13.9c-6 fold-in)
	M.box(pr, T, ew + Vector3(-1.0, 0, 0.5), Vector3(0.6, 0.45, 0.5), C.ramp(Color8(150, 154, 148)), Vector3(0.03, 0.03, 0.03))
	M.dpx(pr, T, ew + Vector3(-0.39, 0.0, 0.75), LAMP_R if lock else LAMP_G, X)
	M.cyl(pr, T, ew + Z * 4.2, Z, 0.11, 4.2, 6, C.ramp(Color8(196, 196, 190)), {"edge": false})
	for t in 3:
		for i in 3:
			var a := TAU * i / 3.0 + t * 0.5
			var d := Vector3(cos(a), sin(a), 0)
			M.box(pr, T, ew + d * 0.32 + Z * (3.2 + t * 1.5), (d * 0.05 + Vector3(-d.y, d.x, 0) * 0.2 + Z * 0.38).abs() + Vector3(0.01, 0.01, 0), C.ramp(Color8(214, 214, 206)))
	M.cyl(pr, T, ew + Z * 7.6, Z, 0.55, 0.04, 10, C.ramp(DARK), {"cap_t": 0})
	M.dline(pr, T, ew + Z * 8.6, ew + Z * 10.0, Color8(40, 42, 44))
	_olamp(pr, T, ew + Z * 8.4, 0.02, LAMP_R)
	for gv in [Vector3(1.2, -0.3, 0), Vector3(-1.1, -1.0, 0), Vector3(-0.4, 1.1, 0)]:
		M.dline(pr, T, ew + Z * 6.5, ew + gv + Z * 0.05, Color(0.2, 0.2, 0.2, 0.6))
	for k in [Vector3(th.x, th.y, 0), Vector3(th.x, -th.y + 0.3, 0), Vector3(-th.x, th.y, 0)]:   # brim corner lamps on posts
		_olamp(pr, T, c + k * 0.97 + Z * zr, 0.35, LAMP_R)
	M.box(M.part(S, 2), T, c + Vector3(th.x * 0.2, 0.0, zr + 0.01), Vector3(1.0, 1.0, 0.012), C.ramp(Color8(196, 198, 194)), Vector3.ZERO, {"team": true})
	var xf := cx + hx   # entrance: blast-door vestibule, COMMAND sign, bollards, floodlights
	var vb := _block(S, T, Vector3(xf + 1.0, 0, 0), 1.0, 1.7, 3.3, CONC_D, seed + 9)
	_door(S, pa, T, xf + 2.0, 0.0, 0.9, 2.5, lock, not lock)
	var pv: Dictionary = vb[0]
	RO.quad(pv, T, Vector3(xf + 2.012, 0, 2.95), Y * 1.3, Z * 0.2, SIGN, X)
	M.dline(pv, T, Vector3(xf + 2.016, -1.1, 2.8), Vector3(xf + 2.016, 1.1, 2.8), CN_BLUE, X)
	FAC._stencil(pv, T, Vector3(xf + 2.012, 0, 3.0), Y, X, 7, 0.14)
	RO.quad(pg, T, Vector3(xf + 0.014, 0, 3.75), Y * 2.4, Z * 0.26, SIGN, X)
	FAC._stencil(pg, T, Vector3(xf + 0.018, 0, 3.78), Y, X, 10, 0.2)
	RO.flood(pg, pa, T, Vector3(xf, -hy * 0.7, 3.7), X)
	RO.flood(pg, pa, T, Vector3(xf, hy * 0.7, 3.7), X)
	var pb := M.part(S, 0)
	for k in 4:
		M.cyl(pb, T, Vector3(ex - 0.5, -1.8 + k * 1.2, 0.45), Z, 0.14, 0.45, 6, C.ramp(YEL), {"cap_t": 3})
	var gx := ex - 0.9   # generator skid + day tank on the forecourt
	var gy := ey - 1.5
	if gx - 0.7 > xf + 2.2:
		M.box(pb, T, Vector3(gx, gy, 0.85), Vector3(0.6, 1.2, 0.75), C.ramp(OLIVE), Vector3(0.04, 0.04, 0.04))
		for k in 4:
			M.dline(pb, T, Vector3(gx + 0.61, gy - 0.9 + k * 0.5, 0.45), Vector3(gx + 0.61, gy - 0.9 + k * 0.5, 1.4), C.ca(DARK, 0.8), X)
		M.cyl(pb, T, Vector3(gx - 0.2, gy + 0.8, 1.85), Z, 0.08, 0.25, 6, C.ramp(DARK), {"cap_t": 0})
		M.dpx(pb, T, Vector3(gx + 0.62, gy + 0.8, 1.3), AMBER if lock else LAMP_G, X)
		M.cyl(M.part(S, 0), T, Vector3(gx, -gy, 0.7), Y, 0.55, 1.0, 10, C.ramp(Color8(80, 92, 74)), {"cap_t": 2})

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
	# FACB7-4: contaminated-runoff sump on the -y (runoff tank) side: kerbed grated pit the wash floor drains to, a pump
	# head and the transfer pipe out through the link wall to the runoff tank, RUNOFF lettering, a wet drain streak
	var sp := Vector3(minf(5.0, ex - 1.2), -ey + 1.4, 0)
	if sp.y + 0.7 < ly - lw - 0.3:
		var pk := M.part(S, -1)
		M.box(pk, T, sp + Z * 0.1, Vector3(0.75, 0.6, 0.1), C.ramp(CONC_D))
		FAC._hz(pk, T, sp + Vector3(-0.75, 0.6, 0.21), sp + Vector3(0.75, 0.6, 0.21), Z, 6)
		RO.quad(pk, T, sp + Z * 0.205, X * 0.55, Y * 0.42, Color8(30, 34, 36), Z)
		for k in 5:
			M.dline(pk, T, sp + Vector3(-0.5 + k * 0.25, -0.38, 0.21), sp + Vector3(-0.5 + k * 0.25, 0.38, 0.21), Color8(96, 102, 106), Z)
		M.dpoly(pa, T, [sp + Vector3(-0.3, 0.6, zt + 0.003), sp + Vector3(0.3, 0.6, zt + 0.003), Vector3(sp.x + 0.5, ly - lw, zt + 0.003), Vector3(sp.x - 0.5, ly - lw, zt + 0.003)], Color(0.35, 0.55, 0.7, 0.3), Z)
		var pmp := M.part(S, 0)
		M.box(pmp, T, sp + Vector3(-1.2, -0.25, 0.35), Vector3(0.3, 0.3, 0.35), C.ramp(Color8(60, 92, 120)), Vector3(0.02, 0.02, 0.02))
		M.cyl(pmp, T, sp + Vector3(-1.2, -0.25, 0.85), Z, 0.18, 0.15, 8, C.ramp(Color8(200, 160, 40)), {"cap_t": 3})
		M.dpx(pmp, T, sp + Vector3(-0.89, -0.25, 0.5), LAMP_R if lock else LAMP_G, X)
		M.cyl(pmp, T, Vector3(sp.x - 1.2, (sp.y - 0.25 - ey) * 0.5, 0.3), Y, 0.09, (sp.y - 0.25 + ey) * 0.5, 6, C.ramp(Color8(70, 74, 78)), {"cap_t": 2})
		_gtext(pa, T, sp + Vector3(1.6, 0.0, zt + 0.004), X, 6, 0.3, YEL)


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
	_rdoor(M.part(S, 1), T, Vector3(xb, 0, 0), Y, -X, 0.6, 2.2, lock, false)   # FACB7-2 (13.9c-8): reinforced inner door
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
## FACB7-4 (owner 13.9c-14): the training complex on the range zone. Local -y half: a 2-storey, fully INDOOR high-tech
## training building (concrete ballistic ground floor with the CQB shoot-house floors, simulator bays upstairs; a range-
## control / observation gallery with a lit ribbon window overlooking the range, a roll-up range door with the LIVE FIRE
## lamp on its bracket, a CQB sign panel and louvres, an exterior fire stair, roof extraction fans for the shoot house,
## simulator skylight domes, HVAC, the red range flag on its roof mast). Local +y half: the outdoor rifle / explosives
## testing range (covered firing line with booths and a target console, lane lines, steel Machine-replica targets, the
## earth stop berm; a HESCO-walled demolition test pit with an observation bunker behind a HESCO traverse; fences with a
## gate on the lane side). Lockdown (base not secure): targets dropped, flag down, red lamps, shutters.
static func range_(S: Array, T: Dictionary, ex: float, ey: float, lock: bool, seed: int) -> void:
	var pa := _apron(S, T, ex, ey, seed, Color8(120, 118, 110))
	var zt := zt_()
	# ---- training building (local y < 0)
	var by0 := -ey + 0.4
	var by1 := -1.2
	var bx0 := -ex + 0.8
	var bx1 := ex - 1.0
	var c := Vector3((bx0 + bx1) * 0.5, (by0 + by1) * 0.5, 0)
	var hx := (bx1 - bx0) * 0.5
	var hy := (by1 - by0) * 0.5
	var z1 := 4.2
	var zr := 8.4
	var g := _block(S, T, c, hx, hy, z1, Color8(150, 148, 140), seed)
	var pg: Dictionary = g[0]
	var pu := M.part(S, 0)
	var clad := Color8(176, 180, 178)
	M.box(pu, T, c + Z * (z1 + zr) * 0.5, Vector3(hx + 0.15, hy + 0.15, (zr - z1) * 0.5), C.ramp(clad), Vector3(0.04, 0.04, 0.04))
	_band(M.part(S, 0), T, c, hx + 0.15, hy + 0.15, z1 + 0.06, lock, Color8(92, 98, 104))
	_band(M.part(S, 1), T, c, hx + 0.15, hy + 0.15, zr - 0.1, lock, Color8(92, 98, 104))
	for nl in [X, Y, -X, -Y]:
		var al := RO._along(nl)
		var ln: float = (hy if absf(nl.x) > 0.5 else hx) * 2.0
		var fc: Vector3 = c + nl * ((hx if absf(nl.x) > 0.5 else hy) + 0.15)
		var ns := int(ln / 1.6)
		for k in ns:   # composite panel seams
			var u := -ln * 0.5 + (k + 0.5) * ln / ns
			M.dline(pu, T, fc + nl * 0.014 + al * u + Z * (z1 + 0.3), fc + nl * 0.014 + al * u + Z * (zr - 0.3), C.ca(C.ramp(clad)[0], 0.7), nl)
		if nl == Y:   # range side: observation / range-control gallery ribbon
			_ribbon(pu, T, fc, al, nl, ln - 1.6, z1 + 1.0, z1 + 3.1, lock, seed + 3)
		else:   # simulator bays: high clerestory slots
			var nw := int(ln / 2.0)
			for k in nw:
				var u := -ln * 0.5 + (k + 0.5) * ln / nw
				RO.quad(pu, T, fc + nl * 0.012 + al * u + Z * (zr - 1.1), al * 0.6, Z * 0.22, Color8(22, 26, 30), nl)
				RO.quad(pu, T, fc + nl * 0.016 + al * u + Z * (zr - 1.1), al * 0.52, Z * 0.15, Color8(86, 92, 96) if lock else (C.ca(Color8(150, 220, 255), 0.8) if (k + seed) % 3 != 0 else Color8(34, 56, 72)), nl)
		var gf: Vector3 = c + nl * (hx if absf(nl.x) > 0.5 else hy)
		for k in int(ln / 3.2):   # ground floor: ballistic concrete, louvres for the shoot-house air
			var u := -ln * 0.5 + (k + 0.5) * ln / int(ln / 3.2)
			if nl == Y and absf(u) < 3.4:
				continue
			RO.quad(pg, T, gf + nl * 0.012 + al * u + Z * 3.2, al * 0.5, Z * 0.32, Color8(52, 56, 60), nl)
			for j in 4:
				M.dline(pg, T, gf + nl * 0.016 + al * (u - 0.45) + Z * (2.95 + j * 0.16), gf + nl * 0.016 + al * (u + 0.45) + Z * (2.95 + j * 0.16), Color8(92, 98, 102), nl)
	var ry := c.y + hy   # range door: roll-up (open on drills = lit shoot-house lane), personnel door, LIVE FIRE lamp
	var pd := M.part(S, 1)
	RO.quad(pd, T, Vector3(c.x - 1.2, ry + 0.014, 1.7), X * 1.6, Z * 1.7, Color8(28, 30, 32) if not lock else C.ramp(STEEL)[1], Y)
	if lock:
		for i in 10:
			M.dline(pd, T, Vector3(c.x - 2.75, ry + 0.02, 0.2 + i * 0.32), Vector3(c.x + 0.35, ry + 0.02, 0.2 + i * 0.32), C.ca(DARK, 0.8), Y)
	else:
		for i in 3:   # shoot-house lane inside: plywood walls lit by the drill lights
			M.dline(pd, T, Vector3(c.x - 2.4 + i * 1.1, ry + 0.02, 0.1), Vector3(c.x - 2.4 + i * 1.1, ry + 0.02, 2.4), Color8(150, 120, 80), Y)
		M.dline(pd, T, Vector3(c.x - 2.7, ry + 0.02, 3.2), Vector3(c.x + 0.3, ry + 0.02, 3.2), Color8(220, 210, 170), Y)
		M.dpoly(pa, T, [Vector3(c.x - 2.8, ry, zt), Vector3(c.x + 0.4, ry, zt), Vector3(c.x + 0.9, ry + 1.6, zt), Vector3(c.x - 3.3, ry + 1.6, zt)], POOL, Z)
	for s in [-1.0, 1.0]:
		FAC._jamb(pd, T, Vector3(c.x - 1.2 + s * 1.7, ry + 0.02, 0), Y, 0.1, 0.2, 3.4)
	M.box(pd, T, Vector3(c.x - 1.2, ry + 0.25, 3.65), Vector3(1.8, 0.25, 0.22), C.ramp(STEEL))   # door drum housing
	_rdoor(pd, T, Vector3(c.x + 2.2, ry, 0), X, Y, 0.5, 2.2, lock, false)
	var lf := Vector3(c.x + 0.9, ry, 2.6)   # LIVE FIRE lamp on a wall bracket
	M.box(pd, T, lf + Y * 0.15, Vector3(0.06, 0.15, 0.05), C.ramp(DARK))
	M.cyl(pd, T, lf + Y * 0.32 + Z * 0.12, Z, 0.12, 0.1, 6, C.ramp(Color8(150, 40, 34)), {"cap_t": 4})
	M.dpx(pd, T, lf + Y * 0.32 + Z * 0.26, LAMP_R if not lock else Color8(90, 40, 36))
	RO.quad(pu, T, Vector3(c.x + 4.4, ry + 0.17, 7.75), X * 1.6, Z * 0.3, SIGN, Y)   # TRAINING sign on the range face
	FAC._stencil(pu, T, Vector3(c.x + 4.4, ry + 0.175, 7.77), X, Y, 8, 0.22)
	M.dline(pu, T, Vector3(c.x + 3.0, ry + 0.175, 7.47), Vector3(c.x + 5.8, ry + 0.175, 7.47), CN_BLUE, Y)
	var sxf := c.x - hx   # south face (local -x): CQB sign panel + exterior fire stair to the upper floor
	RO.quad(pg, T, Vector3(sxf - 0.014, c.y + hy * 0.3, 2.4), Y * 1.3, Z * 0.7, SIGN, -X)
	FAC._stencil(pg, T, Vector3(sxf - 0.018, c.y + hy * 0.3, 2.45), Y, -X, 3, 0.6)
	M.dline(pg, T, Vector3(sxf - 0.018, c.y + hy * 0.3 - 1.1, 1.8), Vector3(sxf - 0.018, c.y + hy * 0.3 + 1.1, 1.8), YEL, -X)
	var pst := M.part(S, 1)
	for k in 10:
		var t := float(k) / 9.0
		M.box(pst, T, Vector3(sxf - 0.42, c.y - hy + 1.0 + t * 4.2, 0.25 + t * 3.95), Vector3(0.34, 0.16, 0.03), C.ramp(STEEL))
	M.box(pst, T, Vector3(sxf - 0.42, c.y - hy + 5.8, 4.2), Vector3(0.36, 0.7, 0.04), C.ramp(STEEL))
	M.dline(pst, T, Vector3(sxf - 0.77, c.y - hy + 0.8, 1.2), Vector3(sxf - 0.77, c.y - hy + 5.2, 5.2), YEL, -X)
	_rdoor(pst, T, Vector3(sxf - 0.15, c.y - hy + 5.8, z1 + 0.05), Y, -X, 0.45, 2.0, lock, false)
	var pr := M.part(S, 2)   # roof: parapet, shoot-house extraction fans, simulator domes, HVAC, range flag mast
	for e in [[c + Vector3(0, -hy - 0.03, zr + 0.25), Vector3(hx + 0.15, 0.12, 0.25)], [c + Vector3(0, hy + 0.03, zr + 0.25), Vector3(hx + 0.15, 0.12, 0.25)],
			[c + Vector3(-hx - 0.03, 0, zr + 0.25), Vector3(0.12, hy, 0.25)], [c + Vector3(hx + 0.03, 0, zr + 0.25), Vector3(0.12, hy, 0.25)]]:
		M.box(pr, T, e[0], e[1], C.ramp(Color8(160, 164, 162)))
	for k in 4:
		var fc2 := c + Vector3(hx * 0.45, -hy + 2.0 + k * (2.0 * hy - 4.0) / 3.0, zr)
		M.cyl(pr, T, fc2 + Z * 0.5, Z, 0.42, 0.5, 10, C.ramp(Color8(170, 174, 176)), {"cap_t": 3})
		M.cyl(pr, T, fc2 + Z * 1.03, Z, 0.3, 0.03, 10, C.ramp(DARK), {"cap_t": 0})
	for k in 3:
		var dc2 := c + Vector3(-hx * 0.4, -hy + 2.6 + k * (2.0 * hy - 5.2) / 2.0, zr)
		M.cyl(pr, T, dc2 + Z * 0.25, Z, 1.0, 0.25, 12, C.ramp(Color8(214, 216, 214)), {"cap_t": 3}, 0.0, 0.7)
		M.cyl(pr, T, dc2 + Z * 0.62, Z, 0.7, 0.12, 12, C.ramp(Color8(150, 200, 230) if not lock else Color8(110, 116, 120)), {"cap_t": 4})
	_hvac(pr, T, c + Vector3(-hx * 0.4, hy - 1.2, zr))
	var fm := c + Vector3(hx - 0.6, hy - 0.6, zr)
	M.cyl(pr, T, fm + Z * 1.5, Z, 0.05, 1.5, 4, C.ramp(Color8(210, 210, 204)), {"edge": false})
	if not lock:
		M.dpoly(pr, T, [fm + Z * 3.0, fm + Vector3(-0.9, 0.1, 2.85), fm + Vector3(-0.9, 0.1, 2.45), fm + Z * 2.5], Color8(220, 40, 30), Y)
	_olamp(pr, T, fm + Z * 3.0, 0.02, LAMP_R)
	M.box(M.part(S, 2), T, c + Vector3(0, 0, zr + 0.01), Vector3(1.0, 1.0, 0.012), C.ramp(Color8(160, 164, 162)), Vector3.ZERO, {"team": true})
	var nv := c + X * hx   # north (lane) face: entrance vestibule on the json door (local y -2)
	_block(S, T, Vector3(nv.x + 0.5, -2.0, 0), 0.5, 1.2, 3.0, CONC_D, seed + 9)
	_rdoor(M.part(S, 1), T, Vector3(nv.x + 1.0, -2.0, 0), Y, X, 0.65, 2.3, lock, not lock)
	# ---- outdoor rifle / explosives testing range (local y > 0)
	var r0 := 0.2
	var r1 := ey - 0.2
	RO.quad(pa, T, Vector3(0, (r0 + r1) * 0.5, zt), X * (ex - 0.25), Y * (r1 - r0) * 0.5, Color8(138, 124, 92), Z)
	for j in int(ey * 6.0):
		M.dpx(pa, T, Vector3((P.hn(j, seed, 61) - 0.5) * 2.0 * (ex - 0.4), r0 + P.hn(j, seed, 63) * (r1 - r0), zt + 0.001), Color(0.3, 0.26, 0.18, 0.35), Z)
	var earth: Array = C.ramp(EARTH)
	var bm := M.part(S, 0)   # stop berm across the far end
	M.box(bm, T, Vector3(0, ey - 1.15, 1.2), Vector3(ex - 0.3, 1.0, 1.2), earth, Vector3(0.0, 0.0, 0.75))
	for j in int(ex * 3.0):
		M.dpx(M.part(S, 1), T, Vector3((P.hn(j, seed, 3) - 0.5) * 2.0 * (ex - 0.6), ey - 1.15 + (P.hn(j, seed, 5) - 0.5) * 0.4, 2.42), Color8(84, 96, 58))
	var lx0 := -2.4   # rifle lanes: x from lx0 to ex - 0.6
	var nlane := 4
	var lw := (ex - 0.6 - lx0) / float(nlane)
	var fl := 3.4   # firing line
	var tgt := ey - 3.6
	for i in nlane:
		var lc := lx0 + lw * (float(i) + 0.5)
		if i > 0:
			M.dline(pa, T, Vector3(lx0 + lw * i, fl + 0.2, zt + 0.003), Vector3(lx0 + lw * i, tgt + 0.8, zt + 0.003), C.ca(STENCIL, 0.7), Z)
		for d in [0.35, 0.65]:   # distance markers
			RO.quad(pa, T, Vector3(lc + lw * 0.32, fl + (tgt - fl) * d, zt + 0.004), X * 0.12, Y * 0.12, STENCIL, Z)
		var tp := Vector3(lc, tgt, 0)
		var pt := M.part(S, 1)
		var mk: Array = C.ramp(Color8(54, 56, 60))
		M.box(pt, T, tp + Z * 0.12, Vector3(0.35, 0.25, 0.12), C.ramp(Color8(80, 84, 70)))   # target lifter
		if lock:
			M.box(pt, T, tp + Vector3(0, 0.35, 0.28), Vector3(0.5, 0.1, 0.06), mk)
		else:
			M.box(pt, T, tp + Z * 1.0, Vector3(0.4, 0.3, 0.28), mk, Vector3(0.06, 0.06, 0.06))
			M.box(pt, T, tp + Vector3(0.0, -0.35, 1.22), Vector3(0.16, 0.18, 0.14), mk)
			M.dpx(pt, T, tp + Vector3(0.06, -0.54, 1.25), Color8(255, 60, 40), -Y)
			M.dpx(pt, T, tp + Vector3(-0.06, -0.54, 1.25), Color8(255, 60, 40), -Y)
			for l in [Vector3(0.5, 0.5, 0), Vector3(0.5, -0.5, 0), Vector3(-0.5, 0.5, 0), Vector3(-0.5, -0.5, 0)]:
				M.dline(pt, T, tp + l * 0.4 + Z * 0.9, tp + l * 0.9 + Z * 1.15, Color8(40, 42, 46))
				M.dline(pt, T, tp + l * 0.9 + Z * 1.15, tp + l * 1.1 + Z * 0.25, Color8(40, 42, 46))
		RO.quad(pa, T, Vector3(lc, fl - 0.9, zt + 0.004), X * 0.55, Y * 0.6, Color8(52, 60, 50), Z)   # firing mat
	var pcn := M.part(S, 1)   # covered firing line: posts, canopy, booth dividers, console
	for px in [lx0 + 0.1, ex - 0.7]:
		for py in [r0 + 0.4, fl - 0.1]:
			M.box(pcn, T, Vector3(px, py, 1.4), Vector3(0.08, 0.08, 1.4), C.ramp(STEEL))
	M.box(M.part(S, 2), T, Vector3((lx0 + ex - 0.6) * 0.5, (r0 + fl) * 0.5 + 0.15, 2.9), Vector3((ex - 0.6 - lx0) * 0.5 + 0.2, (fl - r0) * 0.5 + 0.2, 0.08), C.ramp(Color8(150, 156, 160)))
	for i in range(1, nlane):
		M.box(pcn, T, Vector3(lx0 + lw * i, fl - 1.0, 0.6), Vector3(0.04, 0.7, 0.6), C.ramp(Color8(120, 126, 120)))
	M.box(pcn, T, Vector3(ex - 1.2, r0 + 0.6, 0.55), Vector3(0.35, 0.25, 0.55), C.ramp(Color8(70, 76, 82)), Vector3(0.0, 0.1, 0.0))
	M.dpx(pcn, T, Vector3(ex - 1.2, r0 + 0.86, 0.95), CN_BLUE if not lock else LAMP_R, Y)
	RO.quad(pa, T, Vector3((lx0 + ex - 0.6) * 0.5, fl + 0.15, zt + 0.005), X * (ex - 0.6 - lx0) * 0.5, Y * 0.08, Color8(220, 60, 50), Z)
	var pf := M.part(S, 2)   # range flag pole + LIVE FIRE lamp at the firing line
	var fp := Vector3(ex - 0.5, fl + 0.4, 0)
	M.cyl(pf, T, fp + Z * 1.6, Z, 0.04, 1.6, 4, C.ramp(Color8(200, 200, 196)), {"edge": false})
	if not lock:
		M.dpoly(pf, T, [fp + Z * 3.15, fp + Vector3(0, 0.8, 3.0), fp + Vector3(0, 0.8, 2.6), fp + Z * 2.65], Color8(220, 40, 30), X)
	_olamp(pf, T, fp + Z * 3.2, 0.02, LAMP_R if not lock else Color8(90, 40, 36))
	# explosives testing: HESCO traverse, walled demolition pit, observation bunker
	var dx := -ex + 0.5
	RO.hesco(S, T, Vector3(-2.95, fl + 0.6, 0), Y, int((tgt - fl) / 1.05), 1.6, seed)
	RO.hesco(S, T, Vector3(dx, ey * 0.45, 0), Y, int((ey - 1.4 - ey * 0.45) / 1.05), 1.4, seed + 1)
	RO.hesco(S, T, Vector3(dx + 1.05, ey * 0.45, 0), X, 2, 1.4, seed + 2)
	var pc := Vector3((dx - 2.6) * 0.5 + 0.5, ey * 0.45 + 3.6, 0)
	var ppit := M.part(S, -1)
	var pts := []
	for k in 12:
		var a := TAU * k / 12.0
		pts.append(pc + Vector3(cos(a) * 1.3, sin(a) * 1.6, zt + 0.002))
	M.dpoly(ppit, T, pts, Color8(58, 50, 40), Z)
	var pts2 := []
	for k in 12:
		var a := TAU * k / 12.0
		pts2.append(pc + Vector3(cos(a) * 0.7, sin(a) * 0.9, zt + 0.003))
	M.dpoly(ppit, T, pts2, Color8(36, 32, 28), Z)
	for k in 10:
		var a := TAU * k / 10.0 + 0.3
		M.dline(ppit, T, pc + Vector3(cos(a) * 0.8, sin(a) * 1.0, zt + 0.004), pc + Vector3(cos(a) * 1.9, sin(a) * 2.2, zt + 0.004), Color(0.1, 0.09, 0.08, 0.5), Z)
	M.cyl(M.part(S, 1), T, pc + Z * 0.5, Z, 0.05, 0.5, 4, C.ramp(Color8(120, 110, 90)), {"edge": false})   # charge stand
	RO.quad(pa, T, Vector3(pc.x, ey * 0.45 - 0.6, zt + 0.004), X * 0.9, Y * 0.12, YEL, Z)
	var bk := Vector3(dx + 1.2, fl - 0.6, 0)   # observation bunker: concrete, slit toward the pit, sandbag roof
	M.box(M.part(S, 0), T, bk + Z * 0.7, Vector3(0.9, 0.8, 0.7), C.ramp(CONC_D), Vector3(0.05, 0.05, 0.05))
	RO.quad(M.part(S, 0), T, bk + Y * 0.812 + Z * 1.05, X * 0.55, Z * 0.08, Color8(20, 22, 24), Y)
	for k in 4:
		M.box(M.part(S, 1), T, bk + Vector3(-0.6 + k * 0.4, 0, 1.5), Vector3(0.19, 0.7, 0.1), C.ramp(SAND))
	_rdoor(M.part(S, 0), T, bk - X * 0.9, Y, -X, 0.35, 1.2, lock, false)
	RO.quad(pa, T, Vector3(bk.x, bk.y + 1.4, zt + 0.004), X * 0.8, Y * 0.18, SIGN, Z)
	_gtext(pa, T, Vector3(bk.x, bk.y + 1.4, zt + 0.005), X, 4, 0.22, YEL)
	for sd in [1.0, -1.0]:   # fences on both long sides, a gate toward the lane (json door [8,20], local y +10)
		var fx: float = sd * (ex - 0.12)
		var nl2: Vector3 = X * sd
		for k in 9:
			var fy := r0 + 0.2 + k * (r1 - r0 - 0.4) / 8.0
			if sd > 0.0 and absf(fy - 10.0) < 1.0:
				continue
			M.cyl(M.part(S, 1), T, Vector3(fx, fy, 0.7), Z, 0.04, 0.7, 4, C.ramp(STEEL), {"edge": false})
		for zz in [0.5, 1.0, 1.35]:
			if sd > 0.0:
				M.dline(M.part(S, 1), T, Vector3(fx, r0 + 0.2, zz), Vector3(fx, 9.0, zz), Color8(110, 114, 116), nl2)
				M.dline(M.part(S, 1), T, Vector3(fx, 11.0, zz), Vector3(fx, r1 - 0.2, zz), Color8(110, 114, 116), nl2)
			else:
				M.dline(M.part(S, 1), T, Vector3(fx, r0 + 0.2, zz), Vector3(fx, r1 - 0.2, zz), Color8(110, 114, 116), nl2)
		if sd < 0.0:
			RO.quad(M.part(S, 1), T, Vector3(fx - 0.03, ey * 0.3, 1.0), Y * 0.5, Z * 0.3, Color8(220, 60, 50), -X)   # DANGER board
			FAC._stencil(M.part(S, 1), T, Vector3(fx - 0.035, ey * 0.3, 1.02), Y, -X, 4, 0.18)

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


# ================================================================ FACB7-2 (owner 13.9c-6/-8/-9/-11): new facility art
## Zone kinds that also get rot_<f>_ruin states (their sim part is a real building: the magazine's armoured cell
## cooks off, SENT7's Sentinel Barracks can be destroyed); entity_layer picks them from render_entries mag / bar.
const RUIN_KINDS := ["magazine", "barracks"]
static var _ruin := false
const MED_W := Color8(200, 202, 196)
const MED_R := Color8(206, 44, 40)


static func zt_() -> float:
	return ZS + 0.004


## Reinforced steel door on any face: c = face point at ground level, al = along the face, nl = outward normal.
## Heavy concrete frame and lintel standing proud of the face, ribbed steel leaf with a seam, hazard jambs and a
## status lamp. open: dark opening with a lit strip (green lamp); lockdown: sealed, hazard diagonals, red lamp;
## otherwise shut (amber lamp).
static func _rdoor(pt: Dictionary, T: Dictionary, c: Vector3, al: Vector3, nl: Vector3, hw: float, hz: float, lock: bool, open := false) -> void:
	var cd: Array = C.ramp(CONC_D)
	var st: Array = C.ramp(Color8(92, 98, 100))
	for s in [-1.0, 1.0]:
		M.box(pt, T, c + al * (s * (hw + 0.2)) + nl * 0.12 + Z * (hz * 0.5 + 0.15), (al * 0.2 + nl * 0.12 + Z * (hz * 0.5 + 0.15)).abs(), cd)
		FAC._jamb(pt, T, c + al * (s * (hw + 0.2)) + nl * 0.24, nl, 0.12, 0.2, hz)
	M.box(pt, T, c + nl * 0.14 + Z * (hz + 0.45), (al * (hw + 0.4) + nl * 0.14 + Z * 0.3).abs(), cd)
	var f := c + nl * 0.02
	if open and not lock:
		RO.quad(pt, T, f + Z * hz * 0.5, al * hw, Z * hz * 0.5, Color8(26, 28, 30), nl)
		M.dline(pt, T, f + nl * 0.004 - al * (hw - 0.1) + Z * (hz - 0.15), f + nl * 0.004 + al * (hw - 0.1) + Z * (hz - 0.15), Color8(220, 210, 170), nl)
	else:
		RO.quad(pt, T, f + Z * hz * 0.5, al * hw, Z * hz * 0.5, C.ramp(Color8(122, 70, 58))[2] if lock else st[1], nl)
		for i in int(hz / 0.35):
			M.dline(pt, T, f + nl * 0.004 - al * (hw - 0.05) + Z * (0.25 + i * 0.35), f + nl * 0.004 + al * (hw - 0.05) + Z * (0.25 + i * 0.35), C.ca(st[0], 0.85), nl)
		M.dline(pt, T, f + nl * 0.006 + Z * 0.1, f + nl * 0.006 + Z * (hz - 0.1), C.ca(st[4], 0.8), nl)
		if lock:
			FAC._hz(pt, T, f + nl * 0.008 - al * (hw - 0.1) + Z * 0.3, f + nl * 0.008 + al * (hw - 0.1) + Z * (hz - 0.3), nl, 8)
	M.dpx(pt, T, c + nl * 0.27 + al * (hw + 0.2) + Z * (hz + 0.1), LAMP_R if lock else (LAMP_G if open else AMBER), nl)


## Hazmat / CBRN suits hanging in an open bay (decals on the face plane, across 2*hw).
static func _suits(pt: Dictionary, T: Dictionary, c: Vector3, al: Vector3, nl: Vector3, hw: float, seed: int) -> void:
	var n := int(hw * 2.0 / 0.55)
	for k in n:
		var a := c + nl * 0.01 + al * (-hw + 0.3 + k * 0.55)
		var col := Color8(214, 186, 52) if (k + seed) % 3 != 0 else Color8(96, 150, 200)
		M.dline(pt, T, a + Z * 0.7, a + Z * 1.55, col, nl)
		M.dline(pt, T, a + al * 0.12 + Z * 0.75, a + al * 0.12 + Z * 1.5, P.mul(col, 0.75), nl)
		M.dline(pt, T, a - al * 0.1 + Z * 1.45, a - al * 0.14 + Z * 0.95, P.mul(col, 0.8), nl)
		M.dpx(pt, T, a + al * 0.06 + Z * 1.72, Color8(40, 64, 80), nl)
		M.dline(pt, T, a + al * 0.06 + Z * 1.85, a + al * 0.06 + Z * 2.1, Color8(60, 62, 64), nl)


## Flat painted ground lettering block (n characters) at c along al (ground decals, normal Z).
static func _gtext(pa: Dictionary, T: Dictionary, c: Vector3, al: Vector3, n: int, h: float, col: Color) -> void:
	var up := Vector3(-al.y, al.x, 0)
	for i in n:
		var a := c + al * (-0.5 * (n - 1) * h * 0.75 + i * h * 0.75)
		M.dline(pa, T, a - al * h * 0.25 - up * h * 0.5, a - al * h * 0.25 + up * h * 0.5, col, Z)
		M.dline(pa, T, a - al * h * 0.25 + up * h * 0.5, a + al * h * 0.25 + up * h * 0.5, col, Z)
		if i % 2 == 0:
			M.dline(pa, T, a - al * h * 0.25, a + al * h * 0.2, col, Z)
		else:
			M.dline(pa, T, a + al * h * 0.25 + up * h * 0.5, a + al * h * 0.25 - up * h * 0.5, col, Z)
		M.dline(pa, T, a - al * h * 0.25 - up * h * 0.5, a + al * h * 0.25 - up * h * 0.5, col, Z)


## Lightning-protection mast (air terminal on a slim pole with a down conductor) at ground point c, height h.
static func _lmast(pt: Dictionary, T: Dictionary, c: Vector3, h: float) -> void:
	M.cyl(pt, T, c + Z * 0.25, Z, 0.22, 0.25, 6, C.ramp(CONC_D), {"cap_t": 2})
	M.cyl(pt, T, c + Z * (h * 0.5 + 0.5), Z, 0.06, h * 0.5, 4, C.ramp(STEEL), {"edge": false})
	M.dline(pt, T, c + Z * (h + 1.0), c + Z * (h + 1.6), Color8(200, 200, 196))
	M.dpx(pt, T, c + Z * (h + 0.9), LAMP_R)


# ---------------------------------------------------------------- special ammunition magazine (13.9c-6)
## Earth-covered igloo for the counter-nanite rounds: a concrete arch under a grassed earth mound (door side +x), a
## reinforced headwall with angled wing walls, a double steel blast door in a hazard frame with the orange 1.1
## explosives placard and the magazine board, mushroom vents and two lightning-protection masts on the mound, a
## free-standing T-wall barricade traverse in front of the door (access round both ends), fire point and sand bin.
## Lockdown: door sealed, red lamps. Ruin (the armoured cell cooked off): the mound blown open into a scorched
## crater, the headwall broken to a stump, the door torn out, burnt debris.
static func magazine(S: Array, T: Dictionary, ex: float, ey: float, lock: bool, seed: int) -> void:
	var pa := _apron(S, T, ex, ey, seed, Color8(122, 116, 100))
	var zt := zt_()
	var x0 := -ex + 0.4
	var xh := ex - 3.9
	var hw := minf(ey - 0.4, 3.5)
	var mh := 2.9 if not _ruin else 1.5
	var earth: Array = C.ramp(EARTH if not _ruin else Color8(70, 62, 50))
	var cd: Array = C.ramp(CONC_D)
	var pm := M.part(S, 0)
	var prof := PackedVector2Array()
	var back := PackedVector2Array()
	for i in 9:
		var a := PI * float(i) / 8.0
		var r := -cos(a) * hw
		var z := 0.05 + sin(a) * mh * (0.75 + 0.25 * sin(a))
		prof.append(Vector2(r, z))
		back.append(Vector2(r * 0.55, 0.05 + (z - 0.05) * 0.25))
	M.loft(pm, T, [[x0, back], [x0 + 2.2, prof], [xh, prof]], earth)
	var grass: Array = C.ramp(Color8(92, 106, 60))
	for j in int(ex * 9.0):   # grass, scrub and stones on the cover
		var a := PI * (0.12 + 0.76 * P.hn(j, seed, 3))
		var x := x0 + 2.4 + (xh - x0 - 2.6) * P.hn(j, seed, 5)
		var z := 0.05 + sin(a) * mh * (0.75 + 0.25 * sin(a)) + 0.02
		var n := Vector3(0, -cos(a), sin(a))
		var col: Color = grass[j % 4] if not _ruin else (Color(0.08, 0.07, 0.06, 0.6) if j % 2 == 0 else earth[0])
		M.dpx(pm, T, Vector3(x, -cos(a) * hw * 0.98, z), col, n)
		if j % 4 == 0 and not _ruin:
			M.dline(pm, T, Vector3(x, -cos(a) * hw * 0.98, z), Vector3(x + 0.15, -cos(a) * hw * 0.98, z + 0.25), grass[1], n)
	if _ruin:   # blast crater torn through the cover, charred arch ribs, debris
		var cc := Vector3((x0 + xh) * 0.5 + 1.0, 0, mh + 0.05)
		var ring: Array = []
		for i in 10:
			var a := TAU * i / 10.0
			ring.append(cc + Vector3(cos(a) * (1.9 + 0.4 * P.hn(i, seed, 7)), sin(a) * (1.5 + 0.3 * P.hn(i, seed, 9)), 0.02))
		M.dpoly(pm, T, ring, Color(0.06, 0.05, 0.05, 0.85), Z)
		for k in 4:
			var rx := cc.x - 1.2 + k * 0.8
			M.dline(pm, T, Vector3(rx, -1.2, mh + 0.05), Vector3(rx + 0.2, -0.4, mh + 0.6), Color8(70, 66, 60))
			M.dline(pm, T, Vector3(rx, 1.2, mh + 0.05), Vector3(rx - 0.1, 0.5, mh + 0.5), Color8(70, 66, 60))
		for k in 9:
			var d := Vector3(xh + 0.8 + P.hn(k, seed, 21) * 2.4, (P.hn(k, seed, 23) - 0.5) * 2.0 * (ey - 0.6), 0.25)
			M.box(M.part(S, 0), T, d, Vector3(0.25 + 0.2 * P.hn(k, seed, 25), 0.2, 0.18), cd)
		M.dpoly(pa, T, [Vector3(xh, -hw, zt), Vector3(ex - 0.3, -hw - 0.2, zt), Vector3(ex - 0.2, hw, zt), Vector3(xh, hw + 0.2, zt)], Color(0.05, 0.05, 0.04, 0.45), Z)
	var ph := M.part(S, 0)   # headwall + wing walls
	var hz := 3.9 if not _ruin else 1.6
	M.box(ph, T, Vector3(xh + 0.35, 0, hz * 0.5), Vector3(0.35, hw + 0.3, hz * 0.5), C.ramp(CONC), Vector3(0.0, 0.0, 0.02))
	FAC._wall(ph, T, Vector3(xh + 0.7, 0, 0), Y, (hw + 0.3) * 2.0, hz, X, C.ramp(CONC), seed)
	for s in [-1.0, 1.0]:
		M.box(ph, T, Vector3(xh + 1.05, s * (hw + 0.05), hz * 0.4), Vector3(0.7, 0.28, hz * 0.4), cd, Vector3(1.0, 0.0, 0.0))
	M.box(ph, T, Vector3(xh + 0.35, 0, hz + 0.08), Vector3(0.42, hw + 0.35, 0.08), cd)
	var pd := M.part(S, 1)
	var df := Vector3(xh + 0.7, 0, 0)
	if _ruin:
		RO.quad(pd, T, df + X * 0.012 + Z * 0.9, Y * 1.2, Z * 0.8, Color8(18, 16, 14), X)
		for k in 5:
			M.dline(pd, T, df + X * 0.02 + Y * (-1.2 + k * 0.6) + Z * 1.6, df + X * 0.02 + Y * (-1.0 + k * 0.6) + Z * (1.0 + 0.5 * P.hn(k, seed, 31)), Color8(110, 70, 50), X)
		return
	var st: Array = C.ramp(Color8(96, 104, 98))
	RO.quad(pd, T, df + X * 0.012 + Z * 1.45, Y * 1.3, Z * 1.35, C.ramp(Color8(122, 70, 58))[2] if lock else st[1], X)
	M.dline(pd, T, df + X * 0.018 + Z * 0.15, df + X * 0.018 + Z * 2.75, C.ca(st[4], 0.85), X)   # double-leaf seam
	for i in 7:
		M.dline(pd, T, df + X * 0.016 - Y * 1.25 + Z * (0.3 + i * 0.38), df + X * 0.016 + Y * 1.25 + Z * (0.3 + i * 0.38), C.ca(st[0], 0.85), X)
	for s in [-1.0, 1.0]:
		M.dline(pd, T, df + X * 0.02 + Y * (s * 0.5) + Z * 1.2, df + X * 0.02 + Y * (s * 0.15) + Z * 1.2, Color8(200, 200, 190), X)   # locking bars
		FAC._jamb(pd, T, df + Y * (s * 1.45), X, 0.14, 0.15, 2.9)
	if lock:
		FAC._hz(pd, T, df + X * 0.02 - Y * 1.2 + Z * 0.4, df + X * 0.02 + Y * 1.2 + Z * 2.4, X, 9)
	M.box(pd, T, df + X * 0.12 + Z * 3.0, Vector3(0.12, 1.6, 0.1), C.ramp(STEEL))   # door hood
	M.dpoly(pd, T, [df + X * 0.02 + Y * 1.9 + Z * 3.5, df + X * 0.02 + Y * 2.25 + Z * 3.15, df + X * 0.02 + Y * 1.9 + Z * 2.8, df + X * 0.02 + Y * 1.55 + Z * 3.15], Color8(240, 120, 30), X)   # 1.1 placard
	M.dline(pd, T, df + X * 0.024 + Y * 1.8 + Z * 3.15, df + X * 0.024 + Y * 2.0 + Z * 3.15, DARK, X)
	RO.quad(pd, T, df + X * 0.014 - Y * 1.95 + Z * 3.2, Y * 0.55, Z * 0.3, SIGN, X)   # magazine board
	FAC._stencil(pd, T, df + X * 0.018 - Y * 1.95 + Z * 3.25, Y, X, 3, 0.14)
	M.dline(pd, T, df + X * 0.018 - Y * 2.4 + Z * 3.0, df + X * 0.018 - Y * 1.5 + Z * 3.0, CN_BLUE, X)
	for s in [-1.0, 1.0]:
		M.dpx(pd, T, df + X * 0.2 + Y * (s * 1.7) + Z * 2.7, LAMP_R if lock else AMBER, X)
	RO.flood(pd, pa, T, Vector3(xh + 0.7, hw * 0.7, 3.4), X)
	M.box(ph, T, Vector3(xh + 0.4, -hw * 0.55, hz + 0.17), Vector3(0.3, 0.6, 0.012), C.ramp(CONC), Vector3.ZERO, {"team": true})
	RO.quad(pa, T, Vector3((xh + ex) * 0.5 + 0.35, 0, zt), X * ((ex - xh) * 0.5 - 0.35), Y * 1.5, Color8(132, 132, 126), Z)   # door apron
	for s in [-1.0, 1.0]:
		M.dline(pa, T, Vector3(xh + 0.8, s * 1.5, zt + 0.001), Vector3(ex - 0.3, s * 1.5, zt + 0.001), YEL, Z)
	for i in 2:   # T-wall barricade traverse in front of the door
		_slab(M.part(S, 0), T, Vector3(ex - 0.9, -0.8 + i * 1.6, 0), Y, i, seed)
	var pv := M.part(S, 2)
	for k in 2:   # mushroom vents
		var vx := x0 + 3.2 + k * (xh - x0 - 4.2)
		M.cyl(pv, T, Vector3(vx, 0, mh + 0.35), Z, 0.14, 0.4, 6, C.ramp(STEEL), {"cap_t": 2})
		M.cyl(pv, T, Vector3(vx, 0, mh + 0.82), Z, 0.36, 0.08, 8, C.ramp(Color8(150, 154, 156)), {"cap_t": 3})
	_lmast(M.part(S, 1), T, Vector3(x0 + 1.4, -hw + 0.5, 0), 5.6)
	_lmast(M.part(S, 1), T, Vector3(xh - 0.4, hw + 0.15, 0), 5.6)
	var pf := M.part(S, 0)   # fire point + sand bin at the headwall
	var fp := Vector3(xh + 1.9, -hw + 0.35, 0)
	M.cyl(pf, T, fp + Z * 0.9, Z, 0.05, 0.9, 4, C.ramp(STEEL), {"edge": false})
	M.box(pf, T, fp + Z * 1.55, Vector3(0.06, 0.4, 0.3), C.ramp(Color8(190, 40, 34)))
	M.dpx(pf, T, fp + Vector3(0.07, -0.15, 1.6), Color8(240, 230, 220), X)
	M.box(pf, T, fp + Vector3(0.0, 0.75, 0.35), Vector3(0.3, 0.25, 0.35), C.ramp(Color8(176, 44, 38)), Vector3(0.02, 0.02, 0.02))


# ---------------------------------------------------------------- armory + suit bay (13.9c-6)
## Weapons issue + hazmat / CBRN suit fitting and suit-breach repair on the infantry path. Door side +x: the
## personnel entry from the decon hall (blast vestibule) and the issue window with its steel shutter; the long +y
## side: the issue door to the staging yard under an awning; the -y end: the taller suit bay with a roll-up door,
## open on rows of hanging suits (shut on lockdown), window band, breathing-air cylinder cage and compressor skid;
## roof: suit pressure-test chamber, HVAC, filter stacks, mast. Lockdown: doors sealed, shutters down.
static func armory(S: Array, T: Dictionary, ex: float, ey: float, lock: bool, seed: int) -> void:
	var pa := _apron(S, T, ex, ey, seed)
	var zt := zt_()
	var x0 := -ex + 0.6
	var x1 := ex - 2.0
	var cx := (x0 + x1) * 0.5
	var hx := (x1 - x0) * 0.5
	var ys := -ey + 1.2                 # suit bay -y end
	var ym := -ey * 0.25                # split
	var ya := ey - 1.3                  # armory +y end
	var ar := _block(S, T, Vector3(cx, (ym + ya) * 0.5, 0), hx, (ya - ym) * 0.5, 4.2, Color8(146, 150, 140), seed)
	var sb := _block(S, T, Vector3(cx, (ys + ym) * 0.5, 0), hx, (ym - ys) * 0.5, 5.4, Color8(156, 160, 158), seed + 3)
	var pm: Dictionary = ar[0]
	var ps: Dictionary = sb[0]
	var py := ya - 2.0   # personnel entry (blast vestibule) on the door side
	_block(S, T, Vector3(x1 + 0.8, py, 0), 0.8, 1.2, 3.0, CONC_D, seed + 7)
	_rdoor(M.part(S, 1), T, Vector3(x1 + 1.6, py, 0), Y, X, 0.6, 2.3, lock, not lock)
	var iy := ym + 1.9   # issue window with counter + steel shutter
	RO.quad(pm, T, Vector3(x1 + 0.012, iy, 1.6), Y * 1.1, Z * 0.5, Color8(30, 33, 36) if lock else Color8(196, 186, 150), X)
	if lock:
		for i in 4:
			M.dline(pm, T, Vector3(x1 + 0.02, iy - 1.1, 1.2 + i * 0.25), Vector3(x1 + 0.02, iy + 1.1, 1.2 + i * 0.25), Color8(84, 90, 94), X)
	else:
		for k in 5:   # weapons racked behind the counter
			M.dline(pm, T, Vector3(x1 + 0.016, iy - 0.9 + k * 0.42, 1.25), Vector3(x1 + 0.016, iy - 0.75 + k * 0.42, 2.0), Color8(46, 50, 52), X)
	M.box(pm, T, Vector3(x1 + 0.25, iy, 1.05), Vector3(0.25, 1.2, 0.06), C.ramp(STEEL))
	RO.quad(pm, T, Vector3(x1 + 0.012, iy, 3.45), Y * 1.6, Z * 0.26, SIGN, X)
	FAC._stencil(pm, T, Vector3(x1 + 0.016, iy, 3.48), Y, X, 6, 0.18)
	M.dline(pm, T, Vector3(x1 + 0.016, ym + 0.3, 3.0), Vector3(x1 + 0.016, ya - 0.3, 3.0), CN_BLUE, X)
	RO.flood(pm, pa, T, Vector3(x1, ya - 0.6, 3.6), X)
	for k in 2:   # suit bay window band on the door side
		RO.window(ps, T, Vector3(x1, ys + 1.3 + k * 2.0, 4.1), 1.4, 0.5, X, not lock, lock)
	RO.quad(ps, T, Vector3(x1 + 0.012, (ys + ym) * 0.5, 2.6), Y * 1.4, Z * 0.24, SIGN, X)
	FAC._stencil(ps, T, Vector3(x1 + 0.016, (ys + ym) * 0.5, 2.62), Y, X, 5, 0.17, Color8(240, 200, 60))
	var bw := minf(hx - 0.8, 2.2)
	var bc := Vector3(cx, ys, 0)   # suit bay roll-up door on the -y end
	_rdoor(M.part(S, 1), T, bc, X, -Y, bw, 3.4, lock, not lock)
	if not lock:
		_suits(M.part(S, 1), T, bc - Y * 0.03, X, -Y, bw - 0.2, seed)
		M.dpoly(pa, T, [bc + Vector3(-bw, -0.1, zt), bc + Vector3(bw, -0.1, zt), bc + Vector3(bw + 0.5, -1.0, zt), bc + Vector3(-bw - 0.5, -1.0, zt)], POOL, Z)
	var ay := ya   # issue door on the +y side under an awning
	_rdoor(M.part(S, 1), T, Vector3(cx + hx * 0.2, ay, 0), X, Y, 1.0, 2.6, lock, not lock)
	var paw := M.part(S, 2)
	M.box(paw, T, Vector3(cx + hx * 0.2, ay + 0.55, 3.3), Vector3(1.7, 0.55, 0.05), C.ramp(OLIVE))
	for s in [-1.0, 1.0]:
		M.dline(paw, T, Vector3(cx + hx * 0.2 + s * 1.6, ay + 1.0, 3.25), Vector3(cx + hx * 0.2 + s * 1.6, ay + 1.0, ZS), Color8(60, 64, 66))
	_side(ps, T, Vector3(x0, (ys + ym) * 0.5, 0), Y, -X, lock)
	var pc := M.part(S, 0)   # breathing-air cylinder cage + compressor skid beside the suit bay
	var cc := Vector3(x1 + 1.0, ys + 0.9, 0)
	if cc.x + 0.6 < ex:
		M.box(pc, T, cc + Z * 0.06, Vector3(0.55, 0.8, 0.06), C.ramp(CONC))
		for k in 6:
			M.cyl(pc, T, cc + Vector3(-0.25 + (k % 2) * 0.5, -0.55 + (k / 2) * 0.55, 0.75), Z, 0.14, 0.62, 6, C.ramp(Color8(60, 120, 170) if k % 3 else Color8(220, 220, 214)), {"cap_t": 3})
		for k in 4:
			M.dline(pc, T, cc + Vector3(0.55, -0.8 + k * 0.53, 0.12), cc + Vector3(0.55, -0.8 + k * 0.53, 1.5), Color8(64, 68, 70), X)
		M.dline(pc, T, cc + Vector3(0.55, -0.8, 1.5), cc + Vector3(0.55, 0.8, 1.5), Color8(64, 68, 70), X)
		var kc := cc + Y * 2.0
		M.box(pc, T, kc + Z * 0.55, Vector3(0.5, 0.7, 0.5), C.ramp(Color8(60, 92, 120)), Vector3(0.03, 0.03, 0.03))
		for k in 4:
			M.dline(pc, T, kc + Vector3(0.51, -0.5 + k * 0.32, 0.25), kc + Vector3(0.51, -0.5 + k * 0.32, 0.85), C.ca(DARK, 0.8), X)
		M.dpx(pc, T, kc + Vector3(0.52, 0.55, 0.9), LAMP_R if lock else LAMP_G, X)
	var pr: Dictionary = sb[2]   # suit pressure-test chamber + filter stacks on the suit bay roof
	var sc := Vector3(cx - hx * 0.3, (ys + ym) * 0.5, 0)
	M.cyl(pr, T, sc + Z * 6.15, Y, 0.7, minf(1.3, (ym - ys) * 0.5 - 0.4), 12, C.ramp(Color8(200, 204, 206)), {"cap_t": 3})
	M.cyl(pr, T, sc + Z * 6.15, Y, 0.74, 0.05, 12, C.ramp(CN_BLUE), {"cap_t": 0})
	M.dpx(pr, T, sc + Vector3(0.71, 0, 6.2), AMBER if lock else LAMP_G, X)
	for k in 2:
		M.cyl(pr, T, Vector3(cx + hx * 0.5, ys + 0.8 + k * 1.2, 5.4 + 0.9), Z, 0.2, 0.9, 8, C.ramp(STEEL), {"cap_t": 2})
	_hvac(ar[2], T, Vector3(cx - hx * 0.3, (ym + ya) * 0.5 + 0.8, 4.2))
	_hvac(ar[2], T, Vector3(cx + hx * 0.35, (ym + ya) * 0.5 - 0.6, 4.2))
	M.box(ar[1], T, Vector3(cx, (ym + ya) * 0.5, 4.21), Vector3(0.9, 0.9, 0.012), C.ramp(CONC), Vector3.ZERO, {"team": true})
	M.cyl(ar[2], T, Vector3(x0 + 0.5, ya - 0.5, 4.2 + 2.0), Z, 0.05, 2.0, 4, C.ramp(DARK), {"edge": false})
	M.dpx(ar[2], T, Vector3(x0 + 0.5, ya - 0.5, 8.3), LAMP_R)


# ---------------------------------------------------------------- aid station + quarantine bay (13.9c-6)
## Triage + nanite-exposure treatment, attached to the infantry decon hall (flush on the -y side). Door side +x: the
## triage entrance under a canopy (double doors, red-cross sign, stretcher kerb stripes, a stretcher trolley); the
## ward with lit, blinded windows, oxygen cylinder rack and clinical waste bins on +y; the far -x end: the sealed
## quarantine bay, a taller module in a hazard band with its own airlock, negative-pressure HEPA units and exhaust
## stacks on the roof and an amber isolation lamp. Roof: red-cross panel, HVAC. Lockdown: doors sealed, red lamps.
static func aid_station(S: Array, T: Dictionary, ex: float, ey: float, lock: bool, seed: int) -> void:
	var pa := _apron(S, T, ex, ey, seed)
	var zt := zt_()
	var x0 := -ex + 0.9
	var xq := x0 + 3.8
	var x1 := ex - 2.0
	var y0 := -ey + 0.05
	var y1 := ey - 0.9
	var cy := (y0 + y1) * 0.5
	var hy := (y1 - y0) * 0.5
	var wd := _block(S, T, Vector3((xq + x1) * 0.5, cy, 0), (x1 - xq) * 0.5, hy, 3.8, MED_W, seed)
	var qb := _block(S, T, Vector3((x0 + xq) * 0.5, cy, 0), (xq - x0) * 0.5, hy, 4.4, Color8(186, 188, 180), seed + 5)
	var pw: Dictionary = wd[0]
	var pq: Dictionary = qb[0]
	for nl in [Y, -X]:   # quarantine hazard band
		var fc: Vector3 = Vector3((x0 + xq) * 0.5, cy, 0) + (Y * hy if nl == Y else -X * (xq - x0) * 0.5)
		var al := RO._along(nl)
		var ln := (xq - x0) if nl == Y else hy * 2.0
		FAC._hz(pq, T, fc + nl * 0.014 - al * (ln * 0.5 - 0.1) + Z * 3.6, fc + nl * 0.014 + al * (ln * 0.5 - 0.1) + Z * 3.6, nl, 12)
		FAC._hz(pq, T, fc + nl * 0.014 - al * (ln * 0.5 - 0.1) + Z * 3.75, fc + nl * 0.014 + al * (ln * 0.5 - 0.1) + Z * 3.75, nl, 12)
	var dy := cy + hy * 0.25   # triage entrance + canopy on the door side
	_rdoor(M.part(S, 1), T, Vector3(x1, dy, 0), Y, X, 0.9, 2.5, lock, not lock)
	var pc := M.part(S, 2)
	M.box(pc, T, Vector3(x1 + 0.95, dy, 3.25), Vector3(0.95, 1.5, 0.07), C.ramp(MED_W))
	M.dline(pc, T, Vector3(x1 + 1.9, dy - 1.4, 3.18), Vector3(x1 + 1.9, dy + 1.4, 3.18), MED_R, X)
	for s in [-1.0, 1.0]:
		M.dline(pc, T, Vector3(x1 + 1.8, dy + s * 1.4, 3.2), Vector3(x1 + 1.8, dy + s * 1.4, ZS), Color8(70, 74, 76))
	RO.quad(pw, T, Vector3(x1 + 0.014, dy - 1.5, 2.6), Y * 0.3, Z * 0.3, Color8(236, 236, 230), X)   # red-cross sign
	M.dline(pw, T, Vector3(x1 + 0.02, dy - 1.7, 2.6), Vector3(x1 + 0.02, dy - 1.3, 2.6), MED_R, X)
	M.dline(pw, T, Vector3(x1 + 0.02, dy - 1.5, 2.4), Vector3(x1 + 0.02, dy - 1.5, 2.8), MED_R, X)
	for i in 4:   # stretcher kerb stripes
		M.dline(pa, T, Vector3(x1 + 0.3 + i * 0.4, dy - 0.9, zt + 0.001), Vector3(x1 + 0.3 + i * 0.4, dy + 0.9, zt + 0.001), YEL if i % 2 == 0 else STENCIL, Z)
	var ptr := M.part(S, 1)   # stretcher trolley
	var tc := Vector3(x1 + 1.0, y0 + 0.7, 0)
	M.box(ptr, T, tc + Z * 0.8, Vector3(0.8, 0.28, 0.05), C.ramp(Color8(210, 212, 208)))
	M.box(ptr, T, tc + Vector3(-0.5, 0, 0.9), Vector3(0.2, 0.24, 0.06), C.ramp(Color8(150, 190, 214)))
	for l in [Vector3(-0.7, -0.24, 0), Vector3(0.7, -0.24, 0), Vector3(-0.7, 0.24, 0), Vector3(0.7, 0.24, 0)]:
		M.dline(ptr, T, tc + l + Z * 0.75, tc + l + Z * 0.15, Color8(80, 84, 86))
	for k in 3:   # ward windows on the +y side, blinds half down
		var wx := xq + 0.9 + k * 1.5
		if wx < x1 - 0.5:
			RO.window(pw, T, Vector3(wx, y1, 2.0), 0.9, 0.9, Y, not lock, lock)
			if not lock:
				M.dline(pw, T, Vector3(wx - 0.4, y1 + 0.02, 2.3), Vector3(wx + 0.4, y1 + 0.02, 2.3), Color8(200, 196, 180), Y)
	var oc := Vector3(xq + 0.5, y1 + 0.45, 0)   # oxygen cylinder rack
	for k in 4:
		M.cyl(M.part(S, 0), T, oc + Vector3(k * 0.32, 0, 0.7), Z, 0.12, 0.6, 6, C.ramp(Color8(70, 140, 90) if k % 2 == 0 else Color8(220, 222, 218)), {"cap_t": 3})
	M.dline(M.part(S, 1), T, oc + Vector3(-0.2, 0.15, 1.0), oc + Vector3(1.2, 0.15, 1.0), Color8(60, 64, 66))
	var qa := Vector3(x0, cy + hy * 0.15, 0)   # quarantine airlock on the -x end
	_block(S, T, qa - X * 0.35, 0.35, 1.1, 3.0, Color8(176, 178, 170), seed + 9)
	_rdoor(M.part(S, 1), T, qa - X * 0.7, Y, -X, 0.6, 2.3, lock, false)
	M.dpx(M.part(S, 1), T, qa + Vector3(-0.8, 1.3, 3.0), LAMP_R if lock else AMBER, -X)
	RO.quad(pq, T, Vector3((x0 + xq) * 0.5, y1 + 0.014, 2.4), X * 1.4, Z * 0.22, SIGN, Y)
	FAC._stencil(pq, T, Vector3((x0 + xq) * 0.5, y1 + 0.018, 2.42), X, Y, 6, 0.16, Color8(240, 200, 60))
	for k in 2:   # clinical waste bins
		M.box(M.part(S, 0), T, Vector3(x0 + 0.6 + k * 0.7, y1 + 0.45, 0.42), Vector3(0.28, 0.3, 0.3), C.ramp(Color8(214, 176, 40)), Vector3(0.02, 0.02, 0.02))
	var pr: Dictionary = qb[2]   # HEPA units + exhaust stacks on the quarantine roof
	for k in 2:
		var hc := Vector3(x0 + 0.9 + k * 1.8, cy - hy * 0.3, 4.4)
		M.box(pr, T, hc + Z * 0.4, Vector3(0.6, 0.5, 0.4), C.ramp(Color8(170, 174, 176)), Vector3(0.03, 0.03, 0.03))
		for j in 4:
			M.dline(pr, T, hc + Vector3(0.61, -0.35 + j * 0.23, 0.15), hc + Vector3(0.61, -0.35 + j * 0.23, 0.65), C.ca(DARK, 0.75), X)
		M.cyl(pr, T, hc + Vector3(-0.2, 0.55, 1.2), Z, 0.12, 0.6, 6, C.ramp(STEEL), {"cap_t": 2})
	M.dpx(pr, T, Vector3(x0 + 0.3, cy + hy * 0.6, 4.75), LAMP_R if lock else AMBER)
	var rc := Vector3((xq + x1) * 0.5, cy, 3.81)   # red-cross roof panel
	RO.quad(wd[1], T, rc, X * 1.2, Y * 1.2, Color8(236, 236, 230), Z)
	RO.quad(wd[1], T, rc + Z * 0.002, X * 0.85, Y * 0.25, MED_R, Z)
	RO.quad(wd[1], T, rc + Z * 0.002, X * 0.25, Y * 0.85, MED_R, Z)
	_hvac(wd[2], T, Vector3(xq + 0.9, cy + hy * 0.55, 3.8))


# ---------------------------------------------------------------- Sentinel barracks (13.9c-6 ready room, 13.9c-10)
## FACB7-4 (owner 13.9c-14): the Sentinel barracks as a 3-storey hardened high-tech block with a rooftop landing pad
## for the CN Vanta rotorless gunship (json roof_pad: TLOF 7 x 15 m, deck 11.6 m). Ground floor: blast-resistant
## concrete with armoured slits, the blast-door vestibule (door side), SENTINEL sign, guard camera domes, the backup
## generator skid; floors 2 + 3: dark composite armour cladding, narrow armoured window slots with cyan floor LED bands,
## angled armour fins. Roof: the helideck on stub columns (anti-skid deck, yellow TLOF edge, touchdown / positioning
## circle, CN letters, green edge lights on the deck rim, safety net brackets, deck floodlights on posts, a windsock
## mast with its red obstruction lamp, the deck stair from the roof hatch, a refuel / rearm hose cabinet).
## Lockdown: shutters, red bands, door sealed, deck lights red. Ruin: collapsed 3.4 m shell (the pad is gone).
static func barracks(S: Array, T: Dictionary, ex: float, ey: float, lock: bool, seed: int) -> void:
	var pa := _apron(S, T, ex, ey, seed)
	var x0 := -ex + 0.4
	var x1 := ex - 2.0
	var y0 := -ey + 0.3
	var y1 := ey - 0.3
	var cx := (x0 + x1) * 0.5
	var cy := (y0 + y1) * 0.5
	var hx := (x1 - x0) * 0.5
	var hy := (y1 - y0) * 0.5
	if _ruin:
		_barracks_ruin(S, T, ex, ey, cx, cy, hx, hy, seed)
		return
	var c := Vector3(cx, cy, 0)
	var z1 := 3.6
	var zr := 10.8
	var g := _block(S, T, c, hx, hy, z1, Color8(140, 140, 132), seed)   # hardened ground floor
	var pg: Dictionary = g[0]
	var dy := clampf(2.0, -hy + 1.4, hy - 1.4)   # the door (json [24,7]) sits 2 m toward local +y on the door face
	for nl in [X, Y, -X, -Y]:
		var al := RO._along(nl)
		var ln: float = (hy if absf(nl.x) > 0.5 else hx) * 2.0
		var fc: Vector3 = c + nl * (hx if absf(nl.x) > 0.5 else hy)
		var nw := int(ln / 2.6)
		for k in nw:
			var u := -ln * 0.5 + (k + 0.5) * ln / nw
			if nl == X and absf(fc.y + u - dy) < 1.9:
				continue
			RO.quad(pg, T, fc + nl * 0.012 + al * u + Z * 2.5, al * 0.55, Z * 0.13, Color8(24, 30, 36) if lock else GLASS, nl)
	var ux := hx + 0.25   # floors 2 + 3: armour-clad block (slight overhang)
	var uy := hy + 0.25
	var clad := Color8(70, 78, 84)
	var pu := M.part(S, 0)
	M.box(pu, T, c + Z * (z1 + zr) * 0.5, Vector3(ux, uy, (zr - z1) * 0.5), C.ramp(clad), Vector3(0.04, 0.04, 0.04))
	_band(M.part(S, 0), T, c, ux, uy, z1 + 0.08, lock, Color8(168, 170, 164))
	for fl in 2:
		var fz := z1 + fl * 3.6
		for nl in [X, Y, -X, -Y]:
			var al := RO._along(nl)
			var ln: float = (uy if absf(nl.x) > 0.5 else ux) * 2.0
			var fc: Vector3 = c + nl * (ux if absf(nl.x) > 0.5 else uy)
			var nw := int(ln / 1.25)
			for k in nw:   # narrow armoured window slots between composite panels
				var u := -ln * 0.5 + (k + 0.5) * ln / nw
				var lit := not lock and P.hn(k + fl * 13, seed, int(nl.x * 7.0 + nl.y * 3.0) + 20) < 0.62
				RO.quad(pu, T, fc + nl * 0.012 + al * u + Z * (fz + 1.85), al * 0.16, Z * 0.95, Color8(22, 26, 30), nl)
				RO.quad(pu, T, fc + nl * 0.016 + al * u + Z * (fz + 1.85), al * 0.11, Z * 0.88, Color8(86, 92, 96) if lock else (C.ca(Color8(150, 220, 255), 0.85) if lit else Color8(34, 56, 72)), nl)
				M.dline(pu, T, fc + nl * 0.014 + al * (u + 0.62) + Z * (fz + 0.3), fc + nl * 0.014 + al * (u + 0.62) + Z * (fz + 3.3), C.ca(C.ramp(clad)[0], 0.85), nl)
		_band(M.part(S, 1), T, c, ux, uy, fz + 3.5, lock, Color8(168, 170, 164))
	for nl in [X, -Y]:   # angled armour fins on the two camera faces
		var al := RO._along(nl)
		var ln: float = (uy if absf(nl.x) > 0.5 else ux) * 2.0
		_fins(M.part(S, 1), T, c + nl * (ux if absf(nl.x) > 0.5 else uy), al, nl, ln - 0.5, z1 + 0.3, zr - 0.15, 2.5, 0.3, Color8(150, 154, 150))
	var pp := M.part(S, 2)   # parapet stencil band + SENTINEL sign
	RO.quad(pg, T, c + X * (hx + 0.014) + Y * dy + Z * 3.2, Y * 1.5, Z * 0.24, SIGN, X)
	FAC._stencil(pg, T, c + X * (hx + 0.018) + Y * dy + Z * 3.22, Y, X, 8, 0.18)
	M.dline(pg, T, c + X * (hx + 0.018) + Y * (dy - 1.4) + Z * 2.92, c + X * (hx + 0.018) + Y * (dy + 1.4) + Z * 2.92, CN_BLUE, X)
	var vx := cx + hx   # blast-door vestibule on the door face
	_block(S, T, Vector3(vx + 0.75, dy, 0), 0.75, 1.25, 3.0, CONC_D, seed + 7)
	_rdoor(M.part(S, 1), T, Vector3(vx + 1.5, dy, 0), Y, X, 0.7, 2.3, lock, not lock)
	RO.flood(pg, pa, T, Vector3(vx, dy - 2.2, 3.0), X)
	var pb := M.part(S, 0)
	for k in 3:   # bollards in front of the vestibule
		M.cyl(pb, T, Vector3(ex - 0.25, dy - 1.2 + k * 1.2, 0.42), Z, 0.13, 0.42, 6, C.ramp(YEL), {"cap_t": 3})
	var gc := Vector3(vx + 1.0, dy - 2.9, 0)   # backup generator skid beside the vestibule
	if gc.y - 0.8 > -ey:
		M.box(pb, T, gc + Z * 0.75, Vector3(0.65, 0.75, 0.7), C.ramp(OLIVE), Vector3(0.03, 0.03, 0.03))
		for k in 4:
			M.dline(pb, T, gc + Vector3(0.66, -0.5 + k * 0.33, 0.35), gc + Vector3(0.66, -0.5 + k * 0.33, 1.2), C.ca(DARK, 0.8), X)
		M.cyl(pb, T, gc + Vector3(-0.2, 0.3, 1.7), Z, 0.08, 0.25, 6, C.ramp(DARK), {"cap_t": 0})
		M.dpx(pb, T, gc + Vector3(0.67, 0.5, 1.2), AMBER if lock else LAMP_G, X)
	for k in [Vector3(hx, -hy, 0), Vector3(hx, hy, 0), Vector3(-hx, -hy, 0)]:   # camera domes on the ground-floor corners
		var cc: Vector3 = c + k + Vector3(signf(k.x) * 0.15, signf(k.y) * 0.15, 3.1)
		M.box(pg, T, cc, Vector3(0.12, 0.12, 0.06), C.ramp(STEEL))
		M.cyl(pg, T, cc - Z * 0.14, Z, 0.11, 0.08, 6, C.ramp(DARK), {"cap_t": 0})
	# roof: parapet, roof hatch + stair up to the deck
	M.box(pp, T, c + Z * (zr + 0.25), Vector3(ux, uy, 0.25), C.ramp(Color8(150, 152, 148)), Vector3(0.05, 0.05, 0.05))
	var zd := 11.6   # helideck on stub columns (json roof_pad deck_z)
	var dhx := minf(ex - 0.3, 7.6)
	var dhy := minf(ey - 0.2, 3.8)
	var dc := Vector3(-0.1, 0.0, 0)
	var pc := M.part(S, 2)
	for i in 3:
		for j in 2:
			var sc := dc + Vector3(-dhx + 1.6 + i * (2.0 * dhx - 3.2) * 0.5, (j * 2 - 1) * (dhy - 1.0), zr + 0.5)
			if sc.x < cx + ux - 0.3:
				M.box(pc, T, sc + Z * 0.0, Vector3(0.18, 0.18, 0.3), C.ramp(STEEL))
	var front := cx + ux   # the deck overhangs the door face on two raking steel struts
	for s in [-1.0, 1.0]:
		M.dline(pc, T, Vector3(front, s * (dhy - 0.6), zr - 1.6), Vector3(dc.x + dhx - 0.3, s * (dhy - 0.6), zd - 0.25), Color8(70, 74, 78), X)
		M.box(pc, T, Vector3(front + 0.06, s * (dhy - 0.6), zr - 1.6), Vector3(0.08, 0.14, 0.14), C.ramp(STEEL))
	var pdk := M.part(S, 3)
	M.box(pdk, T, dc + Z * (zd - 0.15), Vector3(dhx, dhy, 0.15), C.ramp(Color8(76, 80, 82)))
	var zt := zd + 0.004
	M.dpoly(pdk, T, [dc + Vector3(-dhx + 0.2, -dhy + 0.2, zt), dc + Vector3(dhx - 0.2, -dhy + 0.2, zt), dc + Vector3(dhx - 0.2, dhy - 0.2, zt), dc + Vector3(-dhx + 0.2, dhy - 0.2, zt)], Color8(60, 64, 66), Z)
	for e in [[Vector3(-dhx + 0.35, -dhy + 0.35, zt + 0.001), Vector3(dhx - 0.35, -dhy + 0.35, zt + 0.001)], [Vector3(dhx - 0.35, -dhy + 0.35, zt + 0.001), Vector3(dhx - 0.35, dhy - 0.35, zt + 0.001)],
			[Vector3(dhx - 0.35, dhy - 0.35, zt + 0.001), Vector3(-dhx + 0.35, dhy - 0.35, zt + 0.001)], [Vector3(-dhx + 0.35, dhy - 0.35, zt + 0.001), Vector3(-dhx + 0.35, -dhy + 0.35, zt + 0.001)]]:
		M.dline(pdk, T, dc + e[0], dc + e[1], YEL, Z)   # TLOF edge
		M.dline(pdk, T, dc + e[0] * 0.97, dc + e[1] * 0.97, YEL, Z)
	var tr := minf(dhy - 0.9, 2.6)
	for k in 24:   # touchdown / positioning circle
		var a0 := TAU * k / 24.0
		var a1 := TAU * (k + 1) / 24.0
		M.dline(pdk, T, dc + Vector3(cos(a0) * tr, sin(a0) * tr, zt + 0.002), dc + Vector3(cos(a1) * tr, sin(a1) * tr, zt + 0.002), YEL, Z)
		if k % 2 == 0:
			M.dline(pdk, T, dc + Vector3(cos(a0) * (tr - 0.25), sin(a0) * (tr - 0.25), zt + 0.002), dc + Vector3(cos(a1) * (tr - 0.25), sin(a1) * (tr - 0.25), zt + 0.002), YEL, Z)
	_gtext(pdk, T, dc + Vector3(0, 0, zt + 0.003), Y, 2, 1.1, STENCIL)   # "CN" in the circle
	for s in [-1.0, 1.0]:   # nose / tail alignment bars
		M.dline(pdk, T, dc + Vector3(s * (tr + 0.4), 0, zt + 0.002), dc + Vector3(s * (dhx - 0.8), 0, zt + 0.002), STENCIL, Z)
	for k in 16:   # deck rim lights (green / red on lockdown), sitting in the rim
		var t := float(k) / 16.0
		var pr: Vector3
		if k < 6:
			pr = Vector3(-dhx + 0.12 + t * 16.0 / 6.0 * (2.0 * dhx - 0.24), -dhy + 0.12, zd + 0.03)
		elif k < 8:
			pr = Vector3(dhx - 0.12, -dhy + 0.12 + (k - 6 + 0.5) / 2.0 * (2.0 * dhy - 0.24), zd + 0.03)
		elif k < 14:
			pr = Vector3(dhx - 0.12 - (k - 8) / 6.0 * (2.0 * dhx - 0.24), dhy - 0.12, zd + 0.03)
		else:
			pr = Vector3(-dhx + 0.12, dhy - 0.12 - (k - 14 + 0.5) / 2.0 * (2.0 * dhy - 0.24), zd + 0.03)
		M.box(pdk, T, dc + pr, Vector3(0.07, 0.07, 0.03), C.ramp(DARK))
		M.dpx(pdk, T, dc + pr + Z * 0.05, LAMP_R if lock else LAMP_G)
	if true:   # safety-net brackets under the deck rim on the two camera edges
		for k in 7:
			var ny := -dhy + 0.5 + k * (2.0 * dhy - 1.0) / 6.0
			M.dline(pdk, T, dc + Vector3(dhx, ny, zd - 0.28), dc + Vector3(dhx + 0.55, ny, zd - 0.05), Color8(60, 64, 66), X)
		M.dline(pdk, T, dc + Vector3(dhx + 0.55, -dhy + 0.5, zd - 0.05), dc + Vector3(dhx + 0.55, dhy - 0.5, zd - 0.05), Color8(80, 84, 86), X)
	for k in 5:
		var nx := -dhx + 0.6 + k * (2.0 * dhx - 1.2) / 4.0
		M.dline(pdk, T, dc + Vector3(nx, -dhy, zd - 0.28), dc + Vector3(nx, -dhy - 0.5, zd - 0.05), Color8(60, 64, 66), -Y)
	var pq := M.part(S, 3)   # deck furniture on the rear corner: windsock mast + lamp, floodlight posts, refuel cabinet
	var wc := dc + Vector3(-dhx + 0.35, -dhy + 0.35, zd)
	M.cyl(pq, T, wc + Z * 1.4, Z, 0.05, 1.4, 4, C.ramp(Color8(210, 210, 204)), {"edge": false})
	M.dpoly(pq, T, [wc + Vector3(0, 0, 2.7), wc + Vector3(0.9, 0.3, 2.55), wc + Vector3(0.9, 0.3, 2.4), wc + Vector3(0, 0, 2.35)], Color8(240, 120, 40), -Y)
	_olamp(pq, T, wc + Z * 2.8, 0.02, LAMP_R)
	for k in [Vector3(dhx - 0.3, -dhy + 0.3, 0), Vector3(-dhx + 0.3, dhy - 0.3, 0)]:
		var fc2: Vector3 = dc + k + Z * zd
		M.cyl(pq, T, fc2 + Z * 0.45, Z, 0.04, 0.45, 4, C.ramp(DARK), {"edge": false})
		M.box(pq, T, fc2 + Z * 0.95, Vector3(0.14, 0.14, 0.08), C.ramp(STEEL))
		M.dpx(pq, T, fc2 + Z * 0.9, LAMP_W)
	var rc := dc + Vector3(-dhx + 0.5, dhy - 0.45, zd)   # refuel / rearm hose cabinet on the deck edge
	M.box(pq, T, rc + Z * 0.45, Vector3(0.35, 0.25, 0.45), C.ramp(Color8(196, 60, 46)), Vector3(0.02, 0.02, 0.02))
	M.dpx(pq, T, rc + Vector3(0.36, 0, 0.7), AMBER if lock else LAMP_G, X)
	var sx := cx - hx + 0.5   # deck stair from the roof hatch (rear, under the deck edge)
	for k in 4:
		M.box(pc, T, Vector3(sx + k * 0.22, -uy + 0.7, zr + 0.6 + k * 0.2), Vector3(0.11, 0.4, 0.025), C.ramp(STEEL))
	M.box(M.part(S, 1), T, c + Vector3(hx * 0.3, -hy * 0.5, zr + 0.55), Vector3(0.6, 0.45, 0.05), C.ramp(Color8(150, 154, 156)))   # vent under deck


static func _barracks_ruin(S: Array, T: Dictionary, ex: float, ey: float, cx: float, cy: float, hx: float, hy: float, seed: int) -> void:
	var hz := 3.4
	var col := Color8(96, 92, 86)
	var bl := _block(S, T, Vector3(cx, cy, 0), hx, hy, hz, col, seed)
	var pm: Dictionary = bl[0]
	var rp: Array = C.ramp(col)
	for k in 9:   # broken wall stumps standing above the collapsed slab, rubble, scorching, twisted deck girders
		var t := -1.0 + 2.0 * (float(k) + 0.5) / 9.0
		var zz := 0.5 + 2.2 * P.hn(k, seed, 11)
		M.box(M.part(S, 1), T, Vector3(cx + t * hx, cy - hy + 0.2, hz + zz * 0.5), Vector3(hx / 9.0, 0.2, zz * 0.5), rp)
		M.box(M.part(S, 1), T, Vector3(cx + hx - 0.2, cy + t * hy, hz + zz * 0.4), Vector3(0.2, hy / 9.0, zz * 0.4), rp)
	for k in 22:
		var sd := k % 4
		var u := (P.hn(k, seed, 3) - 0.5) * 2.0
		var off := 0.4 + 0.9 * P.hn(k, seed, 5)
		var d := Vector3(cx + u * hx, cy - hy - off, 0.2) if sd == 0 else (Vector3(cx + hx + off, cy + u * hy, 0.2) if sd == 1 else (Vector3(cx + u * hx, cy + hy + off * 0.5, 0.2) if sd == 2 else Vector3(cx - hx - off * 0.5, cy + u * hy, 0.2)))
		d.x = clampf(d.x, -ex + 0.4, ex - 0.4)
		d.y = clampf(d.y, -ey + 0.4, ey - 0.4)
		var r := 0.25 + 0.35 * P.hn(k, seed, 7)
		M.box(M.part(S, 0), T, d + Z * r * 0.4, Vector3(r, r * 0.8, r * 0.6), C.ramp(CONC_D) if k % 3 else C.ramp(Color8(70, 66, 60)), Vector3(r * 0.4, r * 0.4, r * 0.3))
	for nl in [X, -Y]:
		for k in 5:
			var u := (P.hn(k, seed, 13) - 0.5) * 1.6
			var fc: Vector3 = Vector3(cx, cy, 0) + (nl * hx if absf(nl.x) > 0.5 else nl * hy) + nl * 0.016 + RO._along(nl) * u * (hy if absf(nl.x) > 0.5 else hx)
			M.dpoly(pm, T, [fc + Z * hz, fc + Z * (hz - 1.8) + RO._along(nl) * 0.4, fc + Z * (hz - 1.2) - RO._along(nl) * 0.3], Color(0.05, 0.05, 0.04, 0.55), nl)
	for k in 4:   # twisted deck girders
		var a := Vector3(cx - hx + 1.0 + k * hx * 0.5, cy - hy * 0.3, hz)
		M.dline(bl[2], T, a, a + Vector3(0.6, 0.4, 1.4 + 0.6 * P.hn(k, seed, 9)), Color8(70, 66, 62))
	M.dpoly(bl[1], T, [Vector3(cx - hx * 0.6, cy - hy * 0.5, hz + 0.01), Vector3(cx + hx * 0.5, cy - hy * 0.7, hz + 0.01), Vector3(cx + hx * 0.6, cy + hy * 0.6, hz + 0.01), Vector3(cx - hx * 0.4, cy + hy * 0.5, hz + 0.01)], Color(0.05, 0.05, 0.04, 0.7), Z)

# ---------------------------------------------------------------- fuel / rearm point (13.9c-6), flat
## Hot refuel / rearm apron, everything flush with the ground (aircraft and vehicles stand on it): two refuel pits
## with hose-reel lids in yellow pit boxes, a fuel line trench between them, grounding points, a marked rearm bay
## with hatched ammo-cart parking, painted lettering and arrows, drip stains, red fire-cart spots at the edge.
## Lockdown: red pit lamps (fuel valves shut).
static func fuel_point(S: Array, T: Dictionary, ex: float, ey: float, lock: bool, seed: int) -> void:
	var pa := _apron(S, T, ex, ey, seed, Color8(104, 106, 104))
	var zt := zt_() + 0.001
	M.dline(pa, T, Vector3(-ex + 0.3, -ey + 0.3, zt), Vector3(ex - 0.3, -ey + 0.3, zt), YEL, Z)
	M.dline(pa, T, Vector3(-ex + 0.3, ey - 0.3, zt), Vector3(ex - 0.3, ey - 0.3, zt), YEL, Z)
	var pits: Array = []
	if ey >= ex:
		pits = [Vector3(ex * 0.3, -ey * 0.45, 0), Vector3(ex * 0.3, ey * 0.45, 0)]
	else:
		pits = [Vector3(-ex * 0.45, ey * 0.3, 0), Vector3(ex * 0.45, ey * 0.3, 0)]
	for p in pits:
		var pc: Vector3 = p
		RO.quad(pa, T, pc + Z * zt, X * 0.75, Y * 0.55, Color8(54, 56, 58), Z)
		for e in [[Vector3(-0.8, -0.6, 0), Vector3(0.8, -0.6, 0)], [Vector3(0.8, -0.6, 0), Vector3(0.8, 0.6, 0)], [Vector3(0.8, 0.6, 0), Vector3(-0.8, 0.6, 0)], [Vector3(-0.8, 0.6, 0), Vector3(-0.8, -0.6, 0)]]:
			M.dline(pa, T, pc + (e[0] as Vector3) + Z * (zt + 0.001), pc + (e[1] as Vector3) + Z * (zt + 0.001), YEL, Z)
		var ring: Array = []
		for i in 10:
			ring.append(pc + Vector3(cos(TAU * i / 10.0) * 0.35, sin(TAU * i / 10.0) * 0.35, zt + 0.002))
		for i in 10:
			M.dline(pa, T, ring[i], ring[(i + 1) % 10], Color8(170, 50, 40), Z)
		M.dpx(pa, T, pc + Vector3(0.6, 0.45, zt + 0.003), LAMP_R if lock else LAMP_G, Z)
		M.dpx(pa, T, pc + Vector3(-0.6, -0.45, zt + 0.003), Color8(90, 200, 90), Z)   # grounding point
		M.dpx(pa, T, pc + Vector3(-0.55, -0.45, zt + 0.003), Color8(230, 210, 60), Z)
		FAC._stains(pa, T, pc + Z * ZS, Vector2(1.0, 0.8), 4, seed + int(absf(pc.y) * 10.0 + absf(pc.x) * 7.0))
		_gtext(pa, T, pc + Vector3(-1.6, 0, zt + 0.002), Y, 4, 0.5, STENCIL)
	var a: Vector3 = pits[0]   # fuel line trench grate between the pits
	var b: Vector3 = pits[1]
	var du := (b - a).normalized()
	var dv := Vector3(-du.y, du.x, 0)
	var n := int(a.distance_to(b) / 0.5)
	for i in range(2, n - 1):
		var q := a.lerp(b, (float(i) + 0.5) / n)
		RO.quad(pa, T, q + Z * zt, du * 0.18, dv * 0.12, Color8(44, 46, 48), Z)
	var rb := Vector3(-ex * 0.5, 0, zt) if ey >= ex else Vector3(0, -ey * 0.5, zt)   # rearm bay
	var rx := 1.0 if ey >= ex else 1.6
	var ry := 1.6 if ey >= ex else 1.0
	for e in [[Vector3(-rx, -ry, 0), Vector3(rx, -ry, 0)], [Vector3(rx, -ry, 0), Vector3(rx, ry, 0)], [Vector3(rx, ry, 0), Vector3(-rx, ry, 0)], [Vector3(-rx, ry, 0), Vector3(-rx, -ry, 0)]]:
		M.dline(pa, T, rb + (e[0] as Vector3), rb + (e[1] as Vector3), STENCIL, Z)
	for i in 6:
		var t := -0.85 + i * 0.34
		M.dline(pa, T, rb + Vector3(t * rx - 0.2, -ry + 0.1, 0.001), rb + Vector3(t * rx + 0.2, -ry + 0.5, 0.001), Color8(240, 120, 30), Z)
	for s in [-1.0, 1.0]:   # direction arrows
		var ac: Vector3 = (pits[0] as Vector3).lerp(pits[1], 0.5) + (Vector3(0, s * (ey - 1.6), 0) if ey < ex else Vector3(s * (ex - 1.6), 0, 0)) + Z * zt
		var u := Y if ey >= ex else X
		var v := Vector3(-u.y, u.x, 0)
		M.dpoly(pa, T, [ac + u * 0.7, ac + u * 0.1 + v * 0.4, ac + u * 0.1 + v * 0.15, ac - u * 0.6 + v * 0.15, ac - u * 0.6 - v * 0.15, ac + u * 0.1 - v * 0.15, ac + u * 0.1 - v * 0.4], STENCIL, Z)
	for s in [-1.0, 1.0]:   # fire-cart spots
		RO.quad(pa, T, Vector3(-ex + 0.7, s * (ey - 0.8), zt), X * 0.4, Y * 0.3, Color8(190, 40, 34), Z)


# ---------------------------------------------------------------- contaminated runoff tank (13.9c-6 fold-in)
## The APC wash's contaminated-runoff sump: a buried tank under a raised, bunded concrete lid (walkable) with two
## access manholes, hazard border and lettering, the inlet pipe coming through the link wall from the wash with its
## isolation valve, a level gauge / dosing pump box and a carbon-filter vent stack in the far corner with a warning
## placard. Lockdown: inlet valve shut (red lamp).
static func runoff(S: Array, T: Dictionary, ex: float, ey: float, lock: bool, seed: int) -> void:
	_apron(S, T, ex, ey, seed, Color8(112, 112, 106))
	var pl := M.part(S, 0)
	var cd: Array = C.ramp(CONC_D)
	M.box(pl, T, Vector3(0, 0, 0.2), Vector3(ex - 0.25, ey - 0.25, 0.2), cd, Vector3(0.04, 0.04, 0.04))
	var zl := 0.401
	var al := X if ex >= ey else Y
	var ac := Y if ex >= ey else X
	var la := maxf(ex, ey)
	var lc := minf(ex, ey)
	FAC._hz(pl, T, -al * (la - 0.4) - ac * (lc - 0.4) + Z * zl, al * (la - 0.4) - ac * (lc - 0.4) + Z * zl, Z, 14)
	FAC._hz(pl, T, -al * (la - 0.4) + ac * (lc - 0.4) + Z * zl, al * (la - 0.4) + ac * (lc - 0.4) + Z * zl, Z, 14)
	for k in 2:   # manholes
		var mc := al * (-la * 0.5 + k * la) + Z * zl
		var ring: Array = []
		for i in 10:
			ring.append(mc + Vector3(cos(TAU * i / 10.0) * 0.4, sin(TAU * i / 10.0) * 0.4, 0.001))
		M.dpoly(pl, T, ring, Color8(70, 72, 72), Z)
		for i in 3:
			M.dline(pl, T, mc + ac * (-0.2 + i * 0.2) - al * 0.3 + Z * 0.002, mc + ac * (-0.2 + i * 0.2) + al * 0.3 + Z * 0.002, Color8(96, 98, 98), Z)
	_gtext(pl, T, Z * (zl + 0.001), al, 3, 0.45, Color8(240, 200, 60))
	var pp := M.part(S, 1)   # inlet pipe from the wash side (+y local = toward the link wall when f = 3)
	var ip := al * (la * 0.15) + ac * (lc - 0.45)
	M.cyl(pp, T, ip + Z * 0.65, ac, 0.13, 0.45, 8, C.ramp(Color8(80, 110, 140)), {"cap_t": 2})
	M.cyl(pp, T, ip - ac * 0.4 + Z * 0.65, ac, 0.2, 0.04, 8, C.ramp(STEEL), {"cap_t": 2})
	M.box(pp, T, ip - ac * 0.4 + Z * 0.95, Vector3(0.06, 0.06, 0.14), C.ramp(Color8(200, 60, 40)))
	M.dpx(pp, T, ip - ac * 0.4 + Z * 1.12, LAMP_R if lock else LAMP_G)
	var pg := M.part(S, 1)   # level gauge + dosing pump, vent stack with carbon filter, placard
	var gp := al * (la - 0.8) - ac * (lc - 0.75)
	M.box(pg, T, gp + Z * 0.75, Vector3(0.25, 0.22, 0.35), C.ramp(Color8(60, 92, 120)), Vector3(0.02, 0.02, 0.02))
	M.dpx(pg, T, gp + Vector3(0.26, 0, 0.9), AMBER, X)
	var vp := -al * (la - 0.75) - ac * (lc - 0.7)
	M.cyl(pg, T, vp + Z * 1.1, Z, 0.07, 0.7, 6, C.ramp(STEEL), {"edge": false})
	M.cyl(pg, T, vp + Z * 1.95, Z, 0.22, 0.25, 8, C.ramp(Color8(60, 64, 66)), {"cap_t": 2})
	M.cyl(pg, T, vp + Z * 2.25, Z, 0.12, 0.05, 6, C.ramp(STEEL), {"cap_t": 3})
	M.box(pg, T, vp + al * 0.35 + Z * 0.95, (al * 0.3 + ac * 0.02 + Z * 0.2).abs(), C.ramp(Color8(240, 200, 60)))
	M.dpx(pg, T, vp + al * 0.35 + ac * 0.03 + Z * 0.95, Color8(30, 30, 30), ac)


# ================================================================ foot entry control point (13.9c-8): cn_checkpoint
## g7_fac_gatehouse replaces the old booth art for cn_checkpoint (entity_layer). 2x2 = 8 x 8 m in the south wall line
## (tile axes, +y = outside). West column (x -4..0): the pedestrian passage, a two-door mantrap: the outer blast door
## in the outside face, the interlock chamber with the ID / scan arch (seen through the armoured light well) and the
## reinforced inner door on the compound side; roof status lamps for each door. East column (x 0..4): the guard
## bunker: firing ports and vision blocks covering the approach, an armoured cupola with the remote weapon station,
## searchlight and camera; razor wire along the roof edge, ID reader at the outer door. States: built (both doors
## shut), open_out / open_in (one door open at a time), lockdown (both sealed, red), each with a _damaged copy.
const GH_TOP := 104


static func gatehouse(cv, o: Vector2, st_: String, seed: int) -> void:
	var S: Array = []
	var T := M.pose(o, 0.0)
	var lock := st_ == "lockdown"
	var oo := st_ == "open_out"
	var oi := st_ == "open_in"
	var conc: Array = C.ramp(CONC)
	var cd: Array = C.ramp(CONC_D)
	var pa := _apron(S, T, 4.0, 4.0, seed, Color8(112, 112, 108))
	var pf := M.part(S, 0)
	M.box(pf, T, Vector3(0, 0, 0.3), Vector3(4.0, 4.0, 0.3), cd, Vector3(0.1, 0.1, 0.0))
	var pw := M.part(S, 0)   # passage walls (west + party wall) and the bunker
	M.box(pw, T, Vector3(-3.55, 0, 2.7), Vector3(0.45, 3.95, 2.4), conc, Vector3(0.0, 0.0, 0.02))
	M.box(pw, T, Vector3(-0.45, 0, 2.7), Vector3(0.45, 3.95, 2.4), conc, Vector3(0.0, 0.0, 0.02))
	var pb := M.part(S, 0)
	M.box(pb, T, Vector3(1.95, 0, 2.6), Vector3(1.95, 3.95, 2.3), conc, Vector3(0.03, 0.03, 0.03))
	FAC._wall(pb, T, Vector3(1.95, 3.95, 0), X, 3.9, 4.9, Y, conc, seed)
	FAC._wall(pb, T, Vector3(3.9, 0, 0), Y, 7.9, 4.9, X, conc, seed + 1)
	FAC._wall(pw, T, Vector3(-2.0, 3.95, 0), X, 4.0, 4.9, Y, conc, seed + 2)
	for k in 2:   # firing ports (splayed embrasures) on the outside face + one on the east face
		var px := 0.9 + k * 2.0
		RO.quad(pb, T, Vector3(px, 3.962, 2.2), X * 0.55, Z * 0.2, cd[1], Y)
		RO.quad(pb, T, Vector3(px, 3.966, 2.2), X * 0.38, Z * 0.08, Color8(16, 18, 20), Y)
		M.dline(pb, T, Vector3(px - 0.55, 3.97, 1.98), Vector3(px + 0.55, 3.97, 1.98), C.ca(cd[0], 0.9), Y)
	RO.quad(pb, T, Vector3(3.912, 1.6, 2.2), Y * 0.38, Z * 0.08, Color8(16, 18, 20), X)
	for k in 3:   # vision blocks
		RO.quad(pb, T, Vector3(0.7 + k * 1.25, 3.962, 4.1), X * 0.22, Z * 0.1, Color8(26, 34, 40), Y)
		M.dline(pb, T, Vector3(0.55 + k * 1.25, 3.966, 4.14), Vector3(0.75 + k * 1.25, 3.966, 4.14), Color(0.75, 0.9, 1.0, 0.5), Y)
	var pr := M.part(S, 1)   # roof slab + parapet
	M.box(pr, T, Vector3(0, 0, 5.12), Vector3(4.0, 4.0, 0.12), cd)
	for e in [[Vector3(0, 3.85, 5.42), Vector3(4.0, 0.15, 0.18)], [Vector3(0, -3.85, 5.42), Vector3(4.0, 0.15, 0.18)], [Vector3(3.85, 0, 5.42), Vector3(0.15, 3.7, 0.18)], [Vector3(-3.85, 0, 5.42), Vector3(0.15, 3.7, 0.18)]]:
		M.box(pr, T, e[0], e[1], cd)
	RO.wire(M.part(S, 2), T, Vector3(-4.0, 3.85, 0), Vector3(4.0, 3.85, 0), 5.75)
	var plw := M.part(S, 1, 0.01)   # armoured light well over the interlock chamber (grating, scan glow)
	RO.quad(plw, T, Vector3(-2.0, 0.2, 5.245), X * 1.0, Y * 1.4, Color8(22, 26, 30), Z)
	for i in 6:
		M.dline(plw, T, Vector3(-2.95, -1.1 + i * 0.5, 5.25), Vector3(-1.05, -1.1 + i * 0.5, 5.25), Color8(96, 100, 104), Z)
	for i in 4:
		M.dline(plw, T, Vector3(-2.9 + i * 0.6, -1.15, 5.25), Vector3(-2.9 + i * 0.6, 1.55, 5.25), Color8(96, 100, 104), Z)
	if not lock:   # scan arch glow through the grating
		M.dline(plw, T, Vector3(-2.8, 0.45, 5.252), Vector3(-1.2, 0.45, 5.252), CN_BLUE, Z)
		M.dpx(plw, T, Vector3(-2.0, 0.45, 5.253), Color8(200, 240, 255), Z)
	for s in [[3.2, oo], [-3.2, oi]]:   # door status lamps on the roof (outer south, inner north)
		var lc := Vector3(-2.0, float(s[0]), 5.24)
		M.box(pr, T, lc + Z * 0.12, Vector3(0.28, 0.16, 0.12), C.ramp(STEEL))
		M.dpx(pr, T, lc + Vector3(0.0, 0.0, 0.26), LAMP_R if lock else (LAMP_G if bool(s[1]) else AMBER), Z)
	var pd := M.part(S, 1)   # outer blast door (outside face) with its lintel + ID reader + sign
	M.box(pd, T, Vector3(-2.0, 3.7, 4.1), Vector3(1.15, 0.28, 0.8), cd)
	var fo := Vector3(-2.0, 3.96, 0)
	if oo and not lock:
		RO.quad(pd, T, fo + Z * 1.65, X * 1.05, Z * 1.6, Color8(24, 26, 28), Y)
		M.dline(pd, T, fo + Y * 0.004 + Z * 3.1 - X * 0.95, fo + Y * 0.004 + Z * 3.1 + X * 0.95, Color8(220, 230, 240), Y)
		M.dline(pd, T, fo + Y * 0.004 + Z * 1.4 - X * 0.2, fo + Y * 0.004 + Z * 2.3 - X * 0.2, CN_BLUE, Y)   # the scan arch beyond
		M.dline(pd, T, fo + Y * 0.004 + Z * 1.4 + X * 0.2, fo + Y * 0.004 + Z * 2.3 + X * 0.2, CN_BLUE, Y)
		M.dpoly(pa, T, [fo + Vector3(-1.0, -0.2, ZS + 0.005), fo + Vector3(1.0, -0.2, ZS + 0.005), fo + Vector3(1.0, -2.6, ZS + 0.005), fo + Vector3(-1.0, -2.6, ZS + 0.005)], Color(1.0, 0.95, 0.8, 0.12), Z)
	else:
		var lc2: Array = C.ramp(Color8(122, 70, 58)) if lock else C.ramp(Color8(92, 98, 100))
		RO.quad(pd, T, fo + Z * 1.65, X * 1.05, Z * 1.6, lc2[1], Y)
		for i in 8:
			M.dline(pd, T, fo + Y * 0.004 - X * 1.0 + Z * (0.3 + i * 0.38), fo + Y * 0.004 + X * 1.0 + Z * (0.3 + i * 0.38), C.ca(lc2[0], 0.85), Y)
		for s in [-1.0, 1.0]:
			M.dline(pd, T, fo + Y * 0.006 + X * (s * 0.95) + Z * 0.2, fo + Y * 0.006 + X * (s * 0.95) + Z * 3.1, C.ca(lc2[4], 0.8), Y)
		if lock:
			FAC._hz(pd, T, fo + Y * 0.008 - X * 0.95 + Z * 0.3, fo + Y * 0.008 + X * 0.95 + Z * 3.0, Y, 9)
	for s in [-1.0, 1.0]:
		FAC._jamb(pd, T, fo + X * (s * 1.15), Y, 0.08, 0.3, 3.2)
	RO.quad(pd, T, Vector3(-2.0, 3.99, 4.2), X * 0.9, Z * 0.22, SIGN, Y)
	FAC._stencil(pd, T, Vector3(-2.0, 3.994, 4.22), X, Y, 3, 0.16)
	M.dline(pd, T, Vector3(-2.85, 3.994, 3.95), Vector3(-1.15, 3.994, 3.95), CN_BLUE, Y)
	M.box(pd, T, Vector3(0.35, 4.02, 1.3), Vector3(0.2, 0.06, 0.32), C.ramp(DARK))   # ID / biometric reader
	M.dpx(pd, T, Vector3(0.3, 4.09, 1.45), Color8(80, 220, 255), Y)
	M.dpx(pd, T, Vector3(0.4, 4.09, 1.15), LAMP_R if lock else LAMP_G, Y)
	M.dpx(pd, T, Vector3(-3.3, 4.0, 3.5), LAMP_R if lock else AMBER, Y)
	var fi := Vector3(-2.0, -3.96, 0)   # reinforced inner door (compound side)
	M.box(pd, T, Vector3(-2.0, -3.7, 4.1), Vector3(1.15, 0.28, 0.8), cd)
	if oi and not lock:
		RO.quad(pd, T, fi + Z * 1.6, X * 1.0, Z * 1.55, Color8(24, 26, 28), -Y)
	else:
		RO.quad(pd, T, fi + Z * 1.6, X * 1.0, Z * 1.55, C.ramp(Color8(122, 70, 58))[1] if lock else C.ramp(Color8(92, 98, 100))[1], -Y)
	var pq := M.part(S, 3)   # bunker cupola + RWS, searchlight, camera
	var Tr := M.sub(T, Vector3(2.0, 0.6, 5.24), 0.0)
	M.cyl(pq, Tr, Vector3(0, 0, 0.32), Z, 0.95, 0.32, 12, C.ramp(Color8(98, 104, 98)), {"cap_t": 2})
	for i in 6:
		var a := TAU * i / 6.0
		M.dpx(pq, Tr, Vector3(cos(a) * 0.96, sin(a) * 0.96, 0.4), Color8(26, 34, 40), Vector3(cos(a), sin(a), 0))
	M.box(pq, Tr, Vector3(0.0, 0.1, 0.82), Vector3(0.3, 0.36, 0.18), C.ramp(Color8(104, 112, 100)), Vector3(0.0, 0.0, 0.06))
	M.box(pq, Tr, Vector3(0.32, 0.12, 0.92), Vector3(0.1, 0.08, 0.08), C.ramp(DARK))
	M.dpx(pq, Tr, Vector3(0.33, 0.24, 0.94), GLASS, Y)
	TU.barrel(pq, Tr, 0.34, 1.4, PI * 0.5, 0.82, 0.045, 0.0, DARK, true)
	M.cyl(pq, T, Vector3(3.5, 3.4, 5.75), Vector3(0.3, 1, -0.3), 0.2, 0.18, 8, C.ramp(STEEL), {"cap_t": 4})
	M.dpx(pq, T, Vector3(3.58, 3.62, 5.7), LAMP_W)
	M.box(pq, T, Vector3(-3.7, 3.7, 5.8), Vector3(0.1, 0.18, 0.09), C.ramp(Color8(210, 210, 200)))
	M.dpx(pq, T, Vector3(-3.7, 3.9, 5.8), Color8(60, 200, 255), Y)
	M.box(pr, T, Vector3(2.4, -2.4, 5.25), Vector3(0.7, 0.7, 0.012), C.ramp(CONC), Vector3.ZERO, {"team": true})
	M.cyl(pr, T, Vector3(3.4, -3.3, 6.2), Z, 0.04, 0.95, 4, C.ramp(DARK), {"edge": false})
	M.dpx(pr, T, Vector3(3.4, -3.3, 7.2), LAMP_R)
	_fin_piece(cv, S, o, seed)


static func build_gatehouse(out: Dictionary) -> void:
	var co: Array = K.canvas(2, GH_TOP)
	var o: Vector2 = co[1]
	var entry := {"size": 2, "pivot": [int(o.x), int(o.y)], "fw": int(co[0].w), "fh": int(co[0].h), "states": {},
		"fits": "cn_checkpoint 2x2 foot entry control point in the south wall line, pivot = centre; passage on the west column (mantrap cells), guard bunker east; states built / open_out / open_in / lockdown (+ _damaged)"}
	for nm in ["built", "open_out", "open_in", "lockdown"]:
		var cv = K.canvas(2, GH_TOP)[0]
		gatehouse(cv, o, nm, 6100)
		var base = H.copy(cv)
		C.selout(cv)
		_put(out, entry, "g7_fac_gatehouse", nm, cv)
		var dm = H.copy(base)
		K.damage(dm, o, 2, 9500 + nm.length())
		C.selout(dm)
		_put(out, entry, "g7_fac_gatehouse", nm + "_damaged", dm)
	out.manifest.buildings["g7_fac_gatehouse"] = entry


# ================================================================ wash link walls (13.9c-9): cn_link_wall pieces
## g7_fac_linkwall SHEET, one piece per 1x1 cn_link_wall cell (pivot = cell centre, 2x2-sized canvas). Column =
## side * 4 + (1 if a link cell is north) + (2 if one is south); side 0 = the wash / gate lies on +x (west run),
## 1 = on -x (east run). The wall body stands on the gate bastions' line (3.3 m toward the wash from the cell centre)
## at the gate layers' thickness and height (2.9 m footing, 2.5 m body, 5.5 m, capping beam at the bastion beam
## height), so outer gate, link walls and inner gate read as one enclosure; on the far side a sloped counterfort and
## a HESCO berm fill the rest of the cell. Ends without a link neighbour run on into the gate bastions. Row 0
## intact, 1 damaged.
const LW_TOP := 70


static func link_piece(cv, o: Vector2, side: int, n: bool, s: bool, seed: int) -> void:
	var S: Array = []
	var T := M.pose(o, 0.0)
	var sg := 1.0 if side == 0 else -1.0
	var ax := 3.3 * sg
	var y0 := -2.0 if n else -2.3
	var y1 := 2.0 if s else 3.05
	var ym := (y0 + y1) * 0.5
	var hl := (y1 - y0) * 0.5
	var conc: Array = C.ramp(CONC)
	var cd: Array = C.ramp(CONC_D)
	var pw := M.part(S, 0)
	M.box(pw, T, Vector3(ax, ym, 0.3), Vector3(1.45, hl, 0.3), cd)
	M.box(pw, T, Vector3(ax, ym, 2.9), Vector3(1.25, hl, 2.6), conc, Vector3(0.0, 0.0, 0.03))
	for nl in [X, -X]:
		FAC._wall(pw, T, Vector3(ax, ym, 0) + nl * 1.25, Y, hl * 2.0, 5.5, nl, conc, seed + (1 if nl == X else 2), 2.0)
	var fw := -X * sg   # wash-facing side: blue band, hazard foot
	var fwc := Vector3(ax, ym, 0) + fw * 1.25
	M.dline(pw, T, fwc + fw * 0.016 - Y * (hl - 0.1) + Z * 4.7, fwc + fw * 0.016 + Y * (hl - 0.1) + Z * 4.7, CN_BLUE, fw)
	FAC._hz(pw, T, fwc + fw * 0.016 - Y * (hl - 0.1) + Z * 0.75, fwc + fw * 0.016 + Y * (hl - 0.1) + Z * 0.75, fw, int(hl * 4.0))
	var pc := M.part(S, 1)
	M.box(pc, T, Vector3(ax, ym, 5.7), Vector3(1.35, hl, 0.15), cd)
	RO.wire(M.part(S, 2), T, Vector3(ax + sg * 0.6, y0, 0), Vector3(ax + sg * 0.6, y1, 0), 5.9)
	M.box(pc, T, Vector3(ax, 0.0, 5.95), Vector3(0.15, 0.25, 0.12), C.ramp(STEEL))
	M.dpx(pc, T, Vector3(ax, 0.0, 5.95) + fw * 0.17, LAMP_W, fw)
	M.dpx(pc, T, Vector3(ax, 0.0, 6.1), LAMP_R)
	var ob := -fw   # far side: sloped counterfort + HESCO berm
	var pb := M.part(S, 0)
	var bx: float = ax + ob.x * (1.25 + 0.85)
	M.box(pb, T, Vector3(bx, 0.0, 2.0), Vector3(0.85, 0.5, 2.0), cd, Vector3(1.4, 0.0, 0.0) if ob.x > 0.0 else Vector3(0.0, 1.4, 0.0))
	for k in 2:
		RO.hesco(S, T, Vector3(ax + ob.x * 2.65, -1.9 + k * 2.75, 0), Y, 1, 1.0, seed + k)
	if not s:
		M.dpx(pc, T, Vector3(ax, y1 - 0.4, 5.86), AMBER)
	_fin_piece(cv, S, o, seed)


static func build_linkwall(out: Dictionary) -> void:
	var co: Array = K.canvas(2, LW_TOP)
	var o: Vector2 = co[1]
	var fw: int = co[0].w
	var fh: int = co[0].h
	var sheet := P.Canvas.new(fw * 8, fh * 2)
	for col in 8:
		var cv = K.canvas(2, LW_TOP)[0]
		link_piece(cv, o, col / 4, (col % 4) & 1 != 0, (col % 4) & 2 != 0, 7100 + col * 11)
		var base = H.copy(cv)
		C.selout(cv)
		var dm = H.copy(base)
		K.damage(dm, o, 1, 9700 + col * 13)
		C.selout(dm)
		for row in 2:
			var src = cv if row == 0 else dm
			(sheet.img as Image).blit_rect(src.img, Rect2i(0, 0, fw, fh), Vector2i(col * fw, row * fh))
			(sheet.mask as Image).blit_rect(src.mask, Rect2i(0, 0, fw, fh), Vector2i(col * fw, row * fh))
	var entry := {"size": 1, "pivot": [int(o.x), int(o.y)], "fw": fw, "fh": fh, "states": {},
		"sheet": {"cols": "side * 4 + N1 + S2 (side 0: wash on +x, 1: on -x)", "rows": ["intact", "damaged"]},
		"fits": "cn_link_wall 1x1 cell, pivot = cell centre; wall body on the gate bastion line 3.3 m toward the wash"}
	_put(out, entry, "g7_fac_linkwall", "sheet", sheet)
	entry.states["built"] = (entry.states["sheet"] as Dictionary).duplicate()
	out.manifest.buildings["g7_fac_linkwall"] = entry


# ================================================================ ECP serpentine baffles (13.9c-8): cn_ecp_baffle
## g7_fac_baffle SHEET: 1x1 T-wall baffle autotile, column = conn mask (N1 E2 S4 W8: other baffles + the gatehouse),
## row 0 intact / 1 damaged. Two 2 m T-wall slabs (3.0 m) per straight cell, a hazard-banded post with an amber lamp
## where the run turns or ends, hazard foot band and reflector studs on both faces.
const BF_TOP := 48


static func _tslab(pt: Dictionary, T: Dictionary, c: Vector3, al: Vector3, hw: float, i: int, seed: int) -> void:
	var nl := Y if al == X else X
	var conc: Array = C.ramp(CONC)
	M.box(pt, T, c + Z * 0.25, (al * hw + nl * 0.6 + Z * 0.25).abs(), conc)
	M.box(pt, T, c + Z * 1.75, (al * (hw - 0.03) + nl * 0.16 + Z * 1.25).abs(), conc, Vector3(0.0, 0.0, 0.04))
	for s in [-1.0, 1.0]:
		var f: Vector3 = c + nl * (0.17 * s)
		M.dline(pt, T, f + Z * 0.52 - al * (hw - 0.05), f + Z * 0.52 + al * (hw - 0.05), C.ca(conc[1], 0.8), nl * s)
		M.dline(pt, T, f - al * (hw - 0.02) + Z * 0.55, f - al * (hw - 0.02) + Z * 2.95, C.ca(conc[0], 0.7), nl * s)
		FAC._hz(pt, T, f + nl * (0.004 * s) - al * (hw - 0.1) + Z * 0.62, f + nl * (0.004 * s) + al * (hw - 0.1) + Z * 0.62, nl * s, 6)
		M.dpx(pt, T, f + nl * (0.006 * s) + Z * 1.4, Color8(250, 240, 200), nl * s)
		for j in 2:
			var rr := (P.hn(i, j, seed) - 0.5) * 1.4 * hw
			M.dline(pt, T, f + al * rr + Z * 2.9, f + al * rr + Z * (2.0 - P.hn(j, i, seed + 3)), Color(0.25, 0.24, 0.2, 0.3), nl * s)
	M.dpx(pt, T, c + Z * 3.02, conc[0])


static func baffle_piece(cv, o: Vector2, m: int, seed: int) -> void:
	var S: Array = []
	var T := M.pose(o, 0.0)
	var k := 0
	if m == 5 or m == 10:
		var al := Y if m == 5 else X
		for i in 2:
			_tslab(M.part(S, 0), T, al * (-1.0 + i * 2.0), al, 1.0, i, seed)
		_fin_piece(cv, S, o, seed)
		return
	for b in 4:
		if m & (1 << b):
			var d := Vector3(ARM[b].x, ARM[b].y, 0)
			_tslab(M.part(S, 0), T, d * 1.2, X if absf(d.x) > 0.5 else Y, 0.8, k, seed)
			k += 1
	if m == 0:
		_tslab(M.part(S, 0), T, Vector3.ZERO, X, 1.6, 0, seed)
	else:
		var pp := M.part(S, 0)
		M.box(pp, T, Vector3(0, 0, 1.6), Vector3(0.45, 0.45, 1.6), C.ramp(CONC_D), Vector3(0.05, 0.05, 0.05))
		for nl in [X, Y]:
			FAC._hz(pp, T, nl * 0.455 - RO._along(nl) * 0.4 + Z * 0.5, nl * 0.455 + RO._along(nl) * 0.4 + Z * 0.5, nl, 4)
			FAC._hz(pp, T, nl * 0.455 - RO._along(nl) * 0.4 + Z * 2.8, nl * 0.455 + RO._along(nl) * 0.4 + Z * 2.8, nl, 4)
		M.box(pp, T, Vector3(0, 0, 3.3), Vector3(0.14, 0.14, 0.1), C.ramp(STEEL))
		M.dpx(pp, T, Vector3(0, 0, 3.45), AMBER)
	_fin_piece(cv, S, o, seed)


static func build_baffle(out: Dictionary) -> void:
	var co: Array = K.canvas(1, BF_TOP)
	var o: Vector2 = co[1]
	var fw: int = co[0].w
	var fh: int = co[0].h
	var sheet := P.Canvas.new(fw * 16, fh * 2)
	for m in 16:
		var cv = K.canvas(1, BF_TOP)[0]
		baffle_piece(cv, o, m, 7300 + m * 7)
		var base = H.copy(cv)
		C.selout(cv)
		var dm = H.copy(base)
		K.damage(dm, o, 1, 9900 + m * 13)
		C.selout(dm)
		for row in 2:
			var src = cv if row == 0 else dm
			(sheet.img as Image).blit_rect(src.img, Rect2i(0, 0, fw, fh), Vector2i(m * fw, row * fh))
			(sheet.mask as Image).blit_rect(src.mask, Rect2i(0, 0, fw, fh), Vector2i(m * fw, row * fh))
	var entry := {"size": 1, "pivot": [int(o.x), int(o.y)], "fw": fw, "fh": fh, "states": {},
		"sheet": {"cols": "conn mask m = N1 E2 S4 W8 (baffles + gatehouse)", "rows": ["intact", "damaged"]},
		"fits": "cn_ecp_baffle 1x1 T-wall baffle of the serpentine approach, pivot = cell centre"}
	_put(out, entry, "g7_fac_baffle", "sheet", sheet)
	entry.states["built"] = (entry.states["sheet"] as Dictionary).duplicate()
	out.manifest.buildings["g7_fac_baffle"] = entry


# ================================================================ ready-ammo locker (13.9c-11): cn_ammo_locker
## Armoured locker on a concrete plinth: double steel doors with a hazard band and stencil, a stock lamp (green; amber
## on the "empty" state), a blast shield plate on the -x side, two yellow guard bollards. Drawn per entity by def id.
static func locker(cv, o: Vector2, empty: bool, seed: int) -> void:
	var S: Array = []
	var T := M.pose(o, 0.0)
	var pp := M.part(S, 0)
	M.box(pp, T, Vector3(0, 0, 0.1), Vector3(1.0, 0.9, 0.1), C.ramp(CONC_D), Vector3(0.05, 0.05, 0.05))
	var lk := M.part(S, 0)
	var ol: Array = C.ramp(Color8(88, 98, 82))
	M.box(lk, T, Vector3(0.1, -0.15, 1.15), Vector3(0.45, 0.6, 0.95), ol, Vector3(0.02, 0.02, 0.02))
	M.box(lk, T, Vector3(0.1, -0.15, 2.14), Vector3(0.5, 0.66, 0.05), C.ramp(DARK))
	for nl in [X, Y]:
		var al := RO._along(nl)
		var fc: Vector3 = Vector3(0.1, -0.15, 0) + nl * (0.45 if nl == X else 0.6)
		var hw := 0.6 if nl == X else 0.45
		M.dline(lk, T, fc + nl * 0.01 + Z * 0.25, fc + nl * 0.01 + Z * 2.05, C.ca(ol[4], 0.8), nl)
		for i in 4:
			M.dline(lk, T, fc + nl * 0.008 - al * (hw - 0.05) + Z * (0.5 + i * 0.45), fc + nl * 0.008 + al * (hw - 0.05) + Z * (0.5 + i * 0.45), C.ca(ol[0], 0.8), nl)
		FAC._hz(lk, T, fc + nl * 0.012 - al * (hw - 0.05) + Z * 0.3, fc + nl * 0.012 + al * (hw - 0.05) + Z * 0.3, nl, 6)
		M.dline(lk, T, fc + nl * 0.014 + al * 0.08 + Z * 1.2, fc + nl * 0.014 + al * 0.08 + Z * 1.0, Color8(210, 210, 200), nl)
		M.dline(lk, T, fc + nl * 0.014 - al * 0.08 + Z * 1.2, fc + nl * 0.014 - al * 0.08 + Z * 1.0, Color8(210, 210, 200), nl)
	FAC._stencil(lk, T, Vector3(0.562, -0.15, 1.75), Y, X, 4, 0.13)
	M.dpx(lk, T, Vector3(0.57, 0.3, 1.95), AMBER if empty else LAMP_G, X)
	M.box(lk, T, Vector3(-0.5, -0.15, 1.1), Vector3(0.08, 0.75, 1.0), C.ramp(STEEL))   # blast shield
	for b in [Vector3(0.8, 0.65, 0), Vector3(0.8, -0.85, 0)]:
		M.cyl(M.part(S, 0), T, b + Z * 0.5, Z, 0.1, 0.5, 6, C.ramp(YEL), {"cap_t": 3})
		M.dline(M.part(S, 1), T, b + Vector3(0.1, 0, 0.55), b + Vector3(0.1, 0, 0.75), DARK, X)
	M.box(lk, T, Vector3(0.1, -0.15, 2.2), Vector3(0.25, 0.3, 0.012), C.ramp(CONC), Vector3.ZERO, {"team": true})
	_fin_piece(cv, S, o, seed)


static func build_locker(out: Dictionary) -> void:
	var co: Array = K.canvas(1, 36)
	var o: Vector2 = co[1]
	var entry := {"size": 1, "pivot": [int(o.x), int(o.y)], "fw": int(co[0].w), "fh": int(co[0].h), "states": {},
		"fits": "cn_ammo_locker 1x1 armoured ready-ammo locker (SENT7 def), pivot = cell centre"}
	for nm in ["built", "empty"]:
		var cv = K.canvas(1, 36)[0]
		locker(cv, o, nm == "empty", 7500)
		var base = H.copy(cv)
		C.selout(cv)
		_put(out, entry, "cn_ammo_locker", nm, cv)
		if nm == "built":
			var dm = H.copy(base)
			K.damage(dm, o, 1, 9950)
			C.selout(dm)
			_put(out, entry, "cn_ammo_locker", "damaged", dm)
	for nm in ["rot_0", "rot_1", "rot_2", "rot_3", "build_0", "build_1", "build_2"]:
		entry.states[nm] = (entry.states["built"] as Dictionary).duplicate()
	out.manifest.buildings["cn_ammo_locker"] = entry
