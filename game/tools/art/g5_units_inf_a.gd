extends RefCounted
## G5 Human A squads (agent ART-U5), modern olive kit of units.gd (team-painted helmet covers):
##   a_medic_team (2)          idle walk_a walk_b fire heal carry wounded   (carry = stretcher with a casualty)
##   a_hmg_team (3)            idle walk_a walk_b fire deployed deploy wounded (tripod MG; fire = deployed + flash)
##   a_special_forces (4)      idle walk_a walk_b fire stance work wounded  (stance = stacked tactical crouch;
##                                                                         work = planting a charge)
##   a_drone_team (3)          idle walk_a walk_b fire launch tactical wounded
##   a_airfield_engineers (4)  idle walk_a walk_b fire work wounded         (work = filling a runway crater)
const P = preload("res://tools/art/pix.gd")
const L = preload("res://tools/art/g4_units_lib.gd")
const SL = preload("res://tools/art/g5_units_lib.gd")
const SQ = preload("res://tools/art/g5_units_sq.gd")
const FIG = preload("res://tools/art/g5_units_fig.gd")
const U = preload("res://tools/art/units.gd")

const STD := ["idle", "walk_a", "walk_b", "fire"]
const A := {"coat": U.UNIFORM, "trouser": U.TROUSER, "boot": U.BOOT, "skin": U.SKIN, "head": "helm_a", "weapon": "rifle"}
const SF_COAT := Color8(70, 74, 62)
const SF_TROUSER := Color8(58, 60, 52)
const HIVIS := Color8(214, 184, 52)


static func build(out: Dictionary) -> void:
	SL.squad_sheet(out, "a_medic_team", 2, medic, STD + ["heal", "carry", "wounded"])
	SL.squad_sheet(out, "a_hmg_team", 3, hmg, STD + ["deployed", "deploy", "wounded"])
	SL.squad_sheet(out, "a_special_forces", 4, sf, STD + ["stance", "work", "wounded"])
	SL.squad_sheet(out, "a_drone_team", 3, drone_team, STD + ["launch", "tactical", "wounded"])
	SL.squad_sheet(out, "a_airfield_engineers", 4, engineers, STD + ["work", "wounded"])


# ---------------------------------------------------------------- a_medic_team
const MEDIC_FR := ["idle", "walk_a", "walk_b", "fire", "heal", "carry", "wounded"]


static func medic(cv, k: int, f: int, alive: int) -> void:
	var st := SQ.m(A, {"back": "medic", "cross": true, "weapon": "carbine"})
	var styles := [st, st]
	var fn: String = MEDIC_FR[f]
	if SQ.std(cv, k, fn, 2, alive, styles):
		return
	var d := L.sd(k)
	var pr := SL.perp(d)
	var c := SQ.PIV
	if fn == "heal":  # casualty on the ground, medics kneeling either side, one dressing the wound
		var items := [SQ.fig_at(c + Vector2(0, 1), k, "lie", SQ.m(A, {}))]
		var pts := SQ.take([c - pr * 7.0 + Vector2(0, -1), c + pr * 7.0 + Vector2(0, 2)], alive)
		for i in pts.size():
			var face := (k + (2 if i == 0 else 6)) % 8
			items.append(SQ.fig_at(pts[i], face, "work" if i == 0 else "kneel", SQ.m(st, {"work": "aid"})))
		SQ.layered(cv, items)
	else:  # carry: stretcher along the facing between the two bearers
		var front := c + d * 7.0
		var back := c - d * 7.0
		var items := []
		items.append(SQ.prop_at(c.y - 0.5, func(pc) -> void: _stretcher(pc, c, d, alive)))
		items.append(SQ.fig_at(front, k, "carry", st))
		if alive >= 2:
			items.append(SQ.fig_at(back, k, "carry", st))
		SQ.layered(cv, items)


## Litter poles + canvas + casualty, hand height (~6 px above the ground) between the bearers.
static func _stretcher(pc, c: Vector2, d: Vector2, alive: int) -> void:
	var lift := Vector2(0, -6)
	var a := c - d * (6.0 if alive >= 2 else 3.0) + lift
	var b := c + d * 6.0 + lift
	var pr := SL.perp(d) * Vector2(1.0, 0.5)
	if alive < 2:
		a = c - d * 9.0 + Vector2(0, -1)  # dragged: rear end on the ground
	pc.ellipse(c.x + 1, c.y + 1, 6.0, 1.8, Color.BLACK, true)
	pc.flush_shadow()
	for s: float in [-1.0, 1.0]:
		pc.line_v(a + pr * 1.6 * s, b + pr * 1.6 * s, FIG.WOOD)
	for i in 7:
		var t := 0.15 + 0.7 * float(i) / 6.0
		var p: Vector2 = a.lerp(b, t)
		pc.line_v(p - pr * 1.2, p + pr * 1.2, Color8(196, 188, 150) if t < 0.3 else (Color8(118, 124, 88) if t < 0.75 else U.SKIN))
	var mid: Vector2 = a.lerp(b, 0.5)
	pc.rect(int(mid.x) - 1, int(mid.y) - 1, 3, 1, FIG.BANDAGE)
	pc.px(int(mid.x), int(mid.y) - 1, Color8(186, 30, 28))


# ---------------------------------------------------------------- a_hmg_team
const HMG_FR := ["idle", "walk_a", "walk_b", "fire", "deployed", "deploy", "wounded"]


static func hmg(cv, k: int, f: int, alive: int) -> void:
	var gunner := SQ.m(A, {"weapon": "hmg"})
	var asst := SQ.m(A, {"back": "tripod"})
	var ammo := SQ.m(A, {"back": "ammo"})
	var fn: String = HMG_FR[f]
	if fn == "fire" or fn == "deployed" or fn == "deploy":
		_hmg_nest(cv, k, fn, alive, [SQ.m(A, {"weapon": "none"}), asst, ammo])
		return
	SQ.std(cv, k, fn, 3, alive, [gunner, asst, ammo])


## Tripod MG on the ground ahead of a prone gunner; loader kneels at the belt, the third man covers.
static func _hmg_nest(cv, k: int, fn: String, alive: int, styles: Array) -> void:
	var d := L.sd(k)
	var pr := SL.perp(d)
	var c := SQ.PIV
	var gun := c + d * 6.0
	var mounted := fn != "deploy"
	var items := [SQ.prop_at(gun.y, func(pc) -> void: _tripod(pc, gun, d, mounted))]
	var pts := SQ.take([c - d * 2.0, gun + pr * 6.0 - d * 2.0, c - pr * 8.0 - d * 1.0], alive)
	var poses := ["prone" if mounted else "work", "kneel" if mounted else "work", "kneel_aim"]
	for i in pts.size():
		items.append(SQ.fig_at(pts[i], k, poses[i], SQ.m(styles[i], {"work": "dig"})))
	SQ.layered(cv, items)
	if fn == "fire":
		var tip := gun + d * 7.0 + Vector2(0, -4)
		L.flash(cv, tip, 1.2)
		for i in 3:  # tracer dashes downrange
			var p := tip + d * (4.0 + i * 3.0)
			cv.px(int(p.x), int(p.y), Color8(255, 236, 160))


static func _tripod(pc, p: Vector2, d: Vector2, mounted: bool) -> void:
	var head := p + Vector2(0, -3 if mounted else -1)
	var steel := FIG.STEEL
	if mounted:
		var pr := SL.perp(d) * Vector2(1.0, 0.5)
		pc.line_v(head, p + pr * 3.0 + d * 1.0, P.mul(steel, 0.8))
		pc.line_v(head, p - pr * 3.0 + d * 1.0, P.mul(steel, 0.8))
		pc.line_v(head, p - d * 3.0, P.mul(steel, 0.7))
	else:  # folded legs beside the unmounted gun
		pc.line_v(p + Vector2(-3, 1), p + Vector2(3, 0), P.mul(steel, 0.7))
	var dv := Vector2(d.x, d.y * 0.5)
	pc.line_v(head - dv * 3.0, head + dv * 7.0, U.GUN)
	pc.line_v(head - dv * 3.0 + Vector2(0, 1), head + dv * 5.0 + Vector2(0, 1), P.mul(U.GUN, 1.35))
	pc.rect(int(head.x) - 1, int(head.y), 2, 2, Color8(86, 92, 62))  # ammo can on the receiver side
	pc.px(int(head.x) - 1, int(head.y), Color8(150, 128, 70))


# ---------------------------------------------------------------- a_special_forces
const SF_FR := ["idle", "walk_a", "walk_b", "fire", "stance", "work", "wounded"]


static func sf(cv, k: int, f: int, alive: int) -> void:
	var st := SQ.m(A, {"coat": SF_COAT, "trouser": SF_TROUSER, "head": "ops", "weapon": "carbine", "back": "pack"})
	var lead := SQ.m(st, {"back": "radio"})
	var styles := [lead, st, st, SQ.m(st, {"head": "boonie"})]
	var fn: String = SF_FR[f]
	if SQ.std(cv, k, fn, 4, alive, styles, "crouch_aim"):
		return
	var d := L.sd(k)
	var pr := SL.perp(d)
	var c := SQ.PIV
	var items := []
	if fn == "stance":  # stacked up in a file along the facing, weapons up
		var pts := SQ.take([c + d * 7.5, c + d * 2.5 + pr * 1.5, c - d * 2.5, c - d * 7.5 + pr * 1.5], alive)
		for i in pts.size():
			items.append(SQ.fig_at(pts[i], k, "crouch_aim", styles[i]))
	else:  # work: the lead plants a charge, the rest kneel facing outward to cover
		var pts := SQ.take([c + d * 3.0, c - pr * 8.0, c + pr * 8.0, c - d * 6.0], alive)
		var faces := [k, (k + 6) % 8, (k + 2) % 8, (k + 4) % 8]
		for i in pts.size():
			items.append(SQ.fig_at(pts[i], faces[i], "work" if i == 0 else "kneel_aim", SQ.m(styles[i], {"work": "charge"})))
	SQ.layered(cv, items)


# ---------------------------------------------------------------- a_drone_team
const DT_FR := ["idle", "walk_a", "walk_b", "fire", "launch", "tactical", "wounded"]


static func drone_team(cv, k: int, f: int, alive: int) -> void:
	team_frames(cv, k, f, alive, A, "goggles_a", "quad_a", "lift")


## Shared by both factions: operator (goggles, controller, antenna pack), launcher, rifleman.
static func team_frames(cv, k: int, f: int, alive: int, base: Dictionary, goggles: String, quad: String, launch_pose: String) -> void:
	var op := SQ.m(base, {"head": goggles, "weapon": "tablet", "back": "antenna"})
	var lau := SQ.m(base, {"back": quad, "weapon": "carbine" if base.head == "helm_a" else "smg"})
	var rif := SQ.m(base, {"back": "radio"})
	var fn: String = DT_FR[f]
	if SQ.std(cv, k, fn, 3, alive, [op, lau, rif]):
		return
	var d := L.sd(k)
	var pr := SL.perp(d)
	var c := SQ.PIV
	var items := []
	if fn == "launch":  # the launcher sends the drone up, the operator flies it, the rifleman covers
		var pts := SQ.take([c - pr * 6.0, c + pr * 5.0 - d * 1.0, c + d * 5.0 + Vector2(0, 3)], alive)
		var poses := ["stand", launch_pose, "kneel_aim"]
		var held := SQ.m(lau, {"held": quad, "weapon": "none"})
		var sts := [op, held, rif]
		for i in pts.size():
			items.append(SQ.fig_at(pts[i], k, poses[i], sts[i]))
		SQ.layered(cv, items)
		if alive >= 2:  # rotor wash puff under the climbing drone
			var up: Vector2 = pts[1] + Vector2(0, -13)
			L.puff(cv, up + Vector2(0, 3), 2.2, 0.25, Color(0.85, 0.85, 0.82))
	else:  # tactical: drones spent, the team fights as a fire team (rifle, rifle, AT tube)
		var pts := SQ.take([c - pr * 7.0, c + d * 4.0, c + pr * 7.0], alive)
		var sts := [SQ.m(op, {"weapon": "carbine", "back": "pack"}), lau, SQ.m(rif, {"weapon": "rpg"})]
		for i in pts.size():
			items.append(SQ.fig_at(pts[i], k, "crouch_aim", sts[i]))
		SQ.layered(cv, items)


# ---------------------------------------------------------------- a_airfield_engineers
const EN_FR := ["idle", "walk_a", "walk_b", "fire", "work", "wounded"]


static func engineers(cv, k: int, f: int, alive: int) -> void:
	var st := SQ.m(A, {"vest": HIVIS, "back": "tools", "weapon": "carbine"})
	eng_frames(cv, k, f, alive, st, Color8(96, 96, 92))


## Shared: four engineers filling and tamping a crater (gravel heap + plate in the middle).
static func eng_frames(cv, k: int, f: int, alive: int, st: Dictionary, gravel: Color) -> void:
	var styles := [st, SQ.m(st, {"back": ""}), st, SQ.m(st, {"back": "pack"})]
	var fn: String = EN_FR[f]
	if SQ.std(cv, k, fn, 4, alive, styles):
		return
	var d := L.sd(k)
	var pr := SL.perp(d)
	var c := SQ.PIV
	var items := [SQ.prop_at(c.y, func(pc) -> void: _crater(pc, c, gravel, k), false)]
	var pts := SQ.take([c - d * 8.0, c + pr * 10.0, c - pr * 10.0, c + d * 8.0 + Vector2(0, 1)], alive)
	var faces := [k, (k + 6) % 8, (k + 2) % 8, (k + 4) % 8]
	var poses := ["work", "stand", "work", "stand"]
	var tools := ["shovel", "shovel", "shovel", "pick"]
	for i in pts.size():
		items.append(SQ.fig_at(pts[i], faces[i], poses[i], SQ.m(styles[i], {"weapon": tools[i], "work": "dig"})))
	SQ.layered(cv, items)


static func _crater(pc, c: Vector2, gravel: Color, k: int) -> void:
	pc.ellipse(c.x, c.y + 0.5, 8.0, 3.6, P.mul(gravel, 0.5))  # crater rim shadow
	pc.ellipse(c.x - 1, c.y - 0.5, 6.0, 2.6, P.mul(gravel, 1.25))  # fresh gravel fill
	pc.ellipse(c.x - 1, c.y - 1.0, 3.5, 1.4, P.mul(gravel, 1.5))
	for i in 12:
		var x := int(c.x) - 6 + P.hi(i, k, 9101, 11)
		var y := int(c.y) - 2 + P.hi(i, k, 9102, 4)
		pc.px(x, y, P.mul(gravel, 0.8 + 0.35 * (i % 3)))
	pc.rect(int(c.x) + 2, int(c.y) - 1, 3, 2, Color8(70, 72, 70))  # tamping plate
