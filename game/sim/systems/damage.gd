extends RefCounted
## Damage pipeline (owner: agent A2). Contract: docs/CONTRACTS_G2.md section 2.
##   apply_hit(w, shooter, target, s, hit)  called by combat._fire for EVERY shot (hit or miss).
##     hit:  damage = weapon damage x armor table x facing mult (vehicles) x cover mult (infantry),
##           quantized to 1/1024. Emits Damage. Then (if the target survives) a component roll for
##           AT/autocannon hits on vehicles and suppression for infantry.
##     miss: near-miss suppression on enemy infantry within NEAR_MISS_R of the intended target.
##   line_clear(w, from, to)  supercover grid walk; any RIDGE cell (or off-map cell) blocks.
## RNG: only w.rng, in a fixed order per hit: [component chance] -> [component pick if chance hit].
## Infantry = units that carry a `morale` field (units.json `morale`); vehicles carry `comp`.
## Combat deaths are queued in w.cache.morale_deaths (with squad) for morale.gd, which consumes
## the queue in the same tick (Morale runs right after Combat), so the cache never spans a save.
## NOTE: do not preload combat.gd here (combat preloads this file; avoid a cyclic preload).

const Q := 1.0 / 1024.0
const SimIndex = preload("res://sim/systems/sim_index.gd")  # G3b scale (PERF5): per-kind lists
const BUCKET := 2.0          # must match combat.gd BUCKET (w.cache.combat_grid layout)
const GRID_STRIDE := 1024    # must match combat.gd GRID_STRIDE
const NEAR_MISS_R := 1.5
const NEAR_MISS_NG := true   # G3b PERF4-3: near_miss reads w.cache.combat_ng (Combat then skips its GDScript grid)
const COMPONENTS := ["mobility", "weapon", "sensors"]
const FRONT_HALF := PI / 4.0          # front arc +-45 deg
const REAR_HALF := PI / 4.0           # rear arc +-45 deg around the back
const FOREST := 3                     # Terrain.FOREST (kept local: cheap, no global lookup)
const RIDGE := 7                      # Terrain.RIDGE


static func armor_of(t: Dictionary) -> String:
	if t.kind == "unit":
		return String(Content.unit(t.def).get("armor", "infantry"))
	return String(Content.building(t.def).get("armor", "building"))


## Base damage of one hit: weapon damage x armor table (s = combat stats of the shooter).
static func base_damage(s: Dictionary, t: Dictionary) -> float:
	return float(s.damage) * Content.armor_mult(String(s.cls), armor_of(t))


static func is_infantry(e: Dictionary) -> bool:
	return e.kind == "unit" and e.has("morale")


## "front" | "side" | "rear": angle between the target's facing and the target->shooter vector.
static func hit_side(from: Vector2, t: Dictionary) -> String:
	var tp: Vector2 = t.pos
	var v := from - tp
	if v.length_squared() < 1e-9:
		return "front"
	var a := absf(angle_difference(float(t.get("facing", 0.0)), v.angle()))
	if a <= FRONT_HALF + 1e-9:
		return "front"
	if a >= PI - REAR_HALF - 1e-9:
		return "rear"
	return "side"


## Infantry cover right now: forest under the unit (live), or the near-building/wreck flag that
## morale.gd refreshes every 4 ticks (e.in_cover also includes forest).
static func in_cover(w: SimWorld, e: Dictionary) -> bool:
	if bool(e.get("in_cover", false)):
		return true
	var p: Vector2 = e.pos
	return w.terrain_at(Vector2i(floori(p.x), floori(p.y))) == FOREST


## Called by combat._fire for every shot (hit or miss).
static func apply_hit(w: SimWorld, shooter: Dictionary, target: Dictionary, s: Dictionary, hit: bool) -> void:
	var R: Dictionary = Content.rules()
	var sup: Dictionary = R.get("suppression", {})
	if not hit:
		near_miss(w, int(shooter.owner), target.pos, float(sup.get("per_near_miss", 8)))
		return
	var cls := String(s.get("cls", ""))
	var dmg := base_damage(s, target)
	var side := ""
	var cover := false
	if target.kind == "unit":
		if target.has("comp"):
			side = hit_side(shooter.pos, target)
			dmg *= float((R.get("armor_facing", {}) as Dictionary).get(side, 1.0))
		elif target.has("morale"):
			cover = in_cover(w, target)
			if cover:
				dmg *= float((R.get("cover", {}) as Dictionary).get(cls, 1.0))
	dmg = snappedf(dmg, Q)
	target.hp = snappedf(float(target.hp) - dmg, Q)
	if target.kind == "unit":
		target.last_attacker = int(shooter.id)
		target.last_hit_tick = w.tick
	w.emit("Damage", {"shooter": int(shooter.id), "target": int(target.id), "amount": dmg,
		"hit_side": side, "in_cover": cover})
	if float(target.hp) <= 0.0:
		_note_death(w, target)
		w.destroy(int(target.id), "killed", int(shooter.owner))
		return
	if target.kind != "unit":
		return
	if target.has("comp") and (cls == "at" or cls == "autocannon"):
		_component_roll(w, target, dmg, R)
	if target.has("morale"):
		suppress(w, target, float(sup.get("per_hit", 18)))


## Adds suppression to one infantry unit (clamped 0..100) and marks it under fire.
static func suppress(w: SimWorld, e: Dictionary, amount: float) -> void:
	if not e.has("morale"):
		return
	var v := snappedf(clampf(float(e.get("supp", 0.0)) + amount, 0.0, 100.0), Q)
	e.supp = v
	e.supp_tick = w.tick
	var pin_at := float((Content.rules().get("suppression", {}) as Dictionary).get("pinned_at", 60))
	if v >= pin_at:
		e.pinned = true


## Near-miss suppression: infantry hostile to shooter_owner within NEAR_MISS_R of `at`.
## Uses combat's per-tick unit grid when present (always during a sim tick); falls back to a scan.
static func near_miss(w: SimWorld, shooter_owner: int, at: Vector2, amount: float) -> void:
	var r2 := NEAR_MISS_R * NEAR_MISS_R
	# G3b PERF4-3 (NEAR_MISS_NG): with the native core live, Combat skips its GDScript unit grid and
	# this reads the tick's RtsGrid instead (same FULL units). Candidates come from a slightly wider
	# native query and pass the exact GDScript distance test below, so the set equals the grid path;
	# each unit is suppressed at most once and independently, so the order does not matter.
	var ng = w.cache.get("combat_ng")
	if ng != null:
		for cid in ng.grid.query_radius(at, NEAR_MISS_R + 0.05):
			var e = w.entities.get(cid)
			if e == null or not e.has("morale") or not w.is_enemy(shooter_owner, int(e.owner)):
				continue
			var p: Vector2 = e.pos
			if p.distance_squared_to(at) <= r2:
				suppress(w, e, amount)
		return
	var grid = w.cache.get("combat_grid")
	if grid == null:
		for e in SimIndex.of(w, "unit"):
			if e.has("morale") and w.is_enemy(shooter_owner, int(e.owner)) and SimIndex.alive(w, e):
				var p: Vector2 = e.pos
				if p.distance_squared_to(at) <= r2:
					suppress(w, e, amount)
		return
	var bx := floori(at.x / BUCKET)
	var by := floori(at.y / BUCKET)
	for o in grid:
		if not w.is_enemy(shooter_owner, int(o)):
			continue
		var g: Dictionary = grid[o]
		for yy in range(by - 1, by + 2):
			for xx in range(bx - 1, bx + 2):
				var arr = g.get(xx + yy * GRID_STRIDE)
				if arr == null:
					continue
				for e in arr:
					if not e.has("morale") or not w.entities.has(int(e.id)):
						continue
					var p: Vector2 = e.pos
					if p.distance_squared_to(at) <= r2:
						suppress(w, e, amount)


static func _component_roll(w: SimWorld, t: Dictionary, dmg: float, R: Dictionary) -> void:
	if not w.rng.chance(float(R.get("component_hit_chance", 0.35))):
		return
	var comp: Dictionary = t.comp
	var cname: String = COMPONENTS[w.rng.randi_range(0, COMPONENTS.size() - 1)]
	var before := float(comp.get(cname, 100.0))
	if before <= 0.0:
		return  # already disabled: no second event until repaired
	var after := snappedf(maxf(before - dmg * float(R.get("component_damage_mult", 0.6)), 0.0), Q)
	comp[cname] = after
	if after <= 0.0:
		w.emit("ComponentDisabled", {"id": int(t.id), "owner": int(t.owner), "component": cname})


## Queue a unit death (with its squad) for morale.gd's squadmate-loss check this tick.
static func _note_death(w: SimWorld, t: Dictionary) -> void:
	if t.kind != "unit":
		return
	if not w.cache.has("morale_deaths"):
		w.cache["morale_deaths"] = []
	w.cache["morale_deaths"].append({"id": int(t.id), "owner": int(t.owner),
		"squad": int(t.get("squad", -1)), "pos": t.pos})


static func _blocks(terr: PackedByteArray, mw: int, mh: int, c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= mw or c.y >= mh:
		return true
	return terr[c.y * mw + c.x] == RIDGE


## False if the line of fire from -> to crosses a RIDGE cell. Supercover grid walk (Amanatides-Woo;
## when the segment passes exactly through a cell corner, both side cells are tested).
## Buildings do not block in G2.
static func line_clear(w: SimWorld, from: Vector2, to: Vector2) -> bool:
	var terr: PackedByteArray = w.map.terrain
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var c := Vector2i(floori(from.x), floori(from.y))
	var end := Vector2i(floori(to.x), floori(to.y))
	if _blocks(terr, mw, mh, c):
		return false
	var d := to - from
	var sx := 1 if d.x > 0.0 else -1
	var sy := 1 if d.y > 0.0 else -1
	var tdx := INF if d.x == 0.0 else absf(1.0 / d.x)
	var tdy := INF if d.y == 0.0 else absf(1.0 / d.y)
	var tmx := INF
	if d.x > 0.0:
		tmx = (float(c.x + 1) - from.x) * tdx
	elif d.x < 0.0:
		tmx = (from.x - float(c.x)) * tdx
	var tmy := INF
	if d.y > 0.0:
		tmy = (float(c.y + 1) - from.y) * tdy
	elif d.y < 0.0:
		tmy = (from.y - float(c.y)) * tdy
	var n := absi(end.x - c.x) + absi(end.y - c.y)
	while n > 0:
		if absf(tmx - tmy) < 1e-9:
			if _blocks(terr, mw, mh, c + Vector2i(sx, 0)) or _blocks(terr, mw, mh, c + Vector2i(0, sy)):
				return false
			c += Vector2i(sx, sy)
			tmx += tdx
			tmy += tdy
			n -= 2
		elif tmx < tmy:
			c.x += sx
			tmx += tdx
			n -= 1
		else:
			c.y += sy
			tmy += tdy
			n -= 1
		if _blocks(terr, mw, mh, c):
			return false
	return true
