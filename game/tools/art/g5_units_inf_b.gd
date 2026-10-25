extends RefCounted
## G5 Human B squads (agent ART-U5), industrial drill / rust kit of faction_b_inf (steel brims, gas hoods,
## leather webbing, welded plates):
##   b_grenadiers (4)          idle walk_a walk_b fire wounded              (fire = two lob, two fire launchers)
##   b_shock_troops (4)        idle walk_a walk_b fire stance wounded       (stance = crouched breach wedge)
##   b_at_rocket_team (3)      idle walk_a walk_b fire deployed wounded     (deployed = gunner kneels, aims)
##   b_drone_team (3)          idle walk_a walk_b fire launch tactical wounded (FPV hand-thrown)
##   b_airfield_engineers (4)  idle walk_a walk_b fire work wounded
const P = preload("res://tools/art/pix.gd")
const L = preload("res://tools/art/g4_units_lib.gd")
const SL = preload("res://tools/art/g5_units_lib.gd")
const SQ = preload("res://tools/art/g5_units_sq.gd")
const FIG = preload("res://tools/art/g5_units_fig.gd")
const IA = preload("res://tools/art/g5_units_inf_a.gd")
const BI = preload("res://tools/art/faction_b_inf.gd")

const STD := ["idle", "walk_a", "walk_b", "fire"]
const BS := {"coat": BI.DRILL, "trouser": BI.TROUSER, "boot": BI.BOOT, "skin": BI.SKIN, "head": "helm_b",
	"weapon": "rifle", "belt": BI.LEATHER}
const HIVIS_B := Color8(204, 118, 42)


static func build(out: Dictionary) -> void:
	SL.squad_sheet(out, "b_grenadiers", 4, grenadiers, STD + ["wounded"])
	SL.squad_sheet(out, "b_shock_troops", 4, shock, STD + ["stance", "wounded"])
	SL.squad_sheet(out, "b_at_rocket_team", 3, at_team, STD + ["deployed", "wounded"])
	SL.squad_sheet(out, "b_drone_team", 3, drone_team, STD + ["launch", "tactical", "wounded"])
	SL.squad_sheet(out, "b_airfield_engineers", 4, engineers, STD + ["work", "wounded"])


# ---------------------------------------------------------------- b_grenadiers
static func grenadiers(cv, k: int, f: int, alive: int) -> void:
	var gr := SQ.m(BS, {"back": "ammo", "belt": BI.RUST})
	var gl := SQ.m(BS, {"weapon": "gl", "back": "pack"})
	var styles := [gr, gl, gr, gl]
	if f != 3:
		SQ.std(cv, k, ["idle", "walk_a", "walk_b", "fire", "wounded"][f], 4, alive, styles)
		return
	var d := L.sd(k)
	SL.formation(cv, k, 0, 4, alive, func(c, kk: int, _f: int, i: int) -> void:
		if i % 2 == 0:
			FIG.draw(c, kk, "throw", SQ.m(styles[i], {"held": "grenade", "weapon": "none"}))
		else:
			FIG.draw(c, kk, "aim", SQ.m(styles[i], {"fire": true})))
	if alive >= 1:  # a grenade in flight on its arc ahead of the squad
		var s: Vector2 = SQ.PIV + Vector2(SL.SLOTS[4][0]) + Vector2(0, -15)
		for t in 4:
			var p := s + Vector2(d.x * (3.0 + t * 2.5), d.y * (1.5 + t * 1.2) - 2.0 + t * t * 0.4)
			if t == 3:
				cv.rect(int(p.x), int(p.y), 2, 2, Color8(52, 58, 40))
			else:
				cv.px(int(p.x), int(p.y), Color(0.95, 0.95, 0.9, 0.6))


# ---------------------------------------------------------------- b_shock_troops
static func shock(cv, k: int, f: int, alive: int) -> void:
	var st := SQ.m(BS, {"coat": BI.COAT, "head": "mask_b", "weapon": "smg", "plate": true})
	var styles := [st, SQ.m(st, {"back": "tools"}), st, SQ.m(st, {"back": "pack"})]
	var fn: String = ["idle", "walk_a", "walk_b", "fire", "stance", "wounded"][f]
	if SQ.std(cv, k, fn, 4, alive, styles):
		return
	var d := L.sd(k)
	var pr := SL.perp(d)
	var c := SQ.PIV
	var items := []
	var pts := SQ.take([c + d * 6.0, c + d * 1.0 - pr * 6.0, c + d * 1.0 + pr * 6.0, c - d * 5.0], alive)
	for i in pts.size():
		items.append(SQ.fig_at(pts[i], k, "crouch_aim" if i != 1 else "crouch", styles[i]))
	SQ.layered(cv, items)


# ---------------------------------------------------------------- b_at_rocket_team
static func at_team(cv, k: int, f: int, alive: int) -> void:
	var gun := SQ.m(BS, {"weapon": "rpg", "head": "cap_b"})
	var loader := SQ.m(BS, {"back": "rockets", "weapon": "none"})
	var rif := SQ.m(BS, {"back": "pack"})
	var fn: String = ["idle", "walk_a", "walk_b", "fire", "deployed", "wounded"][f]
	if fn != "fire" and fn != "deployed":
		SQ.std(cv, k, fn, 3, alive, [gun, loader, rif])
		return
	var d := L.sd(k)
	var pr := SL.perp(d)
	var c := SQ.PIV
	var items := []
	var pts := SQ.take([c + d * 2.0, c - pr * 7.0 - d * 2.0, c + pr * 7.0 - d * 1.0], alive)
	var sts := [SQ.m(gun, {"fire": fn == "fire"}), loader, SQ.m(rif, {"fire": fn == "fire"})]
	var poses := ["kneel_aim", "kneel", "kneel_aim"]
	for i in pts.size():
		items.append(SQ.fig_at(pts[i], k, poses[i], sts[i]))
	SQ.layered(cv, items)


# ---------------------------------------------------------------- b_drone_team / b_airfield_engineers
static func drone_team(cv, k: int, f: int, alive: int) -> void:
	IA.team_frames(cv, k, f, alive, SQ.m(BS, {"head": "helm_b"}), "goggles_b", "quad_b", "throw")


static func engineers(cv, k: int, f: int, alive: int) -> void:
	var st := SQ.m(BS, {"coat": BI.OVERALL, "head": "cap_b", "vest": HIVIS_B, "back": "tools", "weapon": "rifle"})
	IA.eng_frames(cv, k, f, alive, st, Color8(112, 100, 84))
