extends SceneTree
## G7 unmanned facility wall turrets (owner: WTUR7; G7_REFERENCE 13.9c-9; defs content/g7/defs_g7_wallturret.json).
## Modelled in real metres and rasterised by ARTCN7's faceted renderer (tools/art/g7_cn_mesh.gd) at the ONE approved
## scale (fact art.scale: 4 m per 64x32 tile, 9.8 px per metre of height), detail level DL7-3, like g7_turrets2.
## The turret hangs on a facility blast wall (tools/art/g7_fac7f.gd: a 0.34 m thick, 3.6 m slab run on the 2x2
## segment's centre line, 0.64 m capping beam to 3.78 m). The sim puts the turret's footprint on the wall's face row
## and its draw point (e.pos) 0.35 tile out from that cell centre (WallTurret7: so it sorts in front of the wall on
## the camera-facing faces and behind it on the far faces), so in the sprite the wall plane lies WALL_X metres behind
## the pivot along the mount normal. Parts: a steel back plate bolted to the slab face under the capping beam, two
## cantilever brackets with struts, a slew ring held out above the parapet line, and the remote weapon station head
## (A: 12.7 mm RWS with an EO/IR sight and ammo bin; B: 14.5 mm in a heavier slab-sided cradle with smoke
## dischargers). The head clears the wall top, so on the far faces it still shows over the parapet.
## States per def (g6 "rot" schema, facing_i = mount m + 4 * aim a; WallTurret7 sets it):
##   rot_<m> (= a5, head straight out) + rot_<m>_fire, rot_<m>_a<1..9> + _fire (head aim across the half-plane in
##   22.5 deg steps from -90 deg, recoil + muzzle flash; WallTurret7 sets facing_i = m + 4 * k), rot_<m>_damaged, build_<0..2>; vehicle_wrecks[<def>] = the destroyed
##   mount (torn plate, dropped head, scorch) on 8 facing rows (row 2m = mount m) for the wreck the sim leaves.
## Deterministic: re-running reproduces byte-identical files.
##   godot --headless --path . -s tools/art/g7_wallturret.gd [-- --out=<abs dir>]   (default assets/art/g7_wallturret/)
## Prints "G7_ART <id> bytes=<n> budget=<n> states=<n> ok|OVER" and "G7_ART group=g7_wallturret files=<n> over=<n>".

const GEN = preload("res://tools/gen_art.gd")
const P = preload("res://tools/art/pix.gd")
const C = preload("res://tools/art/g7_cn_lib.gd")
const M = preload("res://tools/art/g7_cn_mesh.gd")
const GR = preload("res://tools/art/g7_cn_gear.gd")
const V = preload("res://tools/art/g7_cn_vehicles.gd")
const H = preload("res://tools/art/g6_lib.gd")
const K = preload("res://tools/art/g5_bld_lib.gd")

const GROUP := "g7_wallturret"
const DEFS := ["a_wt7_wall_turret", "b_wt7_wall_turret"]
const DRAW_OUT := 0.35          # tiles: sim draw point ahead of the cell centre (WallTurret7.DRAW_OUT)
const WALL_X := -(2.0 + DRAW_OUT * 4.0)   # metres: the wall centre plane behind the pivot
const SLAB := 0.17              # slab half thickness (g7_fac7f _slab)
const RING := Vector3(WALL_X + 1.05, 0.0, 3.72)   # slew ring centre: 1.05 m off the wall plane, above the cap line
const CW := 96
const CH := 88
const OX := 48
const OY := 60
const STEEL := Color8(84, 90, 96)
const STEEL_D := Color8(58, 62, 66)
const DARK := Color8(46, 50, 52)
const ARM_A := Color8(98, 106, 84)
const ARM_B := Color8(92, 100, 110)
const CAN := Color8(92, 98, 64)
const GLASS := Color8(70, 120, 140)
const HAZ := Color8(226, 184, 40)
const SCORCH := Color(0.08, 0.07, 0.06, 0.55)


static func _cv():
	return P.Canvas.new(CW, CH)


## Wall-side hardware (fixed to the wall, does not slew): back plate, bolts, brackets, struts, ring, cable conduit.
## broken: the plate hangs torn, one bracket gone.
static func mount(S: Array, T: Dictionary, faction: String, broken := false) -> void:
	var st: Array = C.ramp(STEEL)
	var sd: Array = C.ramp(STEEL_D)
	var dk: Array = C.ramp(DARK)
	var pp := M.part(S, 0)
	var px := WALL_X + SLAB + 0.05
	if broken:
		M.box(pp, M.sub(T, Vector3(px, 0.1, 2.9), 0.0, 0.0, 0.22), Vector3.ZERO, Vector3(0.05, 0.55, 0.42), sd, Vector3(0.0, 0.03, 0.03))
		M.dpoly(pp, T, [Vector3(px + 0.06, -0.8, 2.2), Vector3(px + 0.06, 0.8, 2.2), Vector3(px + 0.06, 0.9, 3.55), Vector3(px + 0.06, -0.7, 3.55)], SCORCH, Vector3(1, 0, 0))
		M.cyl(pp, T, Vector3(px + 0.3, 0.42, 2.7), Vector3(1, 0, -0.6), 0.04, 0.32, 4, sd, {"edge": false})   # one bent strut
		return
	M.box(pp, T, Vector3(px, 0.0, 3.05), Vector3(0.05, 0.62, 0.42), sd, Vector3(0.0, 0.03, 0.03))   # back plate
	for s in [-1.0, 1.0]:
		for z in [2.72, 3.38]:
			M.dpx(pp, T, Vector3(px + 0.06, s * 0.5, z), st[4], Vector3(1, 0, 0))   # anchor bolts
	M.dline(pp, T, Vector3(px + 0.06, -0.55, 2.66), Vector3(px + 0.06, 0.55, 2.66), C.ca(sd[0], 0.9), Vector3(1, 0, 0))
	for s in [-0.38, 0.38]:   # cantilever brackets + struts up to the ring
		M.box(pp, T, Vector3((px + RING.x) * 0.5, s, RING.z - 0.16), Vector3((RING.x - px) * 0.5 + 0.02, 0.045, 0.07), st)
		var a := Vector3(px + 0.04, s, 2.72)
		var b := Vector3(RING.x - 0.15, s, RING.z - 0.2)
		M.cyl(pp, T, (a + b) * 0.5, b - a, 0.035, (b - a).length() * 0.5, 4, sd, {"edge": false})
	M.cyl(pp, T, Vector3(RING.x, 0, RING.z - 0.04), Vector3(0, 0, 1), 0.42, 0.07, 10, dk, {"cap_t": 1})   # slew ring
	# power / data conduit: a short run along the slab face under the plate into the wall (WTUR7-2: the old drop to the
	# wall foot read as a pole standing in front of the wall in game)
	M.dline(pp, T, Vector3(px + 0.06, 0.32, 2.42), Vector3(px + 0.06, 0.95, 2.42), C.ca(sd[1], 0.85), Vector3(1, 0, 0))
	M.dline(pp, T, Vector3(px + 0.06, 0.95, 2.42), Vector3(px + 0.06, 0.95, 2.2), C.ca(sd[1], 0.85), Vector3(1, 0, 0))
	M.box(pp, T, Vector3(px + 0.1, 0.32, 2.45), Vector3(0.06, 0.12, 0.14), sd)   # junction box
	M.dpx(pp, T, Vector3(px + 0.17, 0.32, 2.5), GR.LED_G if faction == "a" else Color8(120, 200, 255), Vector3(1, 0, 0))
	for i in 3:   # hazard stripes on the plate edge
		M.dline(pp, T, Vector3(px + 0.06, -0.6 + i * 0.12, 2.64), Vector3(px + 0.06, -0.52 + i * 0.12, 2.7), HAZ if i % 2 == 0 else GR.HAZ_D, Vector3(1, 0, 0))


## The remote weapon station head on the ring, slewed to yaw (local), recoil rc, muzzle flash when fire.
static func head(S: Array, T: Dictionary, faction: String, yaw: float, fire: bool, dmg := false, bare := false) -> void:
	var Tg := M.sub(T, RING, yaw)
	var pt := M.part(S, 1)
	var dk: Array = C.ramp(DARK)
	var arm: Array = C.ramp((ARM_A if faction == "a" else ARM_B).darkened(0.4 if dmg else 0.0))
	if bare:   # build stage: turntable + cradle only, no weapon yet
		M.cyl(pt, Tg, Vector3(0, 0, 0.08), Vector3(0, 0, 1), 0.34, 0.06, 10, dk, {"cap_t": 1})
		M.box(pt, Tg, Vector3(-0.08, 0, 0.28), Vector3(0.36, 0.25, 0.16), arm, Vector3(0.18, 0.06, 0.08))
		return
	var rc := 0.16 if fire else 0.0
	M.cyl(pt, Tg, Vector3(0, 0, 0.08), Vector3(0, 0, 1), 0.34, 0.06, 10, dk, {"cap_t": 1})   # turntable
	if faction == "a":
		M.box(pt, Tg, Vector3(-0.08, 0, 0.32), Vector3(0.4, 0.27, 0.2), arm, Vector3(0.18, 0.06, 0.08))   # cradle
		team_patch(pt, Tg, Vector3(-0.22, 0, 0.53), Vector3(0.16, 0.16, 0.012), arm)
		M.box(pt, Tg, Vector3(0.02, -0.33, 0.52), Vector3(0.13, 0.09, 0.12), dk)   # EO/IR sight
		M.dpx(pt, Tg, Vector3(0.16, -0.36, 0.55), GLASS, Vector3(1, 0, 0))
		M.dpx(pt, Tg, Vector3(0.16, -0.3, 0.55), C.ramp(GLASS)[4], Vector3(1, 0, 0))
		M.box(pt, Tg, Vector3(-0.12, 0.36, 0.3), Vector3(0.2, 0.08, 0.13), C.ramp(CAN))   # ammo bin
		M.dline(pt, Tg, Vector3(0.0, 0.3, 0.38), Vector3(0.18, 0.1, 0.36), Color8(176, 148, 70))
		M.box(pt, Tg, Vector3(0.22 - rc, 0, 0.36), Vector3(0.26, 0.07, 0.07), dk)   # receiver
		var mz := barrel(pt, Tg, 0.45, 1.5, 0.36, 0.042, rc, false)
		M.cyl(pt, Tg, Vector3(1.42 - rc, 0, 0.36), Vector3(1, 0, 0), 0.06, 0.07, 6, dk, {"edge": false})   # flash hider
		if fire:
			flash(S, Tg, mz)
	else:
		M.box(pt, Tg, Vector3(-0.1, 0, 0.3), Vector3(0.44, 0.3, 0.18), arm, Vector3(0.1, 0.02, 0.04))   # slab cradle
		for s in [-1.0, 1.0]:
			M.box(pt, Tg, Vector3(0.0, s * 0.33, 0.42), Vector3(0.36, 0.03, 0.2), arm)   # side armour
			for i in 2:   # smoke dischargers
				M.cyl(pt, Tg, Vector3(-0.32 + i * 0.12, s * 0.38, 0.6), Vector3(0.5, s * 0.4, 0.7), 0.04, 0.07, 5, dk, {"edge": false})
		team_patch(pt, Tg, Vector3(-0.3, 0, 0.49), Vector3(0.14, 0.18, 0.012), arm)
		M.box(pt, Tg, Vector3(-0.05, 0.0, 0.66), Vector3(0.1, 0.12, 0.08), dk)   # roof sight
		M.dpx(pt, Tg, Vector3(0.06, 0.0, 0.67), GLASS, Vector3(1, 0, 0))
		M.cyl(pt, Tg, Vector3(0.7 - rc, 0, 0.38), Vector3(1, 0, 0), 0.075, 0.42, 6, C.ramp(STEEL_D), {"edge": false})   # perforated shroud
		for i in 4:
			M.dpx(pt, Tg, Vector3(0.42 + i * 0.16 - rc, 0, 0.455), Color8(20, 22, 22), Vector3(0, 0, 1))
		var mz := barrel(pt, Tg, 1.1, 1.75, 0.38, 0.045, rc, true)
		if fire:
			flash(S, Tg, mz)


## Barrel along local +x of pose Tg from f0 to f1 at height z, pulled back by rc; returns the muzzle point.
static func barrel(pt: Dictionary, Tg: Dictionary, f0: float, f1: float, z: float, rad: float, rc: float, brake: bool) -> Vector3:
	var dk: Array = C.ramp(DARK)
	M.cyl(pt, Tg, Vector3((f0 + f1) * 0.5 - rc, 0, z), Vector3(1, 0, 0), rad, (f1 - f0) * 0.5, 6, dk, {"edge": false})
	if brake:
		M.box(pt, Tg, Vector3(f1 - rc - 0.07, 0, z), Vector3(0.09, rad * 1.7, rad * 1.5), dk)
	return Vector3(f1 - rc + 0.05, 0, z)


static func flash(S: Array, Tp: Dictionary, m: Vector3) -> void:
	var pt := M.part(S, 3)
	V._flash(pt, Tp, m)
	var w := M.wm(Tp, m + Vector3(0.18, 0, 0))
	var o: Vector2 = Tp.o
	M.sprite(S, w, func(cv):
		var c := M.scr_w(o, w)
		C.blob(cv, c, 1.5, [GR.FLASH_O, GR.FLASH_O, GR.FLASH, GR.FLASH, Color(1, 1, 0.9)]), 4.0)


## Team ID plate (mask pixels), as g7_turrets2.team_patch.
static func team_patch(pt: Dictionary, T: Dictionary, c: Vector3, h: Vector3, rp: Array) -> void:
	M.box(pt, T, c, h, rp)
	M.dpoly(pt, T, [c + Vector3(-h.x, -h.y, h.z + 0.004), c + Vector3(h.x, -h.y, h.z + 0.004), c + Vector3(h.x, h.y, h.z + 0.004),
		c + Vector3(-h.x, h.y, h.z + 0.004)], Color8(152, 152, 152), Vector3(0, 0, 1), true)


## The head knocked off its ring: lying at the wall foot, barrel bent, smoke.
static func fallen(S: Array, T: Dictionary, faction: String) -> void:
	var Tf := M.sub(T, Vector3(WALL_X + 1.4, 0.35, 0.25), 0.7, 0.0, 1.2)
	var pt := M.part(S, 0)
	var arm: Array = C.ramp((ARM_A if faction == "a" else ARM_B).darkened(0.35))
	var dk: Array = C.ramp(DARK)
	M.box(pt, Tf, Vector3(0, 0, 0), Vector3(0.38, 0.26, 0.18), arm, Vector3(0.1, 0.05, 0.05))
	M.cyl(pt, Tf, Vector3(0.7, 0, 0.05), Vector3(1, 0, 0.15), 0.045, 0.45, 6, dk, {"edge": false})
	for i in 5:   # debris
		M.dpx(pt, T, Vector3(WALL_X + 0.9 + 0.3 * i, -0.6 + 0.27 * i, 0.02), dk[1 + i % 3], Vector3(0, 0, 1))
	M.dpoly(pt, T, [Vector3(WALL_X + 0.5, -0.9, 0.01), Vector3(WALL_X + 2.4, -0.7, 0.01), Vector3(WALL_X + 2.2, 1.0, 0.01), Vector3(WALL_X + 0.6, 0.9, 0.01)], SCORCH, Vector3(0, 0, 1))


## One frame: mount m (pose yaw m * 90 deg, local +x = out of the face), head aim a (0..8; 4 = straight out).
## stage: -1 complete, 0 plate only, 1 + brackets and ring, 2 + bare cradle (build_<n>). dmg: scorched, smoking.
static func frame(faction: String, m: int, a: int, fire: bool, stage := -1, dmg := false):
	var cv = _cv()
	var o := Vector2(OX, OY)
	var S: Array = []
	var T := M.pose(o, float(m) * PI / 2.0)
	if stage == 0:
		var pp := M.part(S, 0)
		M.box(pp, T, Vector3(WALL_X + SLAB + 0.05, 0.0, 3.05), Vector3(0.05, 0.62, 0.42), C.ramp(STEEL_D), Vector3(0.0, 0.03, 0.03))
		M.dline(pp, T, Vector3(WALL_X + SLAB + 0.11, -0.62, 2.6), Vector3(WALL_X + SLAB + 0.11, 0.62, 2.6), HAZ, Vector3(1, 0, 0))
	else:
		mount(S, T, faction)
	if stage < 0 or stage == 2:
		head(S, T, faction, (float(a) - 4.0) * PI / 8.0, fire, dmg, stage == 2)
	M.shadow(cv, S, o)
	M.render_z(cv, S, o, 9100 + m * 17 + a)
	if dmg:
		for i in 5:   # smoke from the cradle, a lick of flame, sparks on the plate
			var c := M.scr_w(o, M.wm(T, RING + Vector3(-0.1 + 0.06 * i, 0.05 * i, 0.4 + 0.13 * i)))
			C.blob(cv, c, 0.9 + 0.2 * i, C.ramp(Color8(88, 84, 80)))
		var fc := M.scr_w(o, M.wm(T, RING + Vector3(0.0, 0.1, 0.3)))
		C.blob(cv, fc, 1.2, [GR.FLASH_O, GR.FLASH_O, GR.FLASH, GR.FLASH, GR.FLASH])
		var sc := M.scr_w(o, M.wm(T, Vector3(WALL_X + SLAB + 0.1, 0.3, 2.9)))
		cv.px(int(sc.x), int(sc.y), GR.FLASH)
	return cv


static func wreck_frame(faction: String, m: int):
	var cv = _cv()
	var o := Vector2(OX, OY)
	var S: Array = []
	var T := M.pose(o, float(m) * PI / 2.0)
	mount(S, T, faction, true)
	fallen(S, T, faction)
	M.render_z(cv, S, o, 9300 + m)
	var g = cv
	for i in 6:   # smoke wisps over the torn mount
		var c := M.scr_w(o, M.wm(T, Vector3(WALL_X + 0.6 + 0.1 * i, 0.05 * i, 3.1 + 0.25 * i)))
		C.blob(g, c, 1.2 + 0.25 * i, C.ramp(Color8(96, 92, 86)))
	return cv


static func build_def(out: Dictionary, id: String) -> void:
	var faction := id.substr(0, 1)
	var man: Dictionary = out.manifest.get("buildings", {})
	var entry := {"size": 1, "pivot": [OX, OY], "fw": CW, "fh": CH, "states": {}, "g6": {"variants": "rot", "faction": faction}}
	var bytes := 0
	for m in 4:
		for a in 9:
			var cv = frame(faction, m, a, false)
			C.selout(cv)
			bytes += C._bput(out, entry, id, "rot_%d_a%d" % [m, a + 1], cv)
			var cf = frame(faction, m, a, true)
			C.selout(cf)
			bytes += C._bput(out, entry, id, "rot_%d_a%d_fire" % [m, a + 1], cf)
			if a == 4:
				entry.states["rot_%d" % m] = (entry.states["rot_%d_a5" % m] as Dictionary).duplicate()
				entry.states["rot_%d_fire" % m] = (entry.states["rot_%d_a5_fire" % m] as Dictionary).duplicate()
				var dm = frame(faction, m, 5, false, -1, true)
				C.selout(dm)
				bytes += C._bput(out, entry, id, "rot_%d_damaged" % m, dm)
	for m in 4:   # build stages per mount (the mount goes up on its own face: plate, brackets + ring, bare cradle)
		for st in 3:
			var bs = frame(faction, m, 4, false, st)
			C.selout(bs)
			bytes += C._bput(out, entry, id, "rot_%d_build_%d" % [m, st], bs)
	for nm in ["built:rot_1", "damaged:rot_1_damaged", "fire:rot_1_fire", "build_0:rot_1_build_0", "build_1:rot_1_build_1", "build_2:rot_1_build_2"]:
		var pr: PackedStringArray = nm.split(":")
		entry.states[pr[0]] = (entry.states[pr[1]] as Dictionary).duplicate()
	entry["g7"] = {"detail_level": C.VERSION, "class": "turret", "bytes": bytes, "budget": int(C.BUDGET.turret),
		"wall_turret": true, "scale": "4 m/tile, 9.8 px/m (fact art.scale), rev3 DL7-3",
		"mount": "rot_<m> = mount side (0 +x, 1 +y, 2 -x, 3 -y), _a<1..9> = head aim across the half-plane (5 = straight out)",
		"key_frames": ["rot_1_a5", "rot_1_a2_fire", "rot_0_a7", "rot_3_a5", "rot_2_a3"]}
	man[id] = entry
	out.manifest["buildings"] = man
	# the destroyed mount for the wreck the sim leaves (8 facing rows; row 2m = mount m, odd rows = the next even)
	var sheet := P.Canvas.new(CW, CH * 8)
	for m in 4:
		var wc = wreck_frame(faction, m)
		C.selout(wc)
		for r in [2 * m, (2 * m + 7) % 8]:
			(sheet.img as Image).blit_rect(wc.img, Rect2i(0, 0, CW, CH), Vector2i(0, r * CH))
	var wf := "buildings/%s_wreck.png" % id
	out.images[wf] = sheet.img
	var vw: Dictionary = out.manifest.get("vehicle_wrecks", {})
	vw[id] = {"file": wf, "fw": CW, "fh": CH, "pivot": [OX, OY], "rows": "facing index (round(facing / 45 deg) % 8)"}
	out.manifest["vehicle_wrecks"] = vw
	var img: Image = out.images[String(entry.states.built.file)]
	C.icon(out, id, img, CW, CH, 0)


static func generate() -> Dictionary:
	var out := {"images": {}, "manifest": {"version": 1, "tile": [64, 32], "group": GROUP, "g7_detail_level": C.DL.duplicate(true)}}
	for id in DEFS:
		build_def(out, id)
	return out


func _init() -> void:
	var out_dir := "res://assets/art/%s/" % GROUP
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6).path_join(GROUP) + "/"
	var r := generate()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	for sub in ["buildings", "icons"]:
		var bd := DirAccess.open(ProjectSettings.globalize_path(out_dir).path_join(sub))
		if bd != null:
			for fn in bd.get_files():
				if fn.ends_with(".png"):
					bd.remove(fn)
	var files := int(GEN.save(r, out_dir))
	var over := 0
	var man: Dictionary = r.manifest.get("buildings", {})
	var ids: Array = man.keys()
	ids.sort()
	for id in ids:
		var g7: Dictionary = man[id].g7
		var ok := int(g7.bytes) <= int(g7.budget)
		if not ok:
			over += 1
		print("G7_ART %s bytes=%d budget=%d states=%d %s" % [id, int(g7.bytes), int(g7.budget), (man[id].states as Dictionary).size(), "ok" if ok else "OVER"])
	print("G7_ART group=%s files=%d over=%d" % [GROUP, files, over])
	quit()
