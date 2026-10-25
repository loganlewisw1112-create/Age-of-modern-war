extends RefCounted
## G6 proposal art, module g6_infantry (agent art-infantry). Built only from the game's own art libraries
## (G5 figure kit for people, faction_m_lib for Machine units, g5_bld_lib for the tunnel entrance).
##   Human A squads  a_marines (4, wade) a_paratroopers (4, land) a_eod (2, sweep) a_jtac (2, lase)
##                   a_manpads (2, fire = launch, aim = tracking)
##   Human B squads  b_conscripts (10, own 64x44 sheet, charge) b_satchel_sappers (3, plant)
##                   b_marksman (1, prone) b_propaganda_team (2, broadcast)
##   Irregulars      x_ambush_cell (4, hidden / ambush in brush) x_tunnel (building: entrance + emerging fighter)
##   Machine         m_shield_drone (air, shield) m_stalker_synth (cloak) m_repair_swarm2 (work = relink)
##                   m_breacher_crawler (fire = armed, detonate)
##   Human A Stage 10 a_exo_trooper (1-man vehicle-size sheet, rotary gun)
const P = preload("res://tools/art/pix.gd")
const D = preload("res://tools/art/vdetail.gd")
const VH = preload("res://tools/art/vehicles.gd")
const V = preload("res://tools/art/faction_b_veh.gd")
const L = preload("res://tools/art/g4_units_lib.gd")
const SL = preload("res://tools/art/g5_units_lib.gd")
const SQ = preload("res://tools/art/g5_units_sq.gd")
const FIG = preload("res://tools/art/g5_units_fig.gd")
const U = preload("res://tools/art/units.gd")
const BI = preload("res://tools/art/faction_b_inf.gd")
const M = preload("res://tools/art/faction_m_lib.gd")
const MD = preload("res://tools/art/faction_m_drone.gd")
const SW = preload("res://tools/art/g5_units_m.gd")
const K = preload("res://tools/art/g5_bld_lib.gd")
const H = preload("g6_lib.gd")

const OUTL := Color(0.09, 0.09, 0.07, 1)
const MOUTL := Color(0.07, 0.08, 0.09, 1)
const A := {"coat": U.UNIFORM, "trouser": U.TROUSER, "boot": U.BOOT, "skin": U.SKIN, "head": "helm_a", "weapon": "rifle"}
const BS := {"coat": BI.DRILL, "trouser": BI.TROUSER, "boot": BI.BOOT, "skin": BI.SKIN, "head": "helm_b",
	"weapon": "rifle", "belt": BI.LEATHER}
const MAR_COAT := Color8(112, 106, 76)
const MAR_TROUSER := Color8(88, 86, 62)
const TUBE := Color8(78, 84, 58)
const LASER := Color8(255, 64, 52)
const WATER := Color8(58, 98, 106)
const FOAM := Color8(214, 228, 222)
const BRICK := Color8(138, 76, 56)
const SATCHEL := Color8(150, 132, 96)
const CANOPY := Color8(112, 118, 80)
const WOOD := Color8(112, 80, 48)
const BURLAP := Color8(150, 134, 98)
const LEAF := [Color8(70, 84, 44), Color8(88, 100, 52), Color8(60, 72, 38), Color8(100, 106, 60)]
# Irregulars: mismatched civilian / captured kit
const X_TAN := Color8(150, 128, 92)
const X_SAND := Color8(170, 150, 110)
const X_GREY := Color8(104, 96, 84)
const X_JEANS := Color8(72, 78, 92)
const X_KHAKI := Color8(120, 104, 74)
const X_SKIN := Color8(156, 116, 86)
const SCARF_RED := Color8(150, 58, 46)
const SCARF_BLK := Color8(44, 42, 40)
const SCARF_TAN := Color8(184, 168, 128)
const SCARF_GRN := Color8(92, 104, 70)

const SHOW := {
	"a_marines": {"row": 0, "frame": "wade", "ground": "sand"},
	"a_paratroopers": {"row": 1, "frame": "land", "ground": "grass"},
	"a_eod": {"row": 1, "frame": "sweep", "ground": "grass"},
	"a_jtac": {"row": 0, "frame": "lase", "ground": "grass"},
	"a_manpads": {"row": 0, "frame": "fire", "ground": "grass"},
	"b_conscripts": {"row": 1, "frame": "charge", "ground": "mud"},
	"b_satchel_sappers": {"row": 6, "frame": "plant", "ground": "dirt"},
	"b_marksman": {"row": 0, "frame": "prone", "ground": "grass"},
	"b_propaganda_team": {"row": 0, "frame": "broadcast", "ground": "grass"},
	"m_shield_drone": {"row": 1, "frame": "shield", "ground": "grass", "alt": 16, "shadow": [7, 3]},
	"m_stalker_synth": {"row": 1, "frame": "fire", "ground": "grass"},
	"m_repair_swarm2": {"row": 0, "frame": "work", "ground": "dirt"},
	"m_breacher_crawler": {"row": 0, "frame": "fire", "ground": "dirt"},
	"a_exo_trooper": {"row": 2, "frame": "fire", "ground": "conc"},
	"x_ambush_cell": {"row": 1, "frame": "ambush", "ground": "grass"},
	"x_tunnel": {"row": 0, "ground": "dirt"},
}


static func build(out: Dictionary) -> void:
	SL.squad_sheet(out, "a_marines", 4, marines, MAR_FR)
	SL.squad_sheet(out, "a_paratroopers", 4, paras, PARA_FR)
	SL.squad_sheet(out, "a_eod", 2, eod, EOD_FR)
	SL.squad_sheet(out, "a_jtac", 2, jtac, JTAC_FR)
	SL.squad_sheet(out, "a_manpads", 2, manpads, MP_FR)
	big_sheet(out, "b_conscripts", 10, CS, conscripts, CON_FR)
	SL.squad_sheet(out, "b_satchel_sappers", 3, sappers, SAP_FR)
	SL.squad_sheet(out, "b_marksman", 1, marksman, MK_FR)
	SL.squad_sheet(out, "b_propaganda_team", 2, propaganda, PRO_FR)
	var sh := SL.drone_shadow(out, "m_shield_drone_shadow", 7.0, 3.0)
	SL.veh_sheet(out, "m_shield_drone", {"fw": 64, "fh": 60, "pivot": [32, 28]}, shield_drone, ["idle", "move", "fire", "shield"],
		{"air": true, "altitude": 16, "bob": 1, "shadow": sh})
	SL.veh_sheet(out, "m_stalker_synth", {"fw": 36, "fh": 44, "pivot": [18, 36]}, synth, ["idle", "walk_a", "walk_b", "fire", "cloak"])
	SL.veh_sheet(out, "m_repair_swarm2", {"fw": 64, "fh": 52, "pivot": [32, 34]}, swarm2, ["idle", "move", "fire", "work"])
	SL.veh_sheet(out, "m_breacher_crawler", {"fw": 44, "fh": 40, "pivot": [22, 26]}, breacher, ["idle", "move", "fire", "detonate"])
	SL.veh_sheet(out, "a_exo_trooper", {"fw": 40, "fh": 44, "pivot": [20, 35]}, exo, ["idle", "walk_a", "walk_b", "fire"])
	SL.squad_sheet(out, "x_ambush_cell", 4, ambush, AMB_FR)
	H.bld(out, "x_tunnel", 1, 22, tunnel)


# ================================================================ shared figure helpers
## Figure item like SQ.fig_at, with an optional post-process on the outlined 24x26 figure canvas.
static func fig_post(foot: Vector2, k: int, pose: String, st: Dictionary, post: Callable = Callable()) -> Array:
	var fp := Vector2i(int(round(foot.x)), int(round(foot.y)))
	return [fp.y, func(c) -> void:
		var m = P.Canvas.new(24, 26)
		FIG.draw(m, k, pose, st)
		if post.is_valid():
			post.call(m)
		SL.stamp(c, m, fp.x - SL.FIG_PIV.x, fp.y - SL.FIG_PIV.y)]


## SQ.std with a per-member post-process (headscarves for the Irregulars).
static func std_post(cv, k: int, fname: String, n: int, alive: int, styles: Array, posts: Array, fire_pose := "aim") -> bool:
	match fname:
		"idle", "walk_a", "walk_b":
			SL.formation(cv, k, 0, n, alive, func(c, kk: int, _f: int, i: int) -> void:
				var pose := fname
				if fname != "idle" and i % 2 == 1:
					pose = "walk_b" if fname == "walk_a" else "walk_a"
				FIG.draw(c, kk, "stand" if pose == "idle" else pose, styles[i])
				if (posts[i] as Callable).is_valid():
					posts[i].call(c))
		"fire":
			SL.formation(cv, k, 0, n, alive, func(c, kk: int, _f: int, i: int) -> void:
				var st: Dictionary = styles[i]
				FIG.draw(c, kk, fire_pose, SQ.m(st, {"fire": true}))
				if (posts[i] as Callable).is_valid():
					posts[i].call(c))
		"wounded":
			SL.place(cv, Vector2i(SQ.PIV), func(c) -> void:
				FIG.draw(c, k, "lie", styles[0])
				if (posts[0] as Callable).is_valid():
					posts[0].call(c))
		_:
			return false
	return true


static func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.03 and a.a > 0.9


## Headscarf / shemagh over the bare head of an outlined figure: finds the head by its skin pixels,
## wraps the crown (and the lower face when `wrap`), leaves a tail at the back, re-outlines the cloth.
static func scarf(m, skin: Color, col: Color, wrap: bool, k: int) -> void:
	var tones := [skin, P.mul(skin, 0.75), P.mul(skin, 0.6)]
	var y0 := 99
	for y in m.h:
		for x in m.w:
			var c: Color = m.get_px(x, y)
			for t: Color in tones:
				if _near(c, t):
					y0 = mini(y0, y)
		if y0 < 99:
			break
	if y0 == 99:
		return
	var x0 := 99
	var x1 := -1
	for x in m.w:
		var c: Color = m.get_px(x, y0)
		for t: Color in tones:
			if _near(c, t):
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
	var painted: Array = []
	var put := func(x: int, y: int, cc: Color) -> void:
		m.px(x, y, cc)
		painted.append(Vector2i(x, y))
	for x in range(x0 - 1, x1 + 2):
		put.call(x, y0 - 1, P.mul(col, 1.1 if x == x0 - 1 else 1.0))
	for x in range(x0, x1 + 1):
		put.call(x, y0, P.mul(col, 0.88))
	if wrap:
		for x in range(x0, x1 + 1):
			if _near(m.get_px(x, y0 + 2), tones[0]) or _near(m.get_px(x, y0 + 2), tones[1]):
				put.call(x, y0 + 2, P.mul(col, 0.8))
	var d := L.sd(k)
	var tx := x0 - 2 if d.x >= 0 else x1 + 2
	put.call(tx, y0, P.mul(col, 0.8))
	put.call(tx, y0 + 1, P.mul(col, 0.7))
	for p: Vector2i in painted:
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + o
			if m.get_px(q.x, q.y).a < 0.1:
				m.px(q.x, q.y, OUTL)


## Wading: legs below the waterline are erased, a foam ring sits where the body meets the water.
static func wade_cut(m, line_y: int) -> void:
	var xs: Array = []
	for x in m.w:
		if m.get_px(x, line_y - 1).a > 0.6:
			xs.append(x)
	for y in range(line_y, m.h):
		for x in m.w:
			m.img.set_pixel(x, y, Color(0, 0, 0, 0))
			m.mask.set_pixel(x, y, Color(0, 0, 0, 0))
	if xs.is_empty():
		return
	var a: int = xs.min()
	var b: int = xs.max()
	m.rect(a - 1, line_y, b - a + 3, 1, FOAM)
	m.rect(a - 2, line_y + 1, b - a + 5, 1, Color(FOAM.r, FOAM.g, FOAM.b, 0.45))


## Waist cut (figure climbing out of a hole): rows from cut_y down are erased.
static func waist_cut(m, cut_y: int) -> void:
	for y in range(cut_y, m.h):
		for x in m.w:
			m.img.set_pixel(x, y, Color(0, 0, 0, 0))
			m.mask.set_pixel(x, y, Color(0, 0, 0, 0))


## Shoulder point of a standing figure at a squad-frame foot point.
static func shoulder(foot: Vector2, d: Vector2) -> Vector2:
	return foot + Vector2(d.x * 1.5, -10)


static func bush(pc, p: Vector2, r: float, s: int) -> void:
	for i in 6:
		var a := float(i) * TAU / 6.0 + P.hn(i, s, 51) * 0.6
		var q := p + Vector2(cos(a) * r * 0.75, sin(a) * r * 0.32 - r * 0.45)
		pc.ellipse(q.x, q.y, r * 0.55, r * 0.5, LEAF[P.hi(i, s, 52, 4)])
	pc.ellipse(p.x, p.y - r * 0.7, r * 0.6, r * 0.55, LEAF[(s + 1) % 4])
	for i in 5:  # lit leaf tips
		pc.px(int(p.x) - int(r) + P.hi(i, s, 53, int(r * 2.0)), int(p.y - r * 1.1) + P.hi(i, s, 54, 3), P.mul(LEAF[3], 1.25))


# ================================================================ a_marines
const MAR_FR := ["idle", "walk_a", "walk_b", "fire", "wade", "wounded"]


static func _mar_styles() -> Array:
	var st := SQ.m(A, {"coat": MAR_COAT, "trouser": MAR_TROUSER, "back": "pack"})
	return [SQ.m(st, {"back": "radio"}), st, SQ.m(st, {"weapon": "gl"}), SQ.m(st, {"weapon": "carbine", "back": "ammo"})]


static func marines(cv, k: int, f: int, alive: int) -> void:
	var styles := _mar_styles()
	var fn: String = MAR_FR[f]
	if SQ.std(cv, k, fn, 4, alive, styles):
		return
	# wade: surf patch, the squad pushing through it waist-deep in a line abreast, bow waves ahead
	var d := L.sd(k)
	var pr := SL.perp(d)
	var c := SQ.PIV + Vector2(0, -2)
	var items := [SQ.prop_at(-99.0, func(pc) -> void: _surf(pc, c, d, k), false)]
	var pts := SQ.take([c + Vector2(-5, 1) + d * 1.0, c + Vector2(6, -1), c + Vector2(-16, -1) - d * 1.5, c + Vector2(17, 1) - d * 0.5], alive)
	for i in pts.size():
		var pose := "walk_a" if i % 2 == 0 else "walk_b"
		items.append(fig_post(pts[i], k, pose, styles[i], func(m) -> void: wade_cut(m, 16)))
	SQ.layered(cv, items)
	for p: Vector2 in pts:  # spray at the chest where they push the water
		var b := p + Vector2(0, -6) + d * 3.0
		cv.px(int(b.x), int(b.y), Color(1, 1, 1, 0.8))
		cv.px(int(b.x + d.x * 2.0), int(b.y) - 1, Color(1, 1, 1, 0.55))


static func _surf(pc, c: Vector2, d: Vector2, k: int) -> void:
	var w := Color(WATER.r, WATER.g, WATER.b, 0.88)
	pc.ellipse(c.x, c.y - 4, 23.0, 8.5, P.mul(w, 0.9))
	pc.ellipse(c.x + d.x * 3.0, c.y - 4 + d.y * 1.5, 19.0, 6.5, w)
	for i in 9:  # ripple dashes
		var x := int(c.x) - 18 + P.hi(i, k, 611, 36)
		var y := int(c.y) - 9 + P.hi(i, k, 612, 10)
		pc.rect(x, y, 3, 1, Color(0.78, 0.88, 0.88, 0.5))
	for i in 30:  # breaking foam along the near (beach) edge of the surf
		var a := 0.15 * PI + float(i) / 29.0 * 0.7 * PI
		var q := c + Vector2(cos(a) * 22.5, -4.0 + sin(a) * 8.0)
		pc.px(int(q.x), int(q.y), Color(FOAM.r, FOAM.g, FOAM.b, 0.8 if i % 4 != 0 else 0.45))
		if i % 3 == 0:
			pc.px(int(q.x) + 1, int(q.y) - 2, Color(FOAM.r, FOAM.g, FOAM.b, 0.4))


# ================================================================ a_paratroopers
const PARA_FR := ["idle", "walk_a", "walk_b", "fire", "land", "wounded"]


static func _para_styles() -> Array:
	var st := SQ.m(A, {"back": "pack", "weapon": "carbine"})
	return [SQ.m(st, {"back": "radio"}), st, SQ.m(st, {"weapon": "rifle"}), SQ.m(st, {"weapon": "hmg", "back": "ammo"})]


static func paras(cv, k: int, f: int, alive: int) -> void:
	var styles := _para_styles()
	var fn: String = PARA_FR[f]
	if SQ.std(cv, k, fn, 4, alive, styles, "kneel_aim"):
		return
	# land: one man still under his canopy, one just down with the chute collapsing behind him,
	# two already kneeling to secure the drop zone
	var d := L.sd(k)
	var pr := SL.perp(d)
	var c := SQ.PIV
	var items := []
	var down := c + pr * 7.0 + d * 1.0
	if alive >= 2:
		items.append(SQ.prop_at(down.y - 1.0, func(pc) -> void: _chute_down(pc, down, d, pr)))
		items.append(SQ.fig_at(down, k, "stand", styles[1]))
	var kn := SQ.take([c - pr * 9.0 + Vector2(0, 2), c + d * 6.0 + Vector2(0, 3)], maxi(0, alive - 2))
	for i in kn.size():
		items.append(SQ.fig_at(kn[i], (k + (6 if i == 0 else 0)) % 8, "kneel_aim", styles[2 + i]))
	var air := c + Vector2(-2, -4) - pr * 2.0
	var land := c + Vector2(-2, 2) - pr * 2.0
	items.append([-50, func(cc) -> void:  # landing shadow of the man in the air
		cc.ellipse(land.x + 1, land.y, 3.5, 1.3, Color.BLACK, true)
		cc.flush_shadow()])
	items.append([90, func(cc) -> void:
		SL.place(cc, Vector2i(air), func(m) -> void: FIG.draw(m, k, "stand", styles[0]))
		var pc = P.Canvas.new(cc.w, cc.h)
		_canopy(pc, air, k)
		pc.outline(OUTL)
		SL.stamp(cc, pc, 0, 0)])
	SQ.layered(cv, items)


static func _canopy(pc, foot: Vector2, k: int) -> void:
	var top := foot + Vector2(1, -18)
	var rx := 9.5
	for y in range(int(top.y) - 5, int(top.y) + 2):
		for x in range(int(top.x - rx) - 1, int(top.x + rx) + 2):
			var dx := (x + 0.5 - top.x) / rx
			var dy := (y + 0.5 - (top.y + 1.0)) / 5.2
			if dx * dx + dy * dy <= 1.0 and y <= int(top.y) + 1:
				var g := int(floor((x - top.x + rx) / 3.0)) % 2
				var col := P.mul(CANOPY, (1.3 if g == 0 else 0.95) * (1.12 if y < top.y - 2 else 1.0))
				pc.px(x, y, col)
	pc.rect(int(top.x - rx) + 1, int(top.y) + 1, int(rx * 2.0) - 1, 1, P.mul(CANOPY, 0.7))  # skirt
	var sh := foot + Vector2(1, -10)
	for s: float in [-1.0, -0.4, 0.4, 1.0]:  # rigging lines
		pc.line_v(Vector2(top.x + s * (rx - 1.0), top.y + 2), sh, Color(0.82, 0.82, 0.76, 0.85))


static func _chute_down(pc, foot: Vector2, d: Vector2, pr: Vector2) -> void:
	var back := foot - d * 7.0 + Vector2(0, -1)
	pc.ellipse(back.x, back.y, 6.0, 2.4, P.mul(CANOPY, 0.95))
	pc.ellipse(back.x - d.x * 2.0, back.y - 2.0, 4.5, 2.2, P.mul(CANOPY, 1.15))  # half-inflated hump
	pc.ellipse(back.x - d.x * 3.0, back.y - 3.0, 2.5, 1.2, P.mul(CANOPY, 1.3))
	for s: float in [-1.0, 1.0]:
		pc.line_v(back + pr * 3.0 * s, foot + Vector2(0, -8), Color(0.82, 0.82, 0.76, 0.85))


# ================================================================ a_eod (from the orchestrator's ex.gd start)
const EOD_FR := ["idle", "walk_a", "walk_b", "fire", "sweep", "wounded"]


static func eod(cv, k: int, f: int, alive: int) -> void:
	var st := SQ.m(A, {"back": "pack", "weapon": "carbine", "vest": Color8(150, 132, 64)})
	var styles := [st, SQ.m(st, {"back": "tools"})]
	var fn: String = EOD_FR[f]
	if SQ.std(cv, k, fn, 2, alive, styles):
		return
	var d := L.sd(k)
	var pr := SL.perp(d)
	var c := SQ.PIV
	var mine := c + d * 7.0 + Vector2(0, 1)
	var items := [SQ.prop_at(mine.y - 1.0, func(pc) -> void: _mine(pc, mine, c, d, pr), false)]
	var p0 := c - pr * 7.0
	items.append(SQ.fig_at(p0, k, "stand", SQ.m(styles[0], {"weapon": "none"})))
	items.append(SQ.prop_at(p0.y + 0.5, func(pc) -> void: _detector(pc, p0, mine, d)))
	if alive >= 2:
		items.append(SQ.fig_at(mine - d * 4.0 + pr * 5.0, (k + 7) % 8, "work", SQ.m(styles[1], {"weapon": "none", "work": "aid"})))
	SQ.layered(cv, items)


static func _mine(pc, m: Vector2, c: Vector2, d: Vector2, pr: Vector2) -> void:
	pc.ellipse(m.x, m.y, 3.2, 1.6, Color8(66, 60, 44))
	pc.ellipse(m.x, m.y - 0.5, 2.2, 1.1, Color8(84, 92, 62))
	pc.px(int(m.x), int(m.y) - 1, Color8(150, 150, 140))
	for s in [-1.0, 1.0]:  # marker pins either side of the cleared lane, tape between them
		var fp: Vector2 = c + pr * (11.0 * s) + d * 2.0
		pc.line_v(fp, fp + Vector2(0, -5), Color8(60, 50, 36))
		pc.rect(int(fp.x), int(fp.y) - 6, 2, 2, Color8(204, 44, 40))
		var fb: Vector2 = c + pr * (11.0 * s) - d * 8.0
		pc.line_v(fp + Vector2(0, -3), fb + Vector2(0, -3), Color(0.92, 0.9, 0.84, 0.7))
		pc.line_v(fb, fb + Vector2(0, -4), Color8(60, 50, 36))


static func _detector(pc, foot: Vector2, mine: Vector2, d: Vector2) -> void:
	var hand := foot + Vector2(d.x * 3.0, -8.0)
	var head := mine.lerp(foot, 0.25) + Vector2(0, -1)
	pc.line_v(hand, head, Color8(58, 60, 58))
	pc.ellipse(head.x, head.y, 2.2, 1.0, Color8(40, 42, 40))
	pc.px(int(head.x), int(head.y) - 1, Color8(236, 200, 80))


# ================================================================ a_jtac
const JTAC_FR := ["idle", "walk_a", "walk_b", "fire", "lase", "wounded"]


static func jtac(cv, k: int, f: int, alive: int) -> void:
	var lead := SQ.m(A, {"head": "boonie", "weapon": "carbine", "back": "antenna"})
	var rto := SQ.m(A, {"back": "radio", "weapon": "rifle"})
	var styles := [lead, rto]
	var fn: String = JTAC_FR[f]
	if SQ.std(cv, k, fn, 2, alive, styles):
		return
	# lase: designator on a short tripod, the controller kneeling behind it, beam + reticle on the target,
	# the radio man kneeling with the handset passing the call
	var d := L.sd(k)
	var pr := SL.perp(d)
	var c := SQ.PIV + Vector2(0, 1)
	var p0 := c - d * 3.0
	var des := p0 + d * 4.0
	var tgt := c + d * 17.0 + Vector2(0, -2)
	tgt = Vector2(clampf(tgt.x, 6, 42), clampf(tgt.y, 8, 33))
	var items := []
	items.append(SQ.fig_at(p0, k, "kneel", SQ.m(lead, {"weapon": "none"})))
	items.append(SQ.prop_at(des.y + 0.2, func(pc) -> void: _designator(pc, des, d)))
	if alive >= 2:
		var p1 := c - d * 4.0 + Vector2(-10.0 if d.x >= -0.1 else 10.0, -1)
		items.append(SQ.fig_at(p1, k, "kneel", SQ.m(rto, {"weapon": "none"})))
		items.append(SQ.prop_at(p1.y + 0.3, func(pc) -> void:
			var hs := p1 + Vector2(d.x * 1.0, -8)
			pc.rect(int(hs.x), int(hs.y), 1, 2, Color8(40, 40, 38))))  # handset at the ear
	SQ.layered(cv, items)
	var lens := des + Vector2(d.x * 2.0, -5 + d.y * 1.0)
	var n := int(lens.distance_to(tgt))
	for i in n:  # pulsed beam
		if i % 3 == 2:
			continue
		var p: Vector2 = lens.lerp(tgt, float(i) / maxf(1.0, n))
		cv.px(int(p.x), int(p.y), Color(LASER.r, LASER.g, LASER.b, 0.9))
	_reticle(cv, tgt)


static func _designator(pc, p: Vector2, d: Vector2) -> void:
	var h := p + Vector2(0, -4)
	for s: float in [-1.0, 1.0]:
		pc.line_v(h, p + Vector2(s * 2.0, 0), Color8(52, 54, 50))
	pc.line_v(h, p - Vector2(d.x * 2.0, -1), Color8(52, 54, 50))
	pc.rect(int(h.x) - 2, int(h.y) - 2, 5, 2, Color8(70, 74, 60))  # designator body
	pc.rect(int(h.x) - 1, int(h.y) - 3, 2, 1, Color8(58, 60, 52))
	var ln := h + Vector2(d.x * 2.0, -1 + d.y)
	pc.px(int(ln.x), int(ln.y), Color8(150, 40, 36))


static func _reticle(cv, t: Vector2) -> void:
	var col := Color(LASER.r, LASER.g, LASER.b, 0.95)
	cv.px(int(t.x), int(t.y), Color8(255, 220, 200))
	for s: Vector2i in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]:
		cv.px(int(t.x) + s.x * 3, int(t.y) + s.y * 2, col)
		cv.px(int(t.x) + s.x * 2, int(t.y) + s.y * 2, col)
		cv.px(int(t.x) + s.x * 3, int(t.y) + s.y * 1, col)
	cv.ellipse(t.x + 0.5, t.y + 0.5, 1.8, 1.0, Color(1, 0.4, 0.3, 0.35))


# ================================================================ a_manpads
const MP_FR := ["idle", "walk_a", "walk_b", "fire", "aim", "wounded"]


static func manpads(cv, k: int, f: int, alive: int) -> void:
	var gun := SQ.m(A, {"weapon": "rpg", "back": "pack"})
	var spot := SQ.m(A, {"head": "boonie", "weapon": "carbine", "back": "rockets"})
	var fn: String = MP_FR[f]
	if fn != "fire" and fn != "aim":
		SQ.std(cv, k, fn, 2, alive, [gun, spot])
		return
	# fire = missile leaving the tube on a climbing smoke trail, backblast behind; aim = tracking (tube up,
	# spotter on binoculars)
	var d := L.sd(k)
	var pr := SL.perp(d)
	var c := SQ.PIV + Vector2(0, 2)
	var sx := 1.0 if d.x >= -0.1 else -1.0
	var p0 := c + Vector2(4.0 * sx, -1)
	var items := [SQ.fig_at(p0, k, "stand", SQ.m(gun, {"weapon": "none"}))]
	var sh := shoulder(p0, d)
	var dv := Vector2(d.x, d.y * 0.5)
	var tail := sh - dv * 4.5 + Vector2(0, 2.5)
	var tip := sh + dv * 5.0 + Vector2(0, -4.5)
	items.append(SQ.prop_at(p0.y + (0.5 if d.y > -0.2 else -0.5), func(pc) -> void: _launcher(pc, tail, tip)))
	if alive >= 2:
		var p1 := c + Vector2(-9.0 * sx, 2) - d * 2.0
		items.append(SQ.fig_at(p1, k, "kneel", SQ.m(spot, {"weapon": "none"})))
		items.append(SQ.prop_at(p1.y + 0.4, func(pc) -> void:
			var e := p1 + Vector2(d.x * 1.5, -9)
			pc.rect(int(e.x) - 1, int(e.y), 3, 1, Color8(36, 38, 36))
			pc.px(int(e.x) + (1 if d.x >= 0 else -1), int(e.y), Color8(120, 150, 160))))
	SQ.layered(cv, items)
	if fn == "fire":
		var back := tail - (tip - tail).normalized() * 3.0
		L.puff(cv, back, 3.0, 0.55)
		L.puff(cv, back - (tip - tail).normalized() * 3.0 + Vector2(0, 1), 2.2, 0.35)
		var dir := (tip - tail).normalized()
		var m := tip + dir * 10.0 + Vector2(0, -8)
		m = Vector2(clampf(m.x, 3, 45), maxf(m.y, 2))
		var n := 9
		for i in n:  # corkscrewing smoke trail from the tube to the missile
			var t := float(i) / float(n)
			var p: Vector2 = tip.lerp(m, t) + Vector2(sin(t * 9.0) * 0.8, 0)
			L.puff(cv, p, 1.2 + t * 0.4, 0.45 * (1.0 - t * 0.4), Color(0.9, 0.9, 0.86))
		cv.line_v(m - dir * 2.0, m, Color8(196, 200, 190))
		cv.px(int(m.x), int(m.y), Color8(80, 84, 76))
		L.flash(cv, m - dir * 3.0, 0.6)
		L.flash(cv, tip, 0.7)


static func _launcher(pc, tail: Vector2, tip: Vector2) -> void:
	pc.line_v(tail, tip, TUBE)
	pc.line_v(tail + Vector2(0, 1), tip + Vector2(0, 1), P.mul(TUBE, 0.78))
	pc.rect(int(tip.x) - 1, int(tip.y) - 1, 2, 2, Color8(150, 156, 140))  # seeker dome
	var g: Vector2 = tail.lerp(tip, 0.4)
	pc.rect(int(g.x) - 1, int(g.y) - 2, 2, 1, Color8(50, 52, 48))  # IFF / sight block
	pc.rect(int(g.x), int(g.y) + 1, 1, 2, Color8(50, 52, 48))       # grip-stock
	pc.px(int(tail.x), int(tail.y), Color8(52, 56, 42))


# ================================================================ b_conscripts (10 men)
const CON_FR := ["idle", "walk_a", "walk_b", "fire", "charge", "wounded"]
const CS := {"fw": 64, "fh": 44, "pivot": [32, 35]}
const CSLOTS := [Vector2(0, 0), Vector2(-12, -3), Vector2(12, -2), Vector2(-6, 5), Vector2(7, 6), Vector2(-21, 2),
	Vector2(21, 3), Vector2(-2, -8), Vector2(-15, -9), Vector2(13, -9)]


## Squad sheet for more than 4 men: same layout and alive_sheets as SL.squad_sheet, bigger frame.
static func big_sheet(out: Dictionary, def: String, n: int, sp: Dictionary, draw: Callable, frames: Array) -> void:
	var alive_sheets := {}
	var fw: int = sp.fw
	var fh: int = sp.fh
	for a in range(n, 0, -1):
		var img := Image.create(fw * frames.size(), fh * 8, false, Image.FORMAT_RGBA8)
		var msk := Image.create(fw * frames.size(), fh * 8, false, Image.FORMAT_RGBA8)
		for k in 8:
			for f in frames.size():
				var cv = P.Canvas.new(fw, fh)
				draw.call(cv, k, f, a)
				img.blit_rect(cv.img, Rect2i(0, 0, fw, fh), Vector2i(f * fw, k * fh))
				msk.blit_rect(cv.mask, Rect2i(0, 0, fw, fh), Vector2i(f * fw, k * fh))
		var stem := "units/%s" % def if a == n else "units/%s_a%d" % [def, a]
		out.images[stem + ".png"] = img
		out.images[stem + "_mask.png"] = msk
		if a < n:
			alive_sheets[str(a)] = {"file": stem + ".png", "mask": stem + "_mask.png"}
	var man: Dictionary = out.manifest.get("infantry", {})
	man[def] = {"file": "units/%s.png" % def, "mask": "units/%s_mask.png" % def, "fw": fw, "fh": fh,
		"pivot": (sp.pivot as Array).duplicate(), "frames": frames.duplicate(), "facings": 8, "squad_size": n,
		"alive_sheets": alive_sheets}
	out.manifest["infantry"] = man


static func _con_styles() -> Array:
	var coats := [BI.DRILL, BI.COAT, BI.DRILL, BI.OVERALL, BI.DRILL, BI.COAT, Color8(100, 92, 70), BI.DRILL, BI.OVERALL, BI.COAT]
	var heads := ["cap_b", "helm_b", "cap_b", "helm_b", "cap_b", "", "helm_b", "cap_b", "helm_b", "cap_b"]
	var wpns := ["pistol", "rifle", "rifle", "rifle", "shovel", "rifle", "rifle", "rifle", "pick", "rifle"]
	var r: Array = []
	for i in 10:
		r.append(SQ.m(BS, {"coat": coats[i], "head": heads[i], "weapon": wpns[i],
			"trouser": BI.TROUSER if i % 3 != 2 else Color8(92, 82, 62), "back": "pack" if i % 4 == 1 else ""}))
	r[0] = SQ.m(r[0], {"coat": BI.COAT, "head": "cap_b", "belt": BI.RUST})  # the commissar
	return r


static func conscripts(cv, k: int, f: int, alive: int) -> void:
	var styles := _con_styles()
	var fn: String = CON_FR[f]
	var piv := Vector2(CS.pivot[0], CS.pivot[1])
	if fn == "wounded":
		SL.place(cv, Vector2i(piv), func(c) -> void: FIG.draw(c, k, "lie", styles[1]))
		return
	var d := L.sd(k)
	var items := []
	var banner_foot := Vector2.ZERO
	for i in mini(alive, 10):
		var st: Dictionary = styles[i]
		var wpn := String(st.weapon)
		var foot: Vector2 = piv + CSLOTS[i] + Vector2(float((i * 7) % 3 - 1), 0)
		var pose := "stand"
		match fn:
			"walk_a", "walk_b":
				pose = fn if i % 2 == 0 else ("walk_b" if fn == "walk_a" else "walk_a")
			"fire":
				if wpn == "rifle" or wpn == "pistol":
					pose = "aim"
					st = SQ.m(st, {"fire": (i % 3) != 1})  # a ragged volley
			"charge":
				foot += d * float(3 + (i % 3) * 2)
				pose = "walk_a" if i % 2 == 0 else "walk_b"
				if i == 0:
					pose = "throw"
				if i == 3:
					banner_foot = foot
		items.append(fig_post(foot, k, pose, st))
	if fn == "charge" and alive > 3:
		items.append(SQ.prop_at(banner_foot.y + 0.5, func(pc) -> void: _banner(pc, banner_foot, d, 1)))
	SQ.layered(cv, items)


## Pole + team-dyed banner with a pale cog-star emblem, held at hand height at a squad-frame foot point.
static func _banner(pc, foot: Vector2, d: Vector2, wave: int) -> void:
	var hand := foot + Vector2(d.x * 2.0 + 1.0, -8)
	var top := hand + Vector2(0, -12)
	pc.line_v(hand + Vector2(0, 3), top, WOOD)
	pc.px(int(top.x), int(top.y) - 1, Color8(200, 170, 80))  # finial
	var sx := -1 if d.x >= 0 else 1
	var w := 8
	pc.team = true
	for x in w:
		var sag := int(round(sin(float(x + wave * 2) * 0.9) * 0.8))
		for y in 5:
			var l := 0.62 + (0.12 if y == 0 else 0.0) - (0.1 if x == w - 1 else 0.0)
			pc.px(int(top.x) + sx * (x + 1), int(top.y) + y + sag, Color(l, l, l))
	pc.team = false
	var e := Vector2(top.x + sx * 4.5, top.y + 2)
	pc.px(int(e.x), int(e.y), Color8(236, 220, 160))
	pc.px(int(e.x) + 1, int(e.y), Color8(236, 220, 160))
	pc.px(int(e.x), int(e.y) - 1, Color8(236, 220, 160))
	pc.px(int(e.x), int(e.y) + 1, Color8(236, 220, 160))


# ================================================================ b_satchel_sappers
const SAP_FR := ["idle", "walk_a", "walk_b", "fire", "plant", "wounded"]


static func sappers(cv, k: int, f: int, alive: int) -> void:
	var st := SQ.m(BS, {"coat": BI.COAT, "weapon": "smg", "back": "ammo", "belt": BI.RUST})
	var styles := [SQ.m(st, {"back": "pack"}), st, SQ.m(st, {"head": "cap_b", "back": "tools"})]
	var fn: String = SAP_FR[f]
	if SQ.std(cv, k, fn, 3, alive, styles, "crouch_aim"):
		_satchels(cv, k, fn, alive)
		return
	# plant: a brick wall section ahead, the lead sapper kneels at its foot and lays the charge (fuse lit),
	# the second presses against the wall covering, the third is already sprinting back
	var d := L.sd(k)
	var pr := SL.perp(d)
	var c := SQ.PIV + Vector2(0, 1)
	var wall := c + d * 8.0
	var items := [SQ.prop_at(wall.y, func(pc) -> void: _wall(pc, wall, d, pr))]
	var bag := wall - d * 2.0 + pr * 1.0
	items.append(SQ.prop_at(bag.y + 0.1, func(pc) -> void: _satchel(pc, bag, true)))
	items.append(SQ.fig_at(wall - d * 5.0 - pr * 1.0, k, "work", SQ.m(styles[0], {"weapon": "none", "work": "charge"})))
	if alive >= 2:
		items.append(SQ.fig_at(wall - d * 4.0 + pr * 9.0, (k + 6) % 8, "crouch_aim", styles[1]))
	if alive >= 3:
		items.append(SQ.fig_at(c - d * 9.0 - pr * 6.0, (k + 4) % 8, "walk_a", styles[2]))
	SQ.layered(cv, items)
	var sp := bag + Vector2(1, -3)
	cv.px(int(sp.x), int(sp.y), Color8(255, 236, 150))
	cv.px(int(sp.x) + 1, int(sp.y) - 1, Color8(255, 170, 60))
	cv.px(int(sp.x) - 1, int(sp.y) - 1, Color8(255, 210, 110))
	L.puff(cv, sp + Vector2(1, -3), 1.6, 0.4)


## Canvas satchels on the hip of each standing sapper (std frames).
static func _satchels(cv, k: int, fn: String, alive: int) -> void:
	if fn == "wounded":
		return
	var d := L.sd(k)
	var slots: Array = SL.SLOTS[3]
	for i in mini(alive, 3):
		var foot: Vector2 = SQ.PIV + Vector2(slots[i])
		var p := foot + Vector2(-d.x * 2.5 + (1 if d.x < 0 else -1), -7)
		if d.y < -0.2:
			continue
		cv.rect(int(p.x), int(p.y), 2, 3, SATCHEL)
		cv.px(int(p.x), int(p.y), P.mul(SATCHEL, 1.2))


static func _satchel(pc, p: Vector2, lit: bool) -> void:
	pc.rect(int(p.x) - 2, int(p.y) - 3, 4, 3, SATCHEL)
	pc.rect(int(p.x) - 2, int(p.y) - 3, 4, 1, P.mul(SATCHEL, 1.18))
	pc.rect(int(p.x) - 1, int(p.y) - 2, 2, 1, P.mul(SATCHEL, 0.78))  # flap buckle
	pc.line_v(p + Vector2(1, -3), p + Vector2(1, -2) + Vector2(1, -1), Color8(60, 50, 36))
	if lit:
		pc.px(int(p.x) + 2, int(p.y) - 3, Color8(40, 36, 30))


static func _wall(pc, c: Vector2, d: Vector2, pr: Vector2) -> void:
	var prs := pr * Vector2(1.0, 0.5) * 2.0
	var a := c - prs * 6.0
	var b := c + prs * 6.0
	var h := Vector2(0, -9)
	var th := Vector2(d.x, d.y * 0.5) * 3.0
	var face := PackedVector2Array([a, b, b + h, a + h])
	pc.poly(face, P.mul(BRICK, 0.82 if d.y < 0 else 0.95))
	pc.poly(PackedVector2Array([a + h, b + h, b + h + th, a + h + th]), P.mul(BRICK, 1.15))
	for row in range(1, 9, 2):  # mortar courses
		pc.line_v(a + Vector2(0, -row), b + Vector2(0, -row), P.mul(BRICK, 0.62))
	for i in 7:
		var p: Vector2 = a.lerp(b, (i + 0.5) / 7.0)
		pc.px(int(p.x), int(p.y) - 3 - (i % 2) * 2, P.mul(BRICK, 0.6))
	var chip: Vector2 = a.lerp(b, 0.75) + Vector2(0, -8)
	pc.rect(int(chip.x), int(chip.y), 2, 2, Color(0, 0, 0, 0))


# ================================================================ b_marksman (1 man)
const MK_FR := ["idle", "walk_a", "walk_b", "fire", "prone", "wounded"]


static func marksman(cv, k: int, f: int, alive: int) -> void:
	var st := SQ.m(BS, {"head": "cap_b", "weapon": "rifle", "back": "pack", "coat": Color8(100, 90, 62), "belt": BI.LEATHER})
	var fn: String = MK_FR[f]
	if fn == "idle" or fn == "walk_a" or fn == "walk_b" or fn == "wounded":
		SQ.std(cv, k, fn, 1, alive, [st])
		if fn != "wounded":  # long scoped rifle slung over the shoulder
			var d0 := L.sd(k)
			var sh := SQ.PIV + Vector2(d0.x * 1.5, -8)
			cv.px(int(sh.x - d0.x * 2.0), int(sh.y) - 2, Color8(40, 40, 38))
		return
	# fire / prone: prone with a long scoped rifle on a bipod, sacking draped over the back; fire adds the flash
	var d := L.sd(k)
	var foot := SQ.PIV + Vector2(0, 1)
	var items := [fig_post(foot, k, "prone_aim", st)]
	items.append(SQ.prop_at(foot.y + 0.5, func(pc) -> void: _scoped(pc, foot, d, k)))
	SQ.layered(cv, items)
	var dv := d * (1.0 - 0.35 * absf(d.y))
	var off := foot - Vector2(12, 21)
	var c := Vector2(12.0 - d.x * 1.5, 19.0 - d.y * 2.0) + off
	var head := c + dv * 4.0
	var muzzle := head + dv * 9.0 + Vector2(0, 1)
	if fn == "fire":
		L.flash(cv, muzzle, 0.9)
		L.puff(cv, muzzle + Vector2(d.x * 2.0, -2), 1.8, 0.35)
	else:
		var g := head + dv * 2.0 + Vector2(0, -1)
		cv.px(int(g.x), int(g.y), Color8(250, 250, 236))  # scope glint


static func _scoped(pc, foot: Vector2, d: Vector2, k: int) -> void:
	var dv := d * (1.0 - 0.35 * absf(d.y))
	var off := foot - Vector2(12, 21)
	var c := Vector2(12.0 - d.x * 1.5, 19.0 - d.y * 2.0) + off
	var head := c + dv * 4.0
	var muzzle := head + dv * 6.0 + Vector2(0, 1)
	var far := head + dv * 9.0 + Vector2(0, 1)
	pc.line_v(muzzle, far, BI.GUN)  # long barrel beyond the standard rifle
	var sc := head + dv * 2.0 + Vector2(0, -1)
	pc.line_v(sc - dv * 1.0, sc + dv * 1.5, Color8(36, 36, 34))  # scope tube
	var bp := head + dv * 6.5 + Vector2(0, 2)
	pc.line_v(bp, bp + Vector2(-1, 2), Color8(52, 50, 46))  # bipod
	pc.line_v(bp, bp + Vector2(1, 2), Color8(52, 50, 46))
	for i in 7:  # hessian sacking over the shoulders and back
		var t := float(i) / 6.0
		var p := c - dv * (3.0 * t) + Vector2(P.hi(i, k, 801, 3) - 1, -1 - P.hi(i, k, 802, 2))
		pc.px(int(p.x), int(p.y), P.mul(BURLAP, 0.85 + 0.25 * P.hn(i, k, 803)))


# ================================================================ b_propaganda_team
const PRO_FR := ["idle", "walk_a", "walk_b", "fire", "broadcast", "wounded"]


static func propaganda(cv, k: int, f: int, alive: int) -> void:
	var flag := SQ.m(BS, {"head": "cap_b", "weapon": "pistol", "coat": BI.COAT, "belt": BI.RUST})
	var spk := SQ.m(BS, {"head": "helm_b", "weapon": "smg", "back": "radio"})
	var fn: String = PRO_FR[f]
	var d := L.sd(k)
	if fn != "broadcast":
		if fn == "fire":
			SQ.std(cv, k, fn, 2, alive, [flag, spk])
		else:
			SQ.std(cv, k, fn, 2, alive, [SQ.m(flag, {"weapon": "none"}), spk])
		if fn == "wounded":
			return
		var slots: Array = SL.SLOTS[2]
		var f0: Vector2 = SQ.PIV + Vector2(slots[0])
		var pc = P.Canvas.new(cv.w, cv.h)
		_banner(pc, f0, d, f)
		if alive >= 2:
			var f1: Vector2 = SQ.PIV + Vector2(slots[1])
			_horn(pc, f1 + Vector2(-d.x * 2.5, -13), d, 3.0)
		pc.outline(OUTL)
		SL.stamp(cv, pc, 0, 0)
		return
	# broadcast: twin loudspeakers on a mast set up ahead, cable to the operator at the microphone,
	# the bannerman beside it; sound rings roll out toward the enemy
	var pr := SL.perp(d)
	var c := SQ.PIV
	var sx := 1.0 if d.x >= -0.1 else -1.0
	var mast := c + Vector2(11.0 * sx, -1) + d * 2.0
	var items := [SQ.prop_at(mast.y, func(pc) -> void:
		pc.line_v(mast, mast + Vector2(0, -15), Color8(62, 60, 54))
		for s: float in [-1.0, 1.0]:
			pc.line_v(mast + Vector2(0, -15), mast + pr * Vector2(1.0, 0.5) * 3.0 * s, Color8(62, 60, 54))
		_horn(pc, mast + Vector2(-1, -16), d, 4.0)
		_horn(pc, mast + Vector2(1, -12), d, 4.0)
		var op := c + Vector2(1.0 * sx, 2)
		pc.line_v(mast, op + Vector2(2, 0), Color8(30, 30, 28)))]  # cable
	var op := c + Vector2(1.0 * sx, 2)
	if alive >= 2:
		items.append(SQ.fig_at(op, k, "kneel", SQ.m(spk, {"weapon": "none"})))
		items.append(SQ.prop_at(op.y + 0.3, func(pc) -> void:
			var mic := op + Vector2(d.x * 2.0, -7)
			pc.rect(int(mic.x), int(mic.y), 1, 2, Color8(40, 40, 38))))
	var fb := c + Vector2(-10.0 * sx, -1)
	items.append(SQ.fig_at(fb, k, "stand", SQ.m(flag, {"weapon": "none"})))
	items.append(SQ.prop_at(fb.y + 0.5, func(pc) -> void: _banner(pc, fb, d, 2)))
	SQ.layered(cv, items)
	var mouth := mast + Vector2(0, -14) + Vector2(d.x, d.y * 0.5) * 5.0
	for r in [5.0, 9.0]:  # sound rings
		for i in 9:
			var a := (float(i) / 8.0 - 0.5) * 1.6
			var dir := Vector2(d.x, d.y * 0.5).normalized().rotated(a)
			var p: Vector2 = mouth + dir * r * Vector2(1.0, 0.8)
			cv.px(int(p.x), int(p.y), Color(1.0, 0.92, 0.66, 0.7 - r * 0.04))


## Loudspeaker horn: small flared cone pointing along the facing.
static func _horn(pc, base: Vector2, d: Vector2, ln: float) -> void:
	var dv := Vector2(d.x, d.y * 0.5).normalized()
	var pr := Vector2(-dv.y, dv.x)
	var a := base
	var b := base + dv * ln
	var q := PackedVector2Array([a + pr * 0.8, b + pr * 2.0, b - pr * 2.0, a - pr * 0.8])
	pc.poly(q, Color8(104, 106, 92))
	pc.line_v(b + pr * 2.0, b - pr * 2.0, Color8(160, 160, 146))
	pc.px(int(a.x), int(a.y), Color8(80, 78, 70))


# ================================================================ m_shield_drone
static func shield_drone(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	if wreck:
		var g := o + Vector2(0, 16)
		cv.ellipse(g.x + 1, g.y + 1, 6.0, 2.4, Color.BLACK, true)
		cv.flush_shadow()
		M.hexp(cv, o, M.w(rot, 0, 0, -16), 0.11, 3.0, rot, M.DEAD, 191, null, 0.8)
		for i in 4:
			var p := M.sp(o, rot, 0.2 * (1 if i < 2 else -1), 0.22 * (1 if i % 2 == 0 else -1), -16)
			cv.rect(int(p.x) - 1, int(p.y), 3, 1, M.DEAD_D)
		var e := M.sp(o, rot, 0.14, 0, -14)
		cv.ellipse(e.x, e.y, 2.5, 1.5, M.DEAD_SEAM)
		cv.outline(MOUTL)
		V.soot(cv, M.sp(o, rot, 0, 0, -12), 4.0, 197)
		return
	var tilt := 1.0 if f == 1 else 0.0
	var front := M.w(rot, 1, 0).x + M.w(rot, 1, 0).y > 0.0
	var pods: Array = []
	for a in [[1, 1], [1, -1], [-1, 1], [-1, -1]]:
		var c := M.w(rot, 0.17 * a[0], 0.2 * a[1], 4.0 - tilt * a[0])
		pods.append([c, c.x + c.y])
	pods.sort_custom(func(x, y): return x[1] < y[1])
	for i in 2:
		MD._pod(cv, o, rot, pods[i][0], f, i)
	var emi := M.w(rot, 0.13, 0, 1)
	if not front:
		_emitter(cv, o, rot, f)
	var b: Dictionary = M.hexp(cv, o, Vector3(0, 0, 0), 0.13, 5.0, rot, M.GRAPH, 181, null, 0.8)
	for sd in b.sides:
		M.seam(cv, sd.quad, 0.45)
	var t2: Dictionary = M.hexp(cv, o, Vector3(0, 0, 5), 0.1, 2.0, rot, M.PANEL, 183, null, 0.8)
	for sd in t2.sides:
		M.seam(cv, sd.quad, 0.5, false, 0.2, 0.8)
	cv.team = true
	M.hexp(cv, o, Vector3(0, 0, 7), 0.06, 0.0, rot, Color(0.78, 0.78, 0.78), 185)
	cv.team = false
	var mast := M.sp(o, rot, -0.06, 0, 7)
	cv.line_v(mast, mast + Vector2(0, -4), M.JOINT)
	cv.px(int(mast.x), int(mast.y) - 5, M.CYAN)
	if front:
		_emitter(cv, o, rot, f)
	for i in range(2, 4):
		MD._pod(cv, o, rot, pods[i][0], f, i)
	cv.outline(MOUTL)
	for p in pods:
		MD._blur(cv, o, p[0], f)
	if f == 2 or f == 3:
		var sc = P.Canvas.new(cv.w, cv.h)
		_shield(sc, o, rot, f == 3)
		_overlay(cv, sc, not front)
	var ep := M.sp(o, rot, 0.2, 0, 2.5)
	cv.px(int(ep.x), int(ep.y), M.CYAN_HOT)


## Forward emitter: a panel ring with a glowing cyan lens under the nose.
static func _emitter(cv, o: Vector2, rot: float, f: int) -> void:
	var c := M.sp(o, rot, 0.17, 0, 2.5)
	cv.ellipse(c.x, c.y, 3.0, 2.4, M.PANEL_D)
	cv.ellipse(c.x, c.y, 2.0, 1.6, M.TEAL)
	cv.ellipse(c.x, c.y, 1.0, 0.9, M.CYAN if f < 2 else M.CYAN_HOT)


## Curved energy wall ahead of the drone, from the ground (z = -16, the drone flies 16 px up) to just
## above the drone. Translucent fill, bright rims, hex lattice. full = the deployed "shield" frame.
static func _shield(sc, o: Vector2, rot: float, full: bool) -> void:
	var r := 0.55
	var span := 1.15 if full else 0.6
	var n := 18
	var z0 := -16.0
	var fill := Color(M.CYAN.r, M.CYAN.g, M.CYAN.b, 0.2 if full else 0.14)
	var pts_b: Array = []
	var pts_t: Array = []
	for i in n + 1:
		var a := -span + 2.0 * span * float(i) / float(n)
		var wv := M.w(rot, r * cos(a), r * sin(a))
		var zt := 6.0 - 6.0 * absf(a) / span + (2.0 if full else 0.0)
		pts_b.append(P.proj(o, Vector3(wv.x, wv.y, z0 + 1.0 + 3.0 * absf(a))))
		pts_t.append(P.proj(o, Vector3(wv.x, wv.y, zt)))
	for i in n:
		sc.poly(PackedVector2Array([pts_b[i], pts_b[i + 1], pts_t[i + 1], pts_t[i]]), fill)
	var rim := Color(M.CYAN.r, M.CYAN.g, M.CYAN.b, 0.85)
	for i in n:
		sc.line_v(pts_t[i], pts_t[i + 1], rim)
		sc.line_v(pts_b[i], pts_b[i + 1], Color(M.CYAN.r, M.CYAN.g, M.CYAN.b, 0.5))
	for i in range(0, n + 1, 3):
		var t: Vector2 = pts_t[i]
		var bb: Vector2 = pts_b[i]
		for j in 5:  # hex lattice nodes up each rib
			var p: Vector2 = bb.lerp(t, (j + 0.5) / 5.0) + Vector2((j % 2) * 1.0, 0)
			sc.px(int(p.x), int(p.y), Color(M.CYAN_HOT.r, M.CYAN_HOT.g, M.CYAN_HOT.b, 0.6))
	if full:
		for i in 6:  # deflected rounds sparking on the shield face
			var q: Vector2 = (pts_b[3 + i * 2] as Vector2).lerp(pts_t[3 + i * 2], 0.3 + 0.1 * (i % 3))
			sc.px(int(q.x), int(q.y), Color8(255, 240, 180))


## Composite a translucent effect canvas onto cv; behind = keep it out of solid sprite pixels.
static func _overlay(cv, sc, behind: bool) -> void:
	for y in cv.h:
		for x in cv.w:
			var s: Color = sc.img.get_pixel(x, y)
			if s.a <= 0.0:
				continue
			var dcol: Color = cv.img.get_pixel(x, y)
			if behind and dcol.a >= 0.6:
				continue
			cv.img.set_pixel(x, y, dcol.blend(s))


# ================================================================ m_stalker_synth
static func synth(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	if wreck:
		_synth_wreck(cv, rot, o)
		return
	var stride := 0.0
	var bob := 0.0
	if f == 1:
		stride = 0.06
		bob = -1.0
	elif f == 2:
		stride = -0.06
		bob = -1.0
	var lunge := 0.03 if f == 3 else 0.0
	cv.ellipse(o.x + 2, o.y + 0.5, 6.0, 2.4, Color.BLACK, true)
	cv.flush_shadow()
	var rnear := M.w(rot, 0, 1).x + M.w(rot, 0, 1).y > 0.0
	var fnear := M.w(rot, 1, 0).x + M.w(rot, 1, 0).y > 0.0
	var hipz := 13.0 + bob
	for s: float in ([1.0, -1.0] if not rnear else [-1.0, 1.0]):
		if s == (1.0 if rnear else -1.0):
			continue
		_synth_leg(cv, o, rot, s, stride, hipz)
	_synth_arm(cv, o, rot, -1.0 if rnear else 1.0, f, bob, lunge)
	# pelvis, torso, shoulders, head
	M.hexp(cv, o, M.w(rot, lunge, 0, hipz - 1.0), 0.045, 3.0, rot, M.GRAPH_D, 401, null, 0.7)
	var t: Dictionary = M.hexp(cv, o, M.w(rot, lunge, 0, hipz + 1.0), 0.05, 6.0, rot, M.GRAPH, 403, null, 0.75)
	for sd in t.sides:
		M.seam(cv, sd.quad, 0.35, false, 0.15, 0.85)
	var sh: Dictionary = M.hexp(cv, o, M.w(rot, lunge, 0, hipz + 6.0), 0.07, 3.0, rot, M.PANEL, 405, null, 0.6)
	for sd in sh.sides:
		if absf((sd.n as Vector2).dot(Vector2(-sin(rot), cos(rot)))) > 0.5:
			M.team_panel(cv, sd.quad, 0.15, 0.2, 0.85, 0.8)
	M.rims(cv, sh, M.PANEL)
	var neck := M.sp(o, rot, lunge, 0, hipz + 9.0)
	cv.px(int(neck.x), int(neck.y), M.JOINT)
	var hd: Dictionary = M.hexp(cv, o, M.w(rot, lunge + 0.01, 0, hipz + 10.0), 0.03, 4.0, rot, M.GRAPH_D, 407, M.PANEL_D, 0.8)
	if fnear:
		var e := M.sp(o, rot, lunge + 0.04, 0, hipz + 12.0)
		cv.px(int(e.x), int(e.y), M.CYAN_HOT)
		cv.px(int(e.x) + (1 if M.w(rot, 0, 1).x > 0 else -1), int(e.y), M.CYAN)
	for s: float in [-1.0, 1.0]:
		if s == (1.0 if rnear else -1.0):
			_synth_leg(cv, o, rot, s, stride, hipz)
	_synth_arm(cv, o, rot, 1.0 if rnear else -1.0, f, bob, lunge)
	cv.outline(MOUTL)
	if f == 3:  # monoblade slash arc + a needle round from the carbine
		var a0 := M.sp(o, rot, 0.05, -0.16, hipz + 8.0)
		var a1 := M.sp(o, rot, 0.3, 0.0, hipz - 2.0)
		for i in 9:
			var tt := float(i) / 8.0
			var p: Vector2 = a0.lerp(a1, tt) + Vector2(0, -sin(tt * PI) * 4.0)
			cv.px(int(p.x), int(p.y), Color(M.CYAN_HOT.r, M.CYAN_HOT.g, M.CYAN_HOT.b, 0.9 - tt * 0.4))
	if f == 4:
		_cloak(cv)


static func _synth_leg(cv, o: Vector2, rot: float, s: float, stride: float, hipz: float) -> void:
	var hip := M.w(rot, 0.0, 0.035 * s, hipz)
	var foot := M.w(rot, stride * s, 0.05 * s, 0.0)
	M.leg(cv, o, hip, foot, Vector2(cos(rot), sin(rot)) * 0.06, -1.0, M.GRAPH, 2)
	var shin := P.proj(o, M.w(rot, stride * s * 0.5 + 0.02, 0.045 * s, 5.0))
	cv.px(int(shin.x), int(shin.y), M.PANEL_D)
	cv.px(int(shin.x), int(shin.y) + 1, M.TEAL)


## s = -1 left arm (monoblade), s = +1 right arm (needle carbine).
static func _synth_arm(cv, o: Vector2, rot: float, s: float, f: int, bob: float, lunge: float) -> void:
	var z := 18.0 + bob
	var sh := M.sp(o, rot, lunge, 0.075 * s, z)
	if s < 0.0:
		var raise := 6.0 if f == 3 else 0.0
		var el := M.sp(o, rot, lunge + 0.03, 0.085 * s, z - 5.0 + raise)
		var hand := M.sp(o, rot, lunge + 0.08, 0.08 * s, z - 8.0 + raise * 1.6)
		cv.line_v(sh, el, M.GRAPH_D)
		cv.line_v(el, hand, M.GRAPH_D)
		var tip := M.sp(o, rot, lunge + 0.2, 0.07 * s, z - 11.0 + raise * 2.4)
		cv.line_v(hand, tip, M.PANEL)
		cv.line_v(hand + Vector2(0, 1), tip + Vector2(0, 1), M.CYAN)
	else:
		var hand := M.sp(o, rot, lunge + 0.06, 0.07 * s, z - 4.0)
		cv.line_v(sh, hand, M.GRAPH_D)
		var g0 := M.sp(o, rot, lunge - 0.02, 0.065 * s, z - 3.0)
		var g1 := M.sp(o, rot, lunge + 0.18, 0.065 * s, z - 3.5)
		cv.line_v(g0, g1, M.JOINT)
		cv.px(int(g1.x), int(g1.y), M.CYAN if f != 3 else M.CYAN_HOT)


## Cloaked: the body turns to a faint refracting ghost; only seams, eye and a shimmer edge remain.
static func _cloak(cv) -> void:
	for y in cv.h:
		for x in cv.w:
			var c: Color = cv.img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			if c.a < 0.6:
				cv.img.set_pixel(x, y, Color(c.r, c.g, c.b, c.a * 0.3))
				continue
			cv.mask.set_pixel(x, y, Color(0, 0, 0, 0))
			if c.b > 0.7 and c.g > 0.7 and c.r < 0.9:
				cv.img.set_pixel(x, y, Color(c.r, c.g, c.b, 0.55))
			elif c.get_luminance() < 0.12:
				cv.img.set_pixel(x, y, Color(0.72, 0.92, 0.96, 0.4 if (x + y) % 3 != 0 else 0.15))
			else:
				cv.img.set_pixel(x, y, Color(0.6, 0.72, 0.74, 0.12 + 0.08 * float((x * 3 + y) % 2)))


static func _synth_wreck(cv, rot: float, o: Vector2) -> void:
	cv.ellipse(o.x + 2, o.y + 0.5, 8.0, 2.6, Color.BLACK, true)
	cv.flush_shadow()
	M.hexp(cv, o, M.w(rot, -0.04, 0.02, 0), 0.08, 3.0, rot, M.DEAD, 421, null, 0.5)
	M.hexp(cv, o, M.w(rot, 0.1, 0.03, 0), 0.03, 2.0, rot, M.DEAD_D, 423)
	for s: float in [-1.0, 1.0]:
		cv.line_v(M.sp(o, rot, -0.08, 0.03 * s, 2), M.sp(o, rot, -0.24, 0.07 * s, 0), M.DEAD_D)
	cv.line_v(M.sp(o, rot, 0.02, -0.06, 2), M.sp(o, rot, 0.18, -0.12, 0), M.PANEL_D)
	cv.outline(MOUTL)
	V.soot(cv, M.sp(o, rot, 0, 0, 4), 3.0, 427)


# ================================================================ m_repair_swarm2
const RING6 := [Vector2(0.36, 0.0), Vector2(0.18, 0.3), Vector2(-0.18, 0.3), Vector2(-0.36, 0.0), Vector2(-0.18, -0.3), Vector2(0.18, -0.3)]
const VEE6 := [Vector2(0.38, 0.0), Vector2(0.14, 0.22), Vector2(-0.12, 0.34), Vector2(-0.28, 0.0), Vector2(-0.12, -0.34), Vector2(0.14, -0.22)]


static func swarm2(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	var pts: Array = VEE6 if f == 1 else RING6
	M.hex_shadow(cv, o, M.w(rot, 0.0, 0.0, 0), 0.19, 6.0, rot)
	for p: Vector2 in pts:
		var gp := P.proj(o, M.w(rot, p.x, p.y, 0))
		cv.ellipse(gp.x + 2, gp.y + 1, 2.4, 1.0, Color.BLACK, true)
	cv.flush_shadow()
	var fnear := M.w(rot, 1, 0).x + M.w(rot, 1, 0).y > 0.0
	if f == 3 and not fnear:
		_hulk(cv, o, rot)
	var items: Array = []
	for i in pts.size():
		var p: Vector2 = pts[i]
		var wv := M.w(rot, p.x, p.y, 0)
		items.append([wv.x + wv.y, i])
	items.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var node_done := false
	for it in items:
		if not node_done and it[0] > 0.0:
			_node2(cv, o, rot, f, wreck)
			node_done = true
		SW._bot(cv, o, rot, pts[it[1]], f, it[1], wreck)
	if not node_done:
		_node2(cv, o, rot, f, wreck)
	if f == 3 and fnear:
		_hulk(cv, o, rot)
	cv.outline(MOUTL)
	if wreck:
		return
	if f == 2:  # cutting arcs from the two lead bots
		for i in [0, 1]:
			var p: Vector2 = pts[i]
			var a := P.proj(o, M.w(rot, p.x, p.y, SW._alt(f, i)))
			var t := P.proj(o, M.w(rot, p.x + 0.2, p.y * 0.6, 4))
			cv.line_v(a, t, M.CYAN_HOT)
			L.flash(cv, t, 0.6)
	elif f == 3:  # repair beams into the damaged unit ahead, data relink from the node mast
		var wp := P.proj(o, M.w(rot, 0.6, 0.0, 5))
		for i in pts.size():
			var p: Vector2 = pts[i]
			var b := P.proj(o, M.w(rot, p.x, p.y, SW._alt(f, i) - 2))
			cv.line_v(b, wp, Color(M.CYAN.r, M.CYAN.g, M.CYAN.b, 0.6))
		var mast := P.proj(o, M.w(rot, 0.0, 0.0, 19))
		var n := 10
		for i in n:
			if i % 2 == 1:
				continue
			var tt := float(i) / float(n)
			var q: Vector2 = mast.lerp(wp + Vector2(0, -4), tt) + Vector2(0, -sin(tt * PI) * 6.0)
			cv.rect(int(q.x), int(q.y), 2, 1, M.CYAN_HOT)
		for i in 6:
			cv.px(int(wp.x) - 3 + P.hi(i, 1, 9311, 7), int(wp.y) - 3 + P.hi(i, 2, 9312, 5), Color8(255, 236, 170))


## Upgraded carrier: two-tier hex node, uplink mast with a cyan tip, team cap.
static func _node2(cv, o: Vector2, rot: float, f: int, wreck: bool) -> void:
	var col: Color = M.DEAD if wreck else M.GRAPH
	var r: Dictionary = M.hexp(cv, o, M.w(rot, 0.0, 0.0, 0), 0.18, 5.0, rot, col, 941)
	for sd in r.sides:
		M.seam(cv, sd.quad, 0.5, wreck)
	if wreck:
		return
	var r2: Dictionary = M.hexp(cv, o, M.w(rot, 0.0, 0.0, 5), 0.13, 4.0, rot, M.PANEL, 942)
	for sd in r2.sides:
		M.seam(cv, sd.quad, 0.4, false, 0.2, 0.8)
	M.rims(cv, r2, M.PANEL)
	var cap: Dictionary = M.hexp(cv, o, M.w(rot, 0.0, 0.0, 9), 0.08, 2.0, rot, M.GRAPH_D, 943)
	cv.team = true
	cv.poly(cap.top, Color(0.72, 0.72, 0.72))
	cv.team = false
	var m := P.proj(o, M.w(rot, -0.03, 0.0, 11))
	cv.line_v(m, m + Vector2(0, -7), M.JOINT)
	cv.rect(int(m.x) - 1, int(m.y) - 5, 3, 1, M.PANEL_D)
	cv.px(int(m.x), int(m.y) - 8, M.CYAN_HOT if f == 3 else M.CYAN)
	var e := P.proj(o, M.w(rot, 0.16, 0.0, 3))
	if M.w(rot, 1.0, 0.0).x + M.w(rot, 1.0, 0.0).y > 0.0:
		M.eye(cv, e)


## Damaged Machine unit being relinked: cold hull, half its seams lit again.
static func _hulk(cv, o: Vector2, rot: float) -> void:
	var c := M.w(rot, 0.62, 0.0, 0)
	var r: Dictionary = M.hexp(cv, o, c, 0.11, 6.0, rot, M.DEAD, 951, null, 0.7)
	var i := 0
	for sd in r.sides:
		M.seam(cv, sd.quad, 0.5, i % 2 == 1)
		i += 1
	M.hexp(cv, o, c + Vector3(0, 0, 6), 0.06, 2.0, rot, M.DEAD_D, 953)
	var p := P.proj(o, c + Vector3(0, 0, 3))
	cv.px(int(p.x) + 2, int(p.y) - 2, Color8(255, 190, 90))


# ================================================================ m_breacher_crawler
static func breacher(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	if wreck:
		cv.ellipse(o.x + 1, o.y + 1, 9.0, 3.4, Color8(36, 32, 30))
		for i in 7:
			var p := M.sp(o, rot, -0.2 + 0.07 * i, 0.16 * (1 if i % 2 == 0 else -1) * P.hn(i, 3, 61), 0)
			cv.rect(int(p.x), int(p.y), 2, 1, M.DEAD_D)
		M.hexp(cv, o, M.w(rot, -0.06, 0, 0), 0.08, 2.0, rot, M.DEAD, 611, null, 0.6)
		cv.outline(MOUTL)
		V.soot(cv, M.sp(o, rot, 0, 0, 3), 4.0, 613)
		return
	var gait := 0
	if f == 1:
		gait = 1
	var armed := f >= 2
	var fnear := M.w(rot, 1, 0).x + M.w(rot, 1, 0).y > 0.0
	cv.ellipse(o.x + 2, o.y + 1, 10.0, 4.0, Color.BLACK, true)
	cv.flush_shadow()
	_crawl_legs(cv, o, rot, gait, false)
	if not fnear:
		_charge(cv, o, rot, armed, f)
	var b: Dictionary = P.box(cv, o, Vector3(0, 0, 3), 0.16, 0.09, 4.0, rot, M.GRAPH, 0.06, 621)
	for sd in b.sides:
		if absf((sd.n as Vector2).dot(Vector2(-sin(rot), cos(rot)))) > 0.7:
			M.team_panel(cv, sd.quad, 0.1, 0.25, 0.7, 0.8)
		M.seam(cv, sd.quad, 0.15)
	var s: Dictionary = M.hexp(cv, o, M.w(rot, -0.05, 0, 7), 0.12, 2.0, rot, M.PANEL, 623, null, 0.6)
	M.rims(cv, s, M.PANEL)
	M.hex_plate(cv, s.top, 0.5, 0.5, 2.0, M.GRAPH_D, true)
	if fnear:
		var e := M.sp(o, rot, 0.08, 0, 8)
		M.eye(cv, e, armed)
		_charge(cv, o, rot, armed, f)
	_crawl_legs(cv, o, rot, gait, true)
	cv.outline(MOUTL)
	if f == 2:  # armed: the charge face glows white-hot, standoff probe touching the target
		var fc := M.sp(o, rot, 0.27, 0, 5.5)
		cv.ellipse(fc.x, fc.y, 3.0, 2.6, Color(M.CYAN.r, M.CYAN.g, M.CYAN.b, 0.35))
		cv.px(int(fc.x), int(fc.y), Color8(255, 255, 255))
	elif f == 3:  # detonation: shaped-charge jet forward, fireball, debris
		var fc := M.sp(o, rot, 0.3, 0, 5)
		var jet := M.sp(o, rot, 0.62, 0, 6)
		cv.ellipse(fc.x, fc.y - 2, 9.0, 6.5, Color8(226, 104, 40))
		cv.ellipse(fc.x, fc.y - 3, 6.5, 4.8, Color8(255, 196, 80))
		cv.ellipse(fc.x, fc.y - 3, 3.5, 2.6, Color8(255, 246, 196))
		cv.line_v(fc, jet, Color8(255, 255, 240))
		cv.line_v(fc + Vector2(0, -1), jet + Vector2(0, -1), M.CYAN_HOT)
		L.flash(cv, jet, 1.2)
		for i in 10:
			var a := float(i) / 10.0 * TAU
			var p := fc + Vector2(cos(a) * (9.0 + P.hi(i, 1, 631, 4)), sin(a) * 5.0 - 4.0)
			cv.px(int(p.x), int(p.y), M.JOINT if i % 2 == 0 else Color8(255, 210, 120))
		L.puff(cv, fc + Vector2(-5, -9), 4.0, 0.45, Color(0.3, 0.29, 0.27))
		L.puff(cv, fc + Vector2(4, -10), 3.5, 0.4, Color(0.3, 0.29, 0.27))


## Shaped charge: a panelled cone on the nose, concave dark face with a cyan core, standoff probe.
static func _charge(cv, o: Vector2, rot: float, armed: bool, f: int) -> void:
	var cone: Dictionary = M.hexp(cv, o, M.w(rot, 0.17, 0, 2), 0.075, 7.0, rot, M.PANEL_D, 641)
	for sd in cone.sides:
		M.seam(cv, sd.quad, 0.75, false)
	var fc := M.sp(o, rot, 0.25, 0, 5.5)
	if M.w(rot, 1, 0).x + M.w(rot, 1, 0).y > -0.3:
		cv.ellipse(fc.x, fc.y, 2.4, 2.0, M.JOINT)
		cv.ellipse(fc.x, fc.y, 1.2, 1.0, M.CYAN_HOT if armed else M.CYAN)
	var probe := M.sp(o, rot, 0.4 if armed else 0.33, 0, 5)
	cv.line_v(M.sp(o, rot, 0.25, 0, 5), probe, M.JOINT)
	cv.px(int(probe.x), int(probe.y), M.PANEL if not armed else M.CYAN_HOT)


static func _crawl_legs(cv, o: Vector2, rot: float, gait: int, near: bool) -> void:
	for i in 3:
		for s: float in [-1.0, 1.0]:
			var fu := -0.11 + i * 0.11
			var foot_f := -0.2 + i * 0.2
			var fv := M.w(rot, foot_f, 0.24 * s)
			if (fv.x + fv.y > 0.0) != near:
				continue
			var ph := 0.0
			if gait == 1:
				ph = 0.05 if (i + (1 if s > 0 else 0)) % 2 == 0 else -0.05
			var hip := M.w(rot, fu, 0.08 * s, 5)
			var foot := M.w(rot, foot_f + ph, 0.24 * s, 2.0 if ph > 0.0 else 0.0)
			var od := Vector2(foot.x - hip.x, foot.y - hip.y).normalized() * 0.04
			M.leg(cv, o, hip, foot, od, 4.0, M.GRAPH_D, 2)


# ================================================================ a_exo_trooper
static func exo(cv, rot: float, f: int, wreck: bool, o: Vector2) -> void:
	if wreck:
		_exo_wreck(cv, rot, o)
		return
	var hull: Color = VH.HULL
	var dark: Color = VH.GUNMETAL
	var stride := 0.0
	var bob := 0.0
	if f == 1:
		stride = 0.06
		bob = -1.0
	elif f == 2:
		stride = -0.06
		bob = -1.0
	cv.ellipse(o.x + 2, o.y + 0.5, 9.0, 3.4, Color.BLACK, true)
	cv.flush_shadow()
	var rnear := D.faces_cam(rot, 0.0, 1.0)
	var fnear := D.faces_cam(rot, 1.0, 0.0)
	var near_s := 1.0 if rnear else -1.0
	_exo_leg(cv, o, rot, -near_s, stride, hull, dark)
	_exo_arm(cv, o, rot, -near_s, f, bob, hull, dark)
	if fnear:
		_exo_pack(cv, o, rot, bob, dark)
	_exo_leg(cv, o, rot, near_s, stride, hull, dark)
	P.box(cv, o, D.w(rot, 0.0, 0.0, 11 + bob), 0.05, 0.08, 3.0, rot, dark, 0.05, 701)  # hip block
	var t: Dictionary = P.box(cv, o, D.w(rot, 0.01, 0.0, 13 + bob), 0.065, 0.09, 8.0, rot, hull, 0.08, 703)
	D.box_edges(cv, t, hull, 704)
	var ax := Vector2(cos(rot), sin(rot))
	for sd in t.sides:
		var dn := (sd.n as Vector2).dot(ax)
		if dn > 0.5:  # chest plate + vents
			cv.poly(P.sub(sd.quad, 0.15, 0.2, 0.85, 0.75), P.mul(hull, 1.12))
			cv.line_v((sd.quad[0] as Vector2).lerp(sd.quad[1], 0.5) + Vector2(0, -2), (sd.quad[3] as Vector2).lerp(sd.quad[2], 0.5) + Vector2(0, 2), P.mul(hull, 0.8))
		elif dn < -0.5:
			cv.poly(P.sub(sd.quad, 0.2, 0.3, 0.8, 0.7), P.mul(hull, 0.85))
	if not fnear:
		_exo_pack(cv, o, rot, bob, dark)
	var hd: Dictionary = P.box(cv, o, D.w(rot, 0.015, 0.0, 21 + bob), 0.035, 0.036, 4.0, rot, P.mul(hull, 1.05), 0.05, 705)
	for sd in hd.sides:
		if (sd.n as Vector2).dot(ax) > 0.5:
			cv.poly(P.sub(sd.quad, 0.1, 0.3, 0.9, 0.65), D.VISION)
			cv.px(int((sd.quad[3] as Vector2).lerp(sd.quad[2], 0.3).x), int((sd.quad[3] as Vector2).lerp(sd.quad[2], 0.3).y) + 2, Color8(200, 230, 236))
	D.antenna(cv, D.sp(rot_o(o), rot, -0.03, -0.035 * near_s, 25 + bob), 5, false)
	_exo_arm(cv, o, rot, near_s, f, bob, hull, dark)
	cv.outline(OUTL)
	if f == 3:
		var tip := D.sp(o, rot, 0.3, 0.115, 12.5 + bob)
		L.flash(cv, tip, 1.1)
		var tip2 := D.sp(o, rot, 0.36, 0.115, 12.5 + bob)
		cv.px(int(tip2.x), int(tip2.y), Color8(255, 236, 160))
		var ej := D.sp(o, rot, 0.06, 0.16, 11 + bob)
		for i in 3:
			cv.px(int(ej.x) + i * (1 if rnear else -1), int(ej.y) + 1 + i, Color8(214, 176, 80))


static func rot_o(o: Vector2) -> Vector2:
	return o


static func _exo_leg(cv, o: Vector2, rot: float, s: float, stride: float, hull: Color, dark: Color) -> void:
	var fw := stride * s
	var lift := 1.5 if fw > 0.0 else 0.0
	P.box(cv, o, D.w(rot, fw + 0.015, 0.055 * s, lift), 0.05, 0.032, 2.0, rot, dark, 0.05, 711)  # boot
	P.box(cv, o, D.w(rot, fw, 0.055 * s, 2 + lift), 0.03, 0.028, 5.0, rot, P.mul(hull, 0.9), 0.05, 713)  # shin
	var kn := D.sp(o, rot, fw * 0.7 + 0.03, 0.055 * s, 7 + lift * 0.5)
	cv.rect(int(kn.x) - 1, int(kn.y) - 1, 2, 2, P.mul(hull, 1.15))  # knee guard
	P.box(cv, o, D.w(rot, fw * 0.5, 0.055 * s, 7), 0.036, 0.032, 5.0, rot, hull, 0.06, 715)  # thigh


static func _exo_pack(cv, o: Vector2, rot: float, bob: float, dark: Color) -> void:
	var r: Dictionary = P.box(cv, o, D.w(rot, -0.085, 0.0, 13 + bob), 0.03, 0.065, 9.0, rot, dark, 0.06, 721)
	cv.team = true
	cv.poly(P.sub(r.top, 0.1, 0.15, 0.9, 0.85), Color(0.66, 0.66, 0.66))
	cv.team = false
	for sd in r.sides:
		if (sd.n as Vector2).dot(Vector2(cos(rot), sin(rot))) < -0.5:
			for i in 3:
				var a: Vector2 = (sd.quad[0] as Vector2).lerp(sd.quad[1], 0.25 + i * 0.25)
				cv.line_v(a + Vector2(0, -2), a + Vector2(0, -6), P.mul(dark, 0.7))  # heat-sink fins


## s = +1 right arm with the rotary gun, s = -1 left arm on the fore-grip.
static func _exo_arm(cv, o: Vector2, rot: float, s: float, f: int, bob: float, hull: Color, dark: Color) -> void:
	P.box(cv, o, D.w(rot, 0.0, 0.105 * s, 12 + bob), 0.026, 0.026, 6.0, rot, dark, 0.05, 731)
	if s > 0.0:
		var g: Dictionary = P.box(cv, o, D.w(rot, 0.09, 0.115, 11 + bob), 0.085, 0.026, 3.0, rot, VH.GUNMETAL, 0.05, 733)
		D.box_edges(cv, g, VH.GUNMETAL, 734)
		var spin := f == 3
		for i in 3:
			var dz := 12.5 + bob - 1.0 + i
			var a := D.sp(o, rot, 0.17, 0.115 + (0.0 if i != 1 else 0.008), dz)
			var b := D.sp(o, rot, 0.3, 0.115 + (0.0 if i != 1 else 0.008), dz)
			cv.line_v(a, b, P.mul(Color8(70, 72, 70), 1.0 + 0.2 * i if not spin else 0.9 + 0.35 * float((i + 1) % 3)))
		var belt0 := D.sp(o, rot, -0.07, 0.07, 18 + bob)
		var belt1 := D.sp(o, rot, 0.04, 0.115, 13.5 + bob)
		cv.line_v(belt0, belt1, Color8(176, 150, 80))
	else:
		P.box(cv, o, D.w(rot, 0.07, 0.1 * s, 11 + bob), 0.05, 0.022, 2.5, rot, hull, 0.05, 735)
	var pad: Dictionary = P.box(cv, o, D.w(rot, 0.0, 0.105 * s, 18 + bob), 0.045, 0.038, 3.0, rot, hull, 0.06, 737)
	cv.team = true
	cv.poly(pad.top, Color(0.68, 0.68, 0.68))
	cv.team = false


static func _exo_wreck(cv, rot: float, o: Vector2) -> void:
	var b: Color = VH.BURNT
	cv.ellipse(o.x + 2, o.y + 1, 11.0, 3.6, Color8(40, 36, 32))
	P.box(cv, o, D.w(rot, -0.2, 0.04, 0), 0.09, 0.03, 3.0, rot, P.mul(b, 0.85), 0.06, 741)
	P.box(cv, o, D.w(rot, -0.2, -0.05, 0), 0.08, 0.03, 3.0, rot + 0.2, P.mul(b, 0.85), 0.06, 742)
	var t: Dictionary = P.box(cv, o, D.w(rot, 0.0, 0.0, 0), 0.1, 0.085, 5.0, rot, b, 0.08, 743)
	VH._scorch(cv, t)
	P.box(cv, o, D.w(rot, 0.14, 0.02, 0), 0.035, 0.035, 4.0, rot, P.mul(b, 1.1), 0.05, 744)
	P.box(cv, o, D.w(rot, 0.05, 0.16, 0), 0.1, 0.025, 3.0, rot, VH.GUNMETAL, 0.05, 745)
	cv.outline(OUTL)
	V.soot(cv, D.sp(o, rot, 0, 0, 6), 5.0, 747)


# ================================================================ x_ambush_cell
const AMB_FR := ["idle", "walk_a", "walk_b", "fire", "hidden", "ambush", "wounded"]


static func _x_styles() -> Array:
	var base := {"skin": X_SKIN, "boot": Color8(52, 44, 36), "head": "", "weapon": "rifle"}
	return [
		SQ.m(base, {"coat": X_TAN, "trouser": X_JEANS, "belt": Color8(86, 70, 50)}),
		SQ.m(base, {"coat": U.UNIFORM, "trouser": X_KHAKI, "head": "helm_b", "weapon": "rpg", "back": "rockets"}),
		SQ.m(base, {"coat": X_GREY, "trouser": U.TROUSER, "back": "pack", "belt": BI.LEATHER}),
		SQ.m(base, {"coat": X_SAND, "trouser": Color8(96, 84, 64), "head": "cap_b", "weapon": "smg"}),
	]


static func _x_posts() -> Array:
	return [
		func(m) -> void: pass,
		Callable(),
		func(m) -> void: pass,
		Callable(),
	]


## Headscarf post-processes per member (k is needed for the tail side, so bound per frame).
static func _x_scarves(k: int) -> Array:
	return [
		func(m) -> void: scarf(m, X_SKIN, SCARF_RED, false, k),
		Callable(),
		func(m) -> void: scarf(m, X_SKIN, SCARF_BLK, true, k),
		Callable(),
	]


static func ambush(cv, k: int, f: int, alive: int) -> void:
	var styles := _x_styles()
	var posts := _x_scarves(k)
	var fn: String = AMB_FR[f]
	if std_post(cv, k, fn, 4, alive, styles, posts):
		return
	# hidden / ambush: the cell lies up in brush and a ruined wall stub; ambush = everyone opens up,
	# the RPG gunner first
	var d := L.sd(k)
	var pr := SL.perp(d)
	var c := SQ.PIV
	var fire := fn == "ambush"
	var pts := SQ.take([c - pr * 8.0, c + pr * 2.0 + d * 2.0, c + pr * 12.0 - d * 1.0, c - pr * 16.0 - d * 3.0], alive)
	var poses := ["crouch_aim", "kneel_aim", "crouch_aim", "kneel_aim"] if fire else ["crouch", "kneel", "crouch", "kneel"]
	var items := []
	for i in pts.size():
		var st: Dictionary = styles[i]
		if fire:
			st = SQ.m(st, {"fire": true})
		items.append(fig_post(pts[i], k, poses[i], st, posts[i]))
		var bp: Vector2 = pts[i] + d * 3.0 + Vector2(0, 1)
		var seed := i
		var r := 5.2 if i != 1 else 4.4
		items.append(SQ.prop_at(bp.y + 0.5, func(pc) -> void:
			bush(pc, bp + Vector2(0, -3), r * 0.85, seed + 11)
			bush(pc, bp, r, seed + 3)))
	var stub := c + d * 6.0 + pr * 8.0
	items.append(SQ.prop_at(stub.y + 0.4, func(pc) -> void: _rubble(pc, stub)))
	SQ.layered(cv, items)
	if not fire:  # a few leaves stuck in the headgear / camouflage
		for i in pts.size():
			var p: Vector2 = pts[i] + Vector2(0, -10)
			cv.px(int(p.x), int(p.y), LEAF[i % 4])


static func _rubble(pc, p: Vector2) -> void:
	pc.poly(PackedVector2Array([p + Vector2(-4, 0), p + Vector2(3, 1), p + Vector2(3, -5), p + Vector2(0, -7), p + Vector2(-4, -4)]), Color8(150, 140, 120))
	pc.line_v(p + Vector2(-4, -2), p + Vector2(3, -2), Color8(118, 110, 94))
	pc.rect(int(p.x) + 4, int(p.y) - 1, 2, 1, Color8(132, 124, 106))
	pc.px(int(p.x) - 6, int(p.y), Color8(120, 112, 96))


# ================================================================ x_tunnel (building-type)
const TS := 1.4


static func _tp(o: Vector2, f: int, u: float, v: float, z: float) -> Vector2:
	return K.pt(o, f, u * TS, v * TS, z)


static func tunnel(cv, o: Vector2, f: int) -> void:
	var dirt := Color8(88, 66, 44)  # fresh-dug spoil, darker and redder than the plate dirt
	# spoil heap behind and to the side
	for i in 6:
		var p := _tp(o, f, -0.28 + 0.05 * (i % 3), 0.22 - 0.09 * (i / 3), 0)
		cv.ellipse(p.x, p.y - 1, 6.0 - i * 0.4, 3.0, P.mul(dirt, 0.92 + 0.08 * (i % 2)))
	var hp := _tp(o, f, -0.26, 0.2, 0)
	cv.ellipse(hp.x, hp.y - 2.5, 4.0, 2.0, P.mul(dirt, 1.25))
	for i in 8:  # clods and lit crumbs on the heap
		cv.px(int(hp.x) - 6 + P.hi(i, f, 97, 12), int(hp.y) - 4 + P.hi(i, f, 98, 5), P.mul(dirt, 1.45 if i % 2 == 0 else 0.7))
	# pit: dark shaft with a lit far wall and a ladder
	var u0 := -0.1
	var u1 := 0.14
	var v0 := -0.12
	var v1 := 0.12
	K.gquad(cv, o, f, TS * (u0 - 0.03), TS * (v0 - 0.03), TS * (u1 + 0.03), TS * (v1 + 0.03), 0, P.mul(dirt, 0.8))
	K.gquad(cv, o, f, TS * u0, TS * v0, TS * u1, TS * v1, 0, Color8(26, 22, 18))
	var fa := _tp(o, f, u0, v0, 0)
	var fb := _tp(o, f, u0, v1, 0)
	cv.poly(PackedVector2Array([fa, fb, fb + Vector2(0, 3), fa + Vector2(0, 3)]), Color8(70, 56, 40))
	for s: float in [-0.04, 0.04]:
		var a := _tp(o, f, u0 + 0.02, s, 0)
		cv.line_v(a, a + Vector2(1, 5), WOOD)
	# timber lean-to frame on the back edge, corrugated sheet roof sloping to the ground
	var ps := [
		[u0 - 0.02, v0 + 0.01, 0, 0.018, 0.018, 11, WOOD, "box"],
		[u0 - 0.02, v1 - 0.01, 0, 0.018, 0.018, 11, WOOD, "box"],
	]
	# sandbag horseshoe round the front and sides
	for i in 7:
		var a := -1.35 + i * (2.7 / 6.0)
		ps.append([0.02 + 0.2 * cos(a), 0.2 * sin(a), 0, 0.055, 0.045, 3.0, P.mul(BURLAP, 0.9 + 0.12 * P.hn(i, f, 91)), "box"])
	for q in ps:
		q[0] = q[0] * TS
		q[1] = q[1] * TS
		q[3] = q[3] * TS
		q[4] = q[4] * TS
	K.render(cv, o, f, ps, 1.0, false, Callable())
	var l0 := _tp(o, f, u0 - 0.02, v0 - 0.02, 11)
	var l1 := _tp(o, f, u0 - 0.02, v1 + 0.02, 11)
	var g0 := _tp(o, f, u0 - 0.24, v0 - 0.04, 0)
	var g1 := _tp(o, f, u0 - 0.24, v1 + 0.04, 0)
	var sheet := Color8(152, 150, 140)  # scavenged galvanised sheet
	cv.poly(PackedVector2Array([l0, l1, g1, g0]), sheet)
	for i in 6:
		var t := (i + 0.5) / 6.0
		cv.line_v(l0.lerp(l1, t), g0.lerp(g1, t), P.mul(sheet, 0.8 if i % 2 == 0 else 1.12))
	cv.poly(PackedVector2Array([l0.lerp(l1, 0.55), l0.lerp(l1, 0.85), g0.lerp(g1, 0.8), g0.lerp(g1, 0.5)]), Color8(146, 84, 48))  # rust patch
	cv.line_v(l0, l1, P.mul(WOOD, 1.15))  # lintel
	# camouflage netting + brush over the roof
	for i in 22:
		var t := P.hn(i, f, 93)
		var s := P.hn(i, f, 94)
		var p: Vector2 = l0.lerp(l1, t).lerp(g0.lerp(g1, t), s)
		cv.px(int(p.x), int(p.y), LEAF[P.hi(i, f, 95, 4)] if i % 3 != 0 else Color8(150, 134, 90))
	var bpc = P.Canvas.new(cv.w, cv.h)
	bush(bpc, _tp(o, f, -0.3, -0.2, 0), 4.5, 7 + f)
	bush(bpc, _tp(o, f, 0.12, -0.3, 0), 3.5, 9 + f)
	SL.stamp(cv, bpc, 0, 0)
	# fighter climbing out with an RPG, scarf; cut at the waist by the pit mouth
	var mouth := _tp(o, f, 0.02, 0.0, 0)
	var m = P.Canvas.new(24, 26)
	var kk := 1 if f == 0 else 3
	FIG.draw(m, kk, "stand", SQ.m(_x_styles()[1], {"head": "", "back": "rockets"}))
	scarf(m, X_SKIN, SCARF_TAN, true, kk)
	waist_cut(m, 16)
	SL.stamp(cv, m, int(mouth.x) - 12, int(mouth.y) - 15)
	# front lip planks over the cut
	var la := _tp(o, f, u1, v0, 0)
	var lb := _tp(o, f, u1, v1, 0)
	cv.line_v(la, lb, WOOD)
	cv.line_v(la + Vector2(0, 1), lb + Vector2(0, 1), P.mul(WOOD, 0.75))
	# team rag on a stick by the entrance
	var pole := _tp(o, f, -0.05, -0.3, 0)
	cv.line_v(pole, pole + Vector2(0, -16), WOOD)
	cv.team = true
	for x in 5:
		for y in 3:
			cv.px(int(pole.x) + 1 + x, int(pole.y) - 16 + y + (1 if x > 2 else 0), Color(0.64 + (0.1 if y == 0 else 0.0), 0.64, 0.64))
	cv.team = false
