extends RefCounted
## G6.1 VFX61 effect engine (presentation only). Screen-space particles, ground lights, persistent decals and
## burning emitters, fed by fx_layer from sim events / the render snapshot. Cosmetic RNG only; never touches the sim.
## Quality (Low/Medium/High) scales every spawn count (Low = half of High) and the live caps.

const Core = preload("res://presentation/view/fx61_core.gd")
const Tex = preload("res://presentation/view/fx61_tex.gd")
const DecalLayer = preload("res://presentation/view/decal_layer.gd")   # G7 (LOOK7): ground mark kinds + caps
static var LOOK_OFF: bool = OS.get_cmdline_user_args().has("--g7-look-off")   # debug A/B: G6.1 fireball blasts

var q := Core.DEFAULT_QUALITY
var cap := 700
var dcap := 110
var rng := RandomNumberGenerator.new()
var parts: Array = []      # scaled particles {tx, p, v, t, life, s0, s1, c, g, r, w, gy, fo}
var fixed: Array = []      # unscaled single layers: flash cores ("glow") and shockwave rings ("ring")
var lights: Array = []     # {p, r, c, t, life}
var decals: Array = []     # {p, r, tx, fade}  fade < 0 = persistent, else seconds into its fade-out
var emitters: Dictionary = {}  # key -> {p, kind, until, acc, r, ph}
var made: Dictionary = {}  # effect name -> count started (tests / playtest)
var heat := 0.0            # recent battle intensity in view (vignette)
var night := 0.0           # G71 ART71-FX 1E: 0 day .. 1 night (FacAtmo7); boosts muzzle/blast lights + vignette
var now := 0.0
var lod := 0
var vignette_on := true
var budget := 10           # weapon effects with particles left this frame (Core.QBUDGET)


func _init() -> void:
	rng.seed = 6161
	set_quality(Core.DEFAULT_QUALITY)


func set_quality(qn) -> void:
	q = Core.norm_quality(qn)
	cap = int(Core.QCAP[q])
	dcap = int(Core.DECAL_CAP[q])
	vignette_on = q != "low"
	budget = int(Core.QBUDGET[q])


func _spend() -> bool:
	if budget <= 0:
		return false
	budget -= 1
	return true


## Spawn count for a base count: base x quality scale with stochastic rounding (expected Low = exactly half of High).
func n(base: int) -> int:
	if base <= 0:
		return 0
	var x: float = float(base) * float(Core.QSCALE[q])
	var k := floori(x)
	if rng.randf() < x - k:
		k += 1
	return k


func _made(name: String, k: int = 1) -> void:
	made[name] = int(made.get(name, 0)) + k


func wind() -> Vector2:
	return Vector2(10.0 + 4.0 * sin(now * 0.05), -2.0 + sin(now * 0.11))


## One sprite particle. fo = fade-out curve exponent; gy = ground y for bouncing (INF = none).
func part(tx: String, p: Vector2, v: Vector2, life: float, s0: float, s1: float, c: Color, g: float = 0.0,
		delay: float = 0.0, gy: float = INF, spin: float = 0.0, fo: float = 1.0) -> void:
	var fx1: bool = tx == "glow" or tx == "ring"
	if (parts.size() >= cap and not fx1) or (fx1 and fixed.size() >= 240):
		return
	(fixed if fx1 else parts).append({"tx": tx, "p": p, "v": v, "t": -delay, "life": life, "s0": s0, "s1": s1, "c": c, "g": g,
		"r": rng.randf() * TAU if spin != 0.0 else 0.0, "w": spin, "gy": gy, "fo": fo})


func light(p: Vector2, r: float, c: Color, life: float, delay: float = 0.0) -> void:
	if r <= 0.0 or lights.size() >= 64:
		return
	# Night: wider/brighter ground pools so muzzle flashes and blasts still punch through the multiply tint.
	var nr: float = r * (1.0 + night * 0.55)
	var nc: Color = c
	if night > 0.05:
		nc = Color(minf(1.0, c.r + 0.08 * night), minf(1.0, c.g + 0.05 * night), c.b, c.a)
	lights.append({"p": p, "r": nr, "c": nc, "t": -delay, "life": life})


func _rv(sx: float, sy: float) -> Vector2:
	return Vector2(rng.randf_range(-sx, sx), rng.randf_range(-sy, sy))


# ------------------------------------------------------------------ weapons
## Muzzle effects at screen point a, firing along screen direction dir; ground = screen point under the gun.
func muzzle(cls: String, a: Vector2, dir: Vector2, ground: Vector2) -> void:
	var pr: Dictionary = Core.params(cls)
	var fl: float = pr.flash
	if fl <= 0.0:
		return
	heat = minf(1.0, heat + 0.02 + fl * 0.004)
	_made("muzzle_" + cls)
	var fc := Color(0.6, 0.95, 1.0) if cls == "energy" else Color(1.0, 0.85, 0.45)
	part("glow", a, Vector2.ZERO, 0.09, fl * 3.4, fl * 2.0, Color(fc.r, fc.g, fc.b, 1.0))
	light(ground, float(pr.light), fc, 0.09)
	if lod >= 1 or not _spend():
		return
	for i in n(1):
		part("flame", a + dir * fl * 0.6, dir * 30.0, 0.08, fl * 1.8, fl * 2.6, fc, 0.0, 0.0, INF, 0.0, 2.0)
	for i in (n(1) if int(pr.casing) > 0 else 0):
		var side := Vector2(-dir.y, dir.x) * (1.0 if rng.randf() < 0.5 else -1.0)
		part("chunk", a - dir * 3.0, side * rng.randf_range(30, 55) + Vector2(0, -rng.randf_range(40, 70)), 0.6,
			2.0, 2.0, Color(0.85, 0.7, 0.3), 320.0, 0.0, ground.y + rng.randf_range(-2, 3), 18.0)
		_made("casing")
	for i in n(int(pr.bsmoke)):
		part("puff", a + dir * (4.0 + i * 3.0) + _rv(2, 2), dir * 12.0 + Vector2(0, -10) + wind() * 0.5,
			rng.randf_range(1.4, 2.4), fl * 1.2, fl * 3.4, Color(0.74, 0.73, 0.7, 0.5), 0.0, i * 0.03)
		_made("barrel_smoke")
	if bool(pr.back):
		_made("backblast")
		for i in n(4):
			part("puff", a - dir * (6.0 + i * 4.0) + _rv(3, 2), -dir * rng.randf_range(40, 80) + _rv(10, 6),
				rng.randf_range(0.6, 1.2), 6.0, 18.0, Color(0.78, 0.74, 0.66, 0.45))
		part("glow", a - dir * 8.0, -dir * 40.0, 0.1, 14.0, 22.0, Color(1.0, 0.7, 0.35, 0.8))


# ------------------------------------------------------------------ impacts
## kind: dirt | armor | water | building | soft. sc scales the effect (heavy rounds > 1).
func impact(kind: String, b: Vector2, sc: float = 1.0) -> void:
	if not _spend():
		return
	_made("impact_" + kind)
	match kind:
		"armor":
			for i in n(roundi(5 * sc)):
				var v := Vector2.from_angle(rng.randf_range(-PI, 0.0)) * rng.randf_range(60, 160)
				part("spark", b, v, rng.randf_range(0.15, 0.35), 3.0, 1.5, Color(1.0, 0.85, 0.4), 260.0)
			light(b + Vector2(0, 6), 18.0 * sc, Color(1.0, 0.8, 0.5), 0.07)
			if rng.randf() < 0.35:
				_made("ricochet")
				part("streak", b, Vector2.from_angle(rng.randf_range(-2.6, -0.5)) * 420.0, 0.18, 1.5, 1.0, Color(1.0, 0.9, 0.6))
		"water":
			for i in n(roundi(5 * sc)):
				part("puff", b + _rv(3, 1), Vector2(rng.randf_range(-20, 20), -rng.randf_range(60, 120) * sc), 0.6,
					3.0 * sc, 7.0 * sc, Color(0.88, 0.95, 1.0, 0.75), 260.0)
			part("ring", b, Vector2.ZERO, 0.5, 2.0, 12.0 * sc, Color(0.9, 0.97, 1.0, 0.7))
		"building":
			for i in n(roundi(4 * sc)):
				part("chunk", b + _rv(3, 2), Vector2(rng.randf_range(-50, 50), -rng.randf_range(40, 110)), 0.9,
					3.0, 3.0, Color(0.55, 0.52, 0.48), 300.0, 0.0, b.y + rng.randf_range(4, 10), 10.0)
			part("puff", b, Vector2(0, -12), 1.2, 6.0 * sc, 16.0 * sc, Color(0.62, 0.6, 0.56, 0.45))
		_:
			for i in n(roundi(3 * sc)):
				part("puff", b + _rv(3, 1), Vector2(rng.randf_range(-14, 14), -rng.randf_range(20, 45)), rng.randf_range(0.6, 1.1),
					5.0 * sc, 14.0 * sc, Color(0.6, 0.52, 0.4, 0.55), 40.0)
			for i in n(roundi(2 * sc)):
				part("chunk", b, Vector2(rng.randf_range(-40, 40), -rng.randf_range(50, 100)), 0.6, 2.0, 2.0,
					Color(0.4, 0.33, 0.24), 320.0, 0.0, b.y + rng.randf_range(1, 5), 12.0)


# ------------------------------------------------------------------ explosions
## Layered blast at ground point b, radius r px: flash, fireball, shockwave ring, debris, lingering smoke column,
## ground light, crater / scorch decal.
func explosion(b: Vector2, r: float, decal: String = "crater", delay: float = 0.0, energy: bool = false, fire: bool = false) -> void:
	_made("explosion")
	heat = minf(1.0, heat + 0.1 + r * 0.004)
	if not energy and not fire and decal != "" and not LOOK_OFF:
		_ground_blast(b, r, decal, delay)
		return
	var fc := Color(0.55, 0.95, 1.0) if energy else Color(1.0, 0.62, 0.22)
	part("glow", b + Vector2(0, -r * 0.3), Vector2.ZERO, 0.14, r * 2.2, r * 3.0, Color(1, 0.95, 0.8, 1.0), 0.0, delay)
	for i in n(6):
		part("flame", b + _rv(r * 0.35, r * 0.2) + Vector2(0, -r * 0.2), Vector2(rng.randf_range(-20, 20), -rng.randf_range(20, 60)),
			rng.randf_range(0.35, 0.6), r * 0.7, r * 1.3, fc, -20.0, delay + i * 0.02, INF, 0.0, 1.5)
	part("ring", b, Vector2.ZERO, 0.45, r * 0.3, r * 1.9, Color(1.0, 0.92, 0.8, 0.8), 0.0, delay)
	if lod < 2:
		for i in n(roundi(clampf(r / 4.0, 3.0, 10.0))):
			part("chunk", b + _rv(4, 2), Vector2(rng.randf_range(-1, 1) * r * 5.0, -rng.randf_range(r * 3.0, r * 7.0)),
				rng.randf_range(0.7, 1.2), 3.0, 3.0, Color(0.3, 0.27, 0.22), 340.0, delay, b.y + rng.randf_range(-r * 0.3, r * 0.4), 14.0)
	for i in n(5):
		part("puff", b + _rv(r * 0.4, r * 0.15), Vector2(0, -rng.randf_range(10, 22)) + wind() * 0.6, rng.randf_range(3.0, 5.5),
			r * 0.6, r * 2.2, Color(0.24, 0.23, 0.22, 0.5), -2.0, delay + 0.1 + i * 0.08)
	light(b, r * 4.0, fc, 0.55, delay)
	if decal != "":
		add_decal(b, r * (1.1 if decal == "crater" else 1.5), decal)


func add_decal(b: Vector2, r: float, tx: String, rot: float = 0.0) -> void:
	# G7 (LOOK7): per-kind caps (decal_layer.gd); over its cap the oldest marks of that kind fade out
	DecalLayer.add(decals, b, r, tx, q, rot)
	_made("decal_" + tx)


## G7 (LOOK7): blood under a fallen soldier (pool), on a hit (small splat) or a bleeding casualty's drip.
func blood(b: Vector2, r: float, small: bool) -> void:
	add_decal(b + _rv(2, 1), r, "blood_s" if small else "blood", rng.randf() * TAU)


## G7.1 DAMAGE71 (B2 / J3) effects, screen px like the rest of this file.
## A shallow hit glances off armour: a fan of sparks and one bright streak carrying on along dir (away from the shooter).
func ricochet71(b: Vector2, dir: Vector2) -> void:
	_made("ricochet71")
	var u := dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
	light(b + Vector2(0, 6), 16.0, Color(1.0, 0.85, 0.5), 0.08)
	if not _spend():
		return
	for i in n(6):
		part("spark", b, u.rotated(rng.randf_range(-0.7, 0.7)) * rng.randf_range(110, 250) + Vector2(0, -rng.randf_range(10, 60)),
			rng.randf_range(0.15, 0.4), 3.0, 1.2, Color(1.0, 0.88, 0.45), 260.0)
	part("streak", b, u.rotated(rng.randf_range(-0.25, 0.25)) * 460.0 + Vector2(0, -40), 0.16, 1.6, 1.0, Color(1.0, 0.92, 0.65))


## An armour plate shears off: a burst of sparks, the dark plate tumbling off along dir, a scrap mark where it lands.
func plate_shear71(b: Vector2, dir: Vector2) -> void:
	_made("plate_shear71")
	var u := dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
	light(b + Vector2(0, 6), 24.0, Color(1.0, 0.8, 0.5), 0.12)
	for i in n(9):
		part("spark", b + _rv(3, 2), Vector2.from_angle(rng.randf_range(-PI, 0.0)) * rng.randf_range(70, 190), rng.randf_range(0.2, 0.45),
			3.0, 1.4, Color(1.0, 0.85, 0.4), 260.0)
	var land := b + u * rng.randf_range(12.0, 20.0) + Vector2(0, 8)
	part("chunk", b, u * rng.randf_range(50, 80) + Vector2(0, -rng.randf_range(90, 130)), 0.95, 6.5, 6.5, Color(0.30, 0.32, 0.36),
		330.0, 0.0, land.y, 9.0)
	add_decal(land, rng.randf_range(5.0, 7.0), "debris", rng.randf() * TAU)


## A part is destroyed: sparks and a puff of smoke, then silver nanite fluid spills (silver71, with a pool).
func part_down71(b: Vector2, kind: String) -> void:
	_made("part_down71")
	for i in n(5):
		part("spark", b + _rv(3, 2), Vector2.from_angle(rng.randf_range(-PI, 0.0)) * rng.randf_range(50, 150), rng.randf_range(0.2, 0.5),
			2.6, 1.2, Color(1.0, 0.8, 0.45) if i % 2 == 0 else Color(0.75, 0.9, 1.0), 240.0)
	part("puff", b, Vector2(0, -14) + wind() * 0.5, 1.4, 4.0, 11.0, Color(0.32, 0.32, 0.34, 0.5))
	silver71(b, kind != "plate")


## Silver nanite fluid: pale glints welling up and dripping over the wound; big = also a silver pool on the ground.
func silver71(b: Vector2, big: bool) -> void:
	_made("silver71")
	for i in n(4 if big else 2):
		part("spark", b + _rv(4, 3), Vector2(rng.randf_range(-14, 14), -rng.randf_range(8, 28)), rng.randf_range(0.45, 0.9), 2.4, 1.0,
			Color(0.80, 0.86, 0.94), 90.0, i * 0.05)
	light(b, 10.0, Color(0.7, 0.85, 1.0), 0.25)
	if big:
		add_decal(b + Vector2(0, 7) + _rv(3, 1), rng.randf_range(4.0, 7.0), "silver", rng.randf() * TAU)


## G7.1 DAMAGE71 (BASTION71 CR seq 2288): n spent casings land at screen point b (px). Shots within PILE_PX of a
## live pile grow that pile (radius up to 10 px) instead of adding marks; piles share the "casings" cap
## (decal_layer.gd CASING_CAP), oldest fading first. Presentation only.
const PILE_PX := 6.0
func casings(b: Vector2, n: int) -> void:
	for d in decals:
		if float(d.fade) < 0.0 and String(d.tx) == "casings" and Vector2(d.p).distance_squared_to(b) < PILE_PX * PILE_PX:
			d.r = minf(float(d.r) + 0.35 * float(n), 10.0)
			return
	add_decal(b + _rv(2, 1), minf(3.0 + 0.35 * float(n), 10.0), "casings", rng.randf() * TAU)


## G7 (LOOK7): rubble scattered around point b (radius r px), k marks.
func debris(b: Vector2, r: float, k: int) -> void:
	for i in k:
		add_decal(b + _rv(r, r * 0.5), rng.randf_range(5.0, 9.0), "debris", rng.randf() * TAU)


## G7 (LOOK7): ground blast = a brief dull flash, then layered brown dust columns that rise, drift with the wind and
## fade slowly, debris arcs, a low lingering haze, the crater / scorch and some rubble (no bright fireball).
const DUST := [Color(0.42, 0.34, 0.24, 0.62), Color(0.35, 0.29, 0.21, 0.55), Color(0.50, 0.42, 0.31, 0.5)]
func _ground_blast(b: Vector2, r: float, decal: String, delay: float) -> void:
	_made("dust_blast")
	part("glow", b + Vector2(0, -r * 0.25), Vector2.ZERO, 0.08, r * 1.2, r * 1.8, Color(1, 0.85, 0.6, 0.8), 0.0, delay)
	for i in n(2):
		part("flame", b + _rv(r * 0.25, r * 0.1) + Vector2(0, -r * 0.15), Vector2(rng.randf_range(-10, 10), -rng.randf_range(20, 40)),
			0.18, r * 0.5, r * 0.8, Color(1.0, 0.55, 0.2), -20.0, delay + i * 0.02, INF, 0.0, 1.5)
	part("ring", b, Vector2.ZERO, 0.35, r * 0.3, r * 1.6, Color(0.75, 0.65, 0.5, 0.55), 0.0, delay)
	var wd := wind()
	# dust columns: 2-3 stacks of puffs, lower ones dense, upper ones lighter, rising then drifting
	for c in clampi(n(3), 1, 3):
		var base := b + _rv(r * 0.35, r * 0.12)
		var col: Color = DUST[c % DUST.size()]
		for k in n(4):
			var hgt := float(k) / 3.0
			part("puff", base + Vector2(0, -r * 0.3 * hgt), Vector2(rng.randf_range(-6, 6), -rng.randf_range(14, 26) * (0.6 + hgt)) + wd * (0.4 + hgt * 0.6),
				rng.randf_range(4.0, 7.0), r * (0.5 + 0.2 * hgt), r * (1.8 + 0.9 * hgt), Color(col.r, col.g, col.b, col.a * (1.0 - 0.3 * hgt)),
				-3.0, delay + 0.03 * k + 0.05 * c, INF, 0.0, 1.6)
	# debris arcs (dirt clods and stones thrown out on ballistic arcs, bouncing once)
	if lod < 2:
		for i in n(roundi(clampf(r / 3.0, 4.0, 12.0))):
			var a := rng.randf_range(-PI * 0.95, -PI * 0.05)
			var sp := rng.randf_range(r * 3.0, r * 7.5)
			part("chunk", b + _rv(3, 2), Vector2(cos(a) * sp, sin(a) * sp * 1.1), rng.randf_range(0.8, 1.4), 2.5, 2.5,
				Color(0.33, 0.27, 0.19), 360.0, delay, b.y + rng.randf_range(-r * 0.3, r * 0.4), 14.0)
	# haze: wide, low and faint; lingers longest
	for i in n(2):
		part("puff", b + _rv(r * 0.6, r * 0.2), wd * 0.5 + Vector2(0, -3), rng.randf_range(8.0, 11.0), r * 1.6, r * 3.6,
			Color(0.55, 0.49, 0.40, 0.22), 0.0, delay + 0.4)
	light(b, r * 2.2, Color(1.0, 0.7, 0.4), 0.25, delay)
	add_decal(b, r * (1.1 if decal == "crater" else 1.5), decal)


## Vehicle / building destruction: big blast, 2-3 delayed secondaries, then a burning wreck emitter (key = entity id).
func destruction(b: Vector2, big: bool, key, burn_s: float) -> void:
	_made("destruction")
	var r := 26.0 if big else 14.0
	explosion(b + Vector2(0, -6), r, "scorch", 0.0, false, true)   # cook-off keeps its fireball
	if lod < 2:
		debris(b + Vector2(0, 4), r * 1.2, 3 if big else 2)
	for i in (n(3) if big else n(1)):
		explosion(b + _rv(r * 0.6, r * 0.3) + Vector2(0, -8), r * rng.randf_range(0.4, 0.65), "", rng.randf_range(0.3, 1.4))
		_made("secondary")
	if burn_s > 0.0 and key != null:
		emitters[key] = {"p": b, "kind": "wreck", "until": now + burn_s, "acc": 0.0, "r": r * 0.5, "ph": rng.randf() * TAU}


## Smoke screen (OFF61 drill tag "smoke"): a wide, long-lived grey-white cloud over the given screen points.
func smoke_screen(pts: Array) -> void:
	_made("smoke_screen")
	for c in pts.slice(0, 6):
		for i in n(14):
			var o := _rv(80, 40)
			part("puff", (c as Vector2) + o, wind() * 0.15 + _rv(4, 2), rng.randf_range(16.0, 24.0), rng.randf_range(44, 64),
				rng.randf_range(100, 140), Color(0.88, 0.88, 0.86, Core.MAX_SMOKE_ALPHA), -0.5, i * 0.08, INF, 0.0, 0.6)


## Dust trail puff behind a moving ground vehicle (colour by terrain; water spray).
func dust(p: Vector2, col: Color, water: bool) -> void:
	if col.a <= 0.0:
		return
	_made("dust")
	if water:
		part("puff", p + _rv(3, 1), Vector2(rng.randf_range(-10, 10), -30), 0.5, 3.0, 8.0, col, 120.0)
	else:
		part("puff", p + _rv(3, 2), wind() * 0.4 + Vector2(0, -6), rng.randf_range(1.4, 2.4), 7.0, 22.0, col)


## Persistent fire (burning building / forest cell); refreshed each snapshot while it burns.
func fire(key, p: Vector2, r: float, ttl: float) -> void:
	var e = emitters.get(key)
	if e == null:
		emitters[key] = {"p": p, "kind": "fire", "until": now + ttl, "acc": 0.0, "r": r, "ph": rng.randf() * TAU}
		_made("fire")
	else:
		e.until = maxf(float(e.until), now + ttl)


# ------------------------------------------------------------------ per frame
func tick(delta: float, vr: Rect2) -> void:
	now += delta
	budget = int(Core.QBUDGET[q])
	heat = maxf(0.0, heat - delta * 0.12)
	_emit(delta, vr)
	parts = _step(parts, delta)
	fixed = _step(fixed, delta)
	var lk: Array = []
	for l in lights:
		l.t += delta
		if l.t < l.life:
			lk.append(l)
	lights = lk
	var dk: Array = []
	for d in decals:
		if float(d.fade) >= 0.0:
			d.fade = float(d.fade) + delta
			if float(d.fade) >= 2.0:
				continue
		dk.append(d)
	decals = dk


func _step(arr: Array, delta: float) -> Array:
	var keep: Array = []
	for f in arr:
		f.t += delta
		if f.t < 0.0:
			keep.append(f)
			continue
		if f.t >= f.life:
			continue
		var v: Vector2 = f.v
		v.y += float(f.g) * delta
		var p: Vector2 = (f.p as Vector2) + v * delta
		if p.y > float(f.gy) and v.y > 0.0:
			p.y = f.gy
			v = Vector2(v.x * 0.45, -v.y * 0.3)
			f.w = float(f.w) * 0.5
			if absf(v.y) < 25.0:
				v = Vector2.ZERO
				f.g = 0.0
		f.v = v
		f.p = p
		f.r = float(f.r) + float(f.w) * delta
		keep.append(f)
	return keep


## Burning emitters in view spawn flames, smoke plumes drifting with the wind and embers (rate by quality).
func _emit(delta: float, vr: Rect2) -> void:
	var dead: Array = []
	var per: float = 0.1 / float(Core.QSCALE[q])
	for key in emitters:
		var e: Dictionary = emitters[key]
		if now >= float(e.until):
			dead.append(key)
			continue
		if not vr.has_point(e.p):
			continue
		e.acc = float(e.acc) + delta
		var r: float = e.r
		var p: Vector2 = e.p
		var smoulder: bool = String(e.kind) == "wreck" and float(e.until) - now < 6.0
		while float(e.acc) >= per:
			e.acc = float(e.acc) - per
			if not smoulder:
				part("flame", p + _rv(r * 0.5, r * 0.2), Vector2(rng.randf_range(-6, 6), -rng.randf_range(18, 36)),
					rng.randf_range(0.45, 0.8), r * 1.1, r * 0.4, Color(1.0, 0.6, 0.2, 0.95), -10.0, 0.0, INF, 0.0, 1.2)
			if rng.randf() < 0.6:
				part("puff", p + Vector2(0, -r) + _rv(r * 0.4, 2), Vector2(0, -rng.randf_range(16, 28)) + wind(),
					rng.randf_range(3.0, 5.0), r * 0.7, r * 3.0, Color(0.2, 0.19, 0.18, 0.42), -1.0)
			if lod < 1 and not smoulder and rng.randf() < 0.3:
				part("spark", p + _rv(r * 0.4, 2), Vector2(rng.randf_range(-12, 12), -rng.randf_range(30, 60)) + wind() * 0.5,
					rng.randf_range(0.8, 1.4), 2.5, 1.0, Color(1.0, 0.7, 0.3), -8.0)
	for k in dead:
		emitters.erase(k)


func _alpha(f: Dictionary, k: float) -> float:
	var fin: float = minf(1.0, float(f.t) / minf(0.3, float(f.life) * 0.12))   # quick fade-in, then the fade-out curve
	return float((f.c as Color).a) * fin * pow(1.0 - k, float(f.fo))


## Normal-blend particles (smoke, flames, debris, sparks, rings) + heat haze over fires. Returns items drawn.
func draw_parts(ci: CanvasItem, vr: Rect2) -> int:
	var cnt := 0
	var t_puff := Tex.tex("puff")
	var t_flame := Tex.tex("flame")
	var t_chunk := Tex.tex("chunk")
	var t_spark := Tex.tex("spark")
	for arr in [parts, fixed]:
		for f in arr:
			if f.t < 0.0 or String(f.tx) == "glow":
				continue
			var p: Vector2 = f.p
			if not vr.has_point(p):
				continue
			var tx := String(f.tx)
			if lod >= 1 and tx == "chunk":
				continue
			if lod >= 2 and (tx == "spark" or tx == "streak" or (tx == "puff" and float(f.s1) < 14.0)):
				continue
			var k: float = float(f.t) / float(f.life)
			var s: float = lerpf(f.s0, f.s1, k)
			var c: Color = f.c
			var a := _alpha(f, k)
			match tx:
				"ring":
					ci.draw_set_transform(p, 0.0, Vector2(1.0, 0.5))
					ci.draw_arc(Vector2.ZERO, s, 0.0, TAU, 28, Color(c.r, c.g, c.b, a), 1.0 + 3.0 * (1.0 - k))
					ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				"streak":
					ci.draw_line(p, p - (f.v as Vector2) * 0.035, Color(c.r, c.g, c.b, a), float(f.s0))
				"puff":
					ci.draw_texture_rect(t_puff, Rect2(p - Vector2(s * 0.5, s * 0.4), Vector2(s, s * 0.8)), false,
						Color(c.r, c.g, c.b, minf(a, Core.MAX_SMOKE_ALPHA)))
				"flame":
					ci.draw_texture_rect(t_flame, Rect2(p - Vector2(s * 0.33, s * 0.75), Vector2(s * 0.67, s)), false, Color(c.r, c.g, c.b, a))
				"chunk":
					ci.draw_set_transform(p, float(f.r), Vector2.ONE)
					ci.draw_texture_rect(t_chunk, Rect2(Vector2(-s, -s) * 0.5, Vector2(s, s)), false, Color(c.r, c.g, c.b, a))
					ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				_:
					ci.draw_texture_rect(t_spark, Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), false, Color(c.r, c.g, c.b, a))
			cnt += 1
	if lod < 2 and q != "low":
		for key in emitters:
			var e: Dictionary = emitters[key]
			var ep: Vector2 = e.p
			if not vr.has_point(ep) or (String(e.kind) == "wreck" and float(e.until) - now < 6.0):
				continue
			var r: float = e.r
			for i in 4:
				var x := (-1.5 + i) * r * 0.5
				var u := fmod(now * 0.7 + i * 0.27 + float(e.ph), 1.0)
				var y0 := -r * 1.2 - u * r * 3.0
				var sw := sin(now * 6.0 + i * 1.7) * 2.0
				ci.draw_line(ep + Vector2(x + sw, y0), ep + Vector2(x - sw, y0 - r * 0.8), Color(1.0, 0.95, 0.85, 0.12 * (1.0 - u)), 1.5)
			cnt += 1
	return cnt


## Additive pass (drawn under the particles): flash cores ("glow" particles), ground light pools, fire flicker.
func draw_lights(ci: CanvasItem, vr: Rect2) -> int:
	var cnt := 0
	var g := Tex.tex("glow")
	var big := vr.grow(120.0)
	var lit_a := 0.55 + night * 0.22
	for l in lights:
		if l.t < 0.0 or not big.has_point(l.p):
			continue
		var k: float = float(l.t) / float(l.life)
		var r: float = l.r
		var c: Color = l.c
		ci.draw_texture_rect(g, Rect2((l.p as Vector2) - Vector2(r, r * 0.5), Vector2(r * 2.0, r)), false, Color(c.r, c.g, c.b, lit_a * (1.0 - k)))
		cnt += 1
	for key in emitters:
		var e: Dictionary = emitters[key]
		if not big.has_point(e.p):
			continue
		var sm: bool = String(e.kind) == "wreck" and float(e.until) - now < 6.0
		var r2: float = float(e.r) * (5.0 if not sm else 2.5) * (0.85 + 0.15 * sin(now * 13.0 + float(e.ph)) * sin(now * 7.3))
		var wa := (0.4 if not sm else 0.18) * (1.0 + night * 0.35)
		ci.draw_texture_rect(g, Rect2((e.p as Vector2) - Vector2(r2, r2 * 0.5), Vector2(r2 * 2.0, r2)), false, Color(1.0, 0.55, 0.2, wa))
		cnt += 1
	for f in fixed:
		if String(f.tx) != "glow" or f.t < 0.0 or not vr.has_point(f.p):
			continue
		var k2: float = float(f.t) / float(f.life)
		var s: float = lerpf(f.s0, f.s1, k2)
		var c2: Color = f.c
		ci.draw_texture_rect(g, Rect2((f.p as Vector2) - Vector2(s, s) * 0.5, Vector2(s, s)), false, Color(c2.r, c2.g, c2.b, c2.a * (1.0 - k2)))
		cnt += 1
	return cnt


## Ground decals (drawn under units and selection rings): craters and scorch marks; oldest beyond the cap fade.
func draw_decals(ci: CanvasItem, vr: Rect2) -> int:
	return DecalLayer.draw(ci, decals, vr)


## Subtle battle vignette over the view rect (fades in with recent fire in view; off on Low).
## Night leans the heat vignette a touch harder so siege fire reads against the dark frame.
func draw_vignette(ci: CanvasItem, view: Rect2) -> bool:
	if not vignette_on or heat < 0.05:
		return false
	ci.draw_texture_rect(Tex.tex("vignette"), view, false, Color(1, 1, 1, heat * (0.3 + night * 0.12)))
	return true
