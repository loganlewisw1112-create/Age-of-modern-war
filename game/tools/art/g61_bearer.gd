extends RefCounted
## G6.1 (BEARER61): ammo bearer art, its own group assets/art/g61_bearer/ (manifest.json, same schema as the
## G6 groups; ArtCatalog merges it once "g61_bearer" is in its group list). Written by tools/art/g61_bearer_gen.gd.
##   a_ammo_bearer      Human A: one soldier, ammo crate on the back, sidearm-less; "restock" = kneels at an open crate
##   b_supply_carrier   Human B: same, Human B drill kit and steel brim, canvas bag on the back
##   m_munitions_drone  Machine: small hover-crawler with a slung magazine pod; "restock" = pod lowered, feed glows
## Infantry use the shared G5/G6 figure (FIG / SQ) and get the G6.1 rig frames from tools/art/g61_anim.gd
## (ANIMA61), exactly like every other foot sheet. Pure function of code: re-running is byte-identical.
const P = preload("res://tools/art/pix.gd")
const L = preload("res://tools/art/g4_units_lib.gd")
const SL = preload("res://tools/art/g5_units_lib.gd")
const SQ = preload("res://tools/art/g5_units_sq.gd")
const FIG = preload("res://tools/art/g5_units_fig.gd")
const U = preload("res://tools/art/units.gd")
const BI = preload("res://tools/art/faction_b_inf.gd")
const M = preload("res://tools/art/faction_m_lib.gd")
const G = preload("res://tools/art/g3b_lib.gd")
const ANIM = preload("res://tools/art/g61_anim.gd")

const MOUTL := Color(0.09, 0.09, 0.07, 1)
const CRATE := Color8(86, 92, 62)
const CRATE_D := Color8(62, 66, 44)
const BRASS := Color8(212, 172, 84)
const A := {"coat": U.UNIFORM, "trouser": U.TROUSER, "boot": U.BOOT, "skin": U.SKIN, "head": "helm_a",
	"weapon": "none", "back": "ammo", "vest": Color8(104, 108, 70)}
const BS := {"coat": BI.DRILL, "trouser": BI.TROUSER, "boot": BI.BOOT, "skin": BI.SKIN, "head": "helm_b",
	"weapon": "none", "back": "pack"}
const INF_FR := ["idle", "walk_a", "walk_b", "fire", "restock", "wounded"]
const DRONE_FR := ["idle", "move", "fire", "restock"]
## Unit id -> [icon facing row, lod class].
const UNITS := {"a_ammo_bearer": [1, "infantry"], "b_supply_carrier": [1, "infantry"], "m_munitions_drone": [1, "vehicle_light"]}


static func new_out() -> Dictionary:
	return {"images": {}, "manifest": {"version": 1, "tile": [64, 32], "group": "g61_bearer"}}


## Builds every sheet + icons + lod classes into a fresh out dict.
static func generate() -> Dictionary:
	var out := new_out()
	SL.squad_sheet(out, "a_ammo_bearer", 1, func(cv, k: int, f: int, alive: int) -> void: _human(cv, k, f, alive, A), INF_FR)
	SL.squad_sheet(out, "b_supply_carrier", 1, func(cv, k: int, f: int, alive: int) -> void: _human(cv, k, f, alive, BS), INF_FR)
	SL.veh_sheet(out, "m_munitions_drone", {"fw": 44, "fh": 44, "pivot": [22, 32]}, drone, DRONE_FR)
	ANIM.build(out)
	preload("res://tools/art/g61_anim_veh.gd").build(out)  # G6.1 (ANIMB61/ANIMC61): vehicle animation frames
	var icons := {}
	var lod := {}
	var spec := {}
	for id in UNITS:
		icons[id] = G.icon_unit(out, id, id, int(UNITS[id][0]), id.substr(0, 1) if id.substr(0, 2) != "a_" else "")
		lod[id] = UNITS[id][1]
		spec[id] = {"restock": "restock"}
	out.manifest["icons"] = icons
	out.manifest["lod_class"] = lod
	out.manifest["specials"] = spec
	out.manifest["g61_bearer"] = {"defs": UNITS.keys()}
	return out


# ================================================================ infantry
static func _human(cv, k: int, f: int, alive: int, st: Dictionary) -> void:
	var fn: String = INF_FR[f]
	if SQ.std(cv, k, fn, 1, alive, [st]):
		return
	# restock: kneels beside an open crate, a magazine held out
	var d := L.sd(k)
	var pr := SL.perp(d)
	var c := SQ.PIV
	var box := c + d * 4.0 + pr * 3.0 + Vector2(0, 1)
	var items := [SQ.prop_at(box.y, func(pc) -> void: _crate(pc, box))]
	items.append(SQ.fig_at(c - d * 1.0, k, "work", SQ.m(st, {"work": "aid"})))
	var mag := c + d * 6.0 + Vector2(0, -6)
	items.append(SQ.prop_at(mag.y + 6.0, func(pc) -> void:
		pc.rect(int(mag.x), int(mag.y), 2, 3, Color8(48, 48, 44))
		pc.px(int(mag.x), int(mag.y) - 1, BRASS), false))
	SQ.layered(cv, items)


static func _crate(pc, p: Vector2) -> void:
	pc.rect(int(p.x) - 4, int(p.y) - 4, 8, 4, CRATE)
	pc.rect(int(p.x) - 4, int(p.y) - 4, 8, 1, CRATE_D)
	pc.rect(int(p.x) - 5, int(p.y) - 6, 3, 2, P.mul(CRATE, 1.15))   # open lid
	for i in 3:
		pc.px(int(p.x) - 2 + i * 2, int(p.y) - 5, BRASS)   # rounds showing


# ================================================================ machine
## Small hover-crawler: graphite body on four stub legs, a magazine pod slung under the rear.
static func drone(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	if wreck:
		cv.ellipse(o.x + 1, o.y + 1, 7.0, 2.8, Color8(36, 32, 30))
		P.box(cv, o, Vector3(0, 0, 1), 0.12, 0.08, 2.0, rot, M.DEAD, 0.06, 7101)
		cv.outline(MOUTL)
		return
	var bob := 1.0 if f == 1 else 0.0
	var z := 3.0 + bob
	cv.ellipse(o.x + 1, o.y + 1, 8.0, 3.2, Color.BLACK, true)
	cv.flush_shadow()
	for s in [-1.0, 1.0]:
		for fw in [-0.1, 0.1]:
			var a := M.sp(o, rot, fw, 0.1 * s, z)
			var b := M.sp(o, rot, fw * 1.4, 0.15 * s, 0)
			cv.line_v(a, b, M.JOINT)
	var pod_z := 0.5 if f == 3 else z - 1.5
	var pod: Dictionary = P.box(cv, o, M.w(rot, -0.2, 0, pod_z), 0.07, 0.08, 3.0, rot, CRATE, 0.05, 7103)
	var b: Dictionary = P.box(cv, o, Vector3(0, 0, z), 0.14, 0.09, 3.0, rot, M.GRAPH, 0.06, 7105)
	for sd in b.sides:
		if absf((sd.n as Vector2).dot(Vector2(-sin(rot), cos(rot)))) > 0.7:
			M.team_panel(cv, sd.quad, 0.1, 0.25, 0.7, 0.8)
		M.seam(cv, sd.quad, 0.15)
	M.eye(cv, M.sp(o, rot, 0.12, 0, z + 2.0), f == 2)
	cv.outline(MOUTL)
	if f == 3:  # feed lit: cyan strip on the lowered pod
		var q := M.sp(o, rot, -0.2, 0, pod_z + 1.0)
		cv.rect(int(q.x) - 1, int(q.y), 3, 1, M.CYAN)
	elif pod.has("sides"):
		var q2 := M.sp(o, rot, -0.2, 0, pod_z + 3.0)
		cv.px(int(q2.x), int(q2.y), BRASS)
