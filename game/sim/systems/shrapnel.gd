extends RefCounted
## G7 (WOUND7): fragmentation (G7 master scope section 2). Library, no tick.
##   Shrapnel.burst(w, pos, profile, src) -> {rays, hits, blocked}
##     profile: a name in rules.g7_shrapnel.profiles ("grenade", "drone", "mortar", "shell") or a Dictionary
##       {frags, radius, dmg, blast_r, blast_dmg, supp}; src: the thrower / shooter (entity dict or id) or null.
##   Rays: n = frags x detail factor (sim detail level: FULL unit count, rules detail table; >= min_frags) evenly
##   spaced around the circle from one w.rng angle offset. A ground unit at distance d (<= radius) is hit by the
##   rays whose angle falls inside its silhouette (half-width atan(hit_r / d)); BUILDING / RIDGE / CLIFF terrain
##   between burst and unit (Damage.line_clear) blocks every ray; cover (Morale.cover_level 1 / 2) stops each ray
##   with cover_block chance (w.rng). Each connecting ray = Damage.wound_hit (a hit-zone wound on a soldier),
##   damage dmg x (1 - 0.5 d / radius). The blast core (d <= blast_r, line clear) adds one concussion hit.
##   Every infantry unit within radius x 1.2 flinches: suppression supp x (1 - 0.5 d / (1.2 radius)) (pins).
##   plain = true (standalone bursts: grenades, drone munitions) also hits non-soldier ground units; Combat's
##   artillery splash passes plain = false (its own splash already damaged them) and grid_ok = true.
## Determinism: candidates in ascending id; w.rng draws only when a candidate exists (offset first, then cover
## rolls / zones in id order).

const Damage = preload("res://sim/systems/damage.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const Tiers = preload("res://sim/systems/tiers.gd")
const Blast8 = preload("res://sim/systems/blast8.gd")   # G7 BLAST8 (13.9c-47): blast throw + concussion

const BUCKET := 2.0          # combat.gd BUCKET
const GRID_STRIDE := 1024    # combat.gd GRID_STRIDE


static func _cfg() -> Dictionary:
	return SimWorld.Wounds.shrapnel_cfg()


## Resolved profile dict (name or dict; missing keys from "grenade").
static func profile(p) -> Dictionary:
	var profs: Dictionary = _cfg().get("profiles", {})
	var out: Dictionary = (profs.get("grenade", {}) as Dictionary).duplicate()
	if typeof(p) == TYPE_STRING or typeof(p) == TYPE_STRING_NAME:
		out.merge(profs.get(String(p), {}), true)
		out["name"] = String(p)
	elif typeof(p) == TYPE_DICTIONARY:
		out.merge(p, true)
	if not out.has("frags"):
		out.merge({"frags": 48, "radius": 5.0, "dmg": 30.0, "blast_r": 1.2, "blast_dmg": 60.0, "supp": 40.0})
	return out


## Profile for an artillery weapon's splash (Combat stats dict s: damage, splash).
static func from_weapon(s: Dictionary) -> Dictionary:
	var sc: Dictionary = _cfg().get("shell_scale", {})
	var sp := maxf(float(s.get("splash", 1.0)), 0.5)
	var dmg := float(s.get("damage", 40.0))
	return {"name": "shell", "frags": mini(int(round(sp * float(sc.get("frags_per_tile", 16)))), int(sc.get("frags_max", 128))),
		"radius": sp * float(sc.get("radius_mult", 1.5)), "dmg": dmg * float(sc.get("frag_dmg_mult", 0.3)),
		"blast_r": sp * float(sc.get("blast_r_mult", 0.3)), "blast_dmg": dmg, "supp": float(sc.get("supp", 50.0))}


## Ray factor for the sim detail level: FULL units now (Tiers lists, else all units) against rules detail.
## DET7: counts LIVE units only (once per tick, cached): the index / Tiers lists keep destroyed units until their next
## rebuild while a loaded world starts clean, so a bare .size() gave a save / load copy another ray count.
static func detail(w: SimWorld) -> float:
	var n := 0
	var c = w.cache.get("shr_n")
	if c != null and int(c[0]) == w.tick:
		n = int(c[1])
	else:
		var src: Array = (Tiers.lists(w).get("full", []) as Array) if Tiers.enabled(w) else SimIndex.of(w, "unit")
		var ents: Dictionary = w.entities
		for e in src:
			if ents.has(int(e.id)):
				n += 1
		w.cache["shr_n"] = [w.tick, n]
	for row in _cfg().get("detail", [[1000000, 1.0]]):
		if n <= int(row[0]):
			return float(row[1])
	return 0.25


static func ray_count(w: SimWorld, prof: Dictionary) -> int:
	return maxi(int(round(float(prof.get("frags", 48)) * detail(w))), int(_cfg().get("min_frags", 8)))


static func _src(w: SimWorld, src, pos: Vector2) -> Dictionary:
	if typeof(src) == TYPE_DICTIONARY:
		return src
	if typeof(src) == TYPE_INT and w.entities.has(int(src)):
		return w.entities[int(src)]
	return {"id": -1, "owner": -1, "pos": pos, "kind": "none"}


## Ground units within r of at, ascending id. grid_ok: read Combat's per-tick grid (inside Combat only).
static func _near(w: SimWorld, at: Vector2, r: float, grid_ok: bool) -> Array:
	var r2 := r * r
	var ids := {}
	var ng = w.cache.get("combat_ng") if grid_ok else null
	if ng != null:
		for cid in ng.grid.query_radius(at, r + 0.05):
			var c = w.entities.get(cid)
			if c != null and c.kind == "unit" and Vector2(c.pos).distance_squared_to(at) <= r2:
				ids[int(cid)] = true
	elif grid_ok and w.cache.has("combat_grid"):
		var grid: Dictionary = w.cache.combat_grid
		for o in grid:
			var g: Dictionary = grid[o]
			for yy in range(floori((at.y - r) / BUCKET), floori((at.y + r) / BUCKET) + 1):
				for xx in range(floori((at.x - r) / BUCKET), floori((at.x + r) / BUCKET) + 1):
					var arr = g.get(xx + yy * GRID_STRIDE)
					if arr == null:
						continue
					for c in arr:
						if Vector2(c.pos).distance_squared_to(at) <= r2:
							ids[int(c.id)] = true
	else:
		for c in SimIndex.of(w, "unit"):
			if w.entities.has(int(c.id)) and Vector2(c.pos).distance_squared_to(at) <= r2:
				ids[int(c.id)] = true
	var out := ids.keys()
	out.sort()
	return out


## Airborne = an air def (is_air, an air* move class, aircraft, launched drone) not parked on the ground
## (e.air_landed, as Combat._landed). Fragments from a ground burst never hit it (DRONE7: a strike drone was
## killed by its own munition's fragments).
static func _air(c: Dictionary) -> bool:
	if c.has("air_landed") and bool(c.air_landed):
		return false
	# PERF7J (perf, exact): the def part is content-static: cached per def, dropped whenever Content's units table
	# is another object (a reload / test swap), so the answer is always the current table's.
	var ut = Content.table("units")
	if not is_same(ut, _air_ref):
		_air_ref = ut
		_air_def.clear()
	var dn := String(c.def)
	var v = _air_def.get(dn)
	if v == null:
		var d := Content.unit(dn)
		v = bool(d.get("is_air", false)) or String(d.get("move_class", "")).begins_with("air") 			or d.has("aircraft") or bool(d.get("launched_drone", false))
		_air_def[dn] = v
	return bool(v)


static var _air_ref = null
static var _air_def := {}


static func burst(w: SimWorld, pos: Vector2, prof_in, src = null, plain: bool = true, grid_ok: bool = false) -> Dictionary:
	var out := {"rays": 0, "hits": 0, "blocked": 0}
	var prof := profile(prof_in)
	var radius := maxf(float(prof.radius), 0.1)
	var br := float(prof.blast_r)
	var fr := radius * 1.2
	var cands := _near(w, pos, maxf(fr, br), grid_ok)
	if cands.is_empty():
		return out
	var s := _src(w, src, pos)
	var n := ray_count(w, prof)
	out.rays = n
	var step := TAU / float(n)
	var base := w.rng.randf() * step
	var hit_r := float(_cfg().get("hit_r", 0.35))
	var cb: Dictionary = _cfg().get("cover_block", {})
	var supp := float(prof.get("supp", 40.0))
	var b8pre := Blast8.pre(w, pos, prof, cands)   # G7 BLAST8: men in throw reach before the fragments (bodies thrown too)
	var gnd: Array = []   # G7 BLAST8: ground units this burst reached (ascending id) for the blast throw / concussion
	for id in cands:
		var c = w.entities.get(id)
		if c == null or _air(c):
			continue
		gnd.append(id)
		var cp: Vector2 = c.pos
		var d := cp.distance_to(pos)
		if c.has("morale") and not bool(c.get("wounded", false)):
			SimWorld.Morale.add_supp(w, c, supp * (1.0 - 0.5 * d / fr), 1.0)
		var zone_unit: bool = SimWorld.Wounds.applies(c)
		if not zone_unit and not plain:
			continue
		if d > 0.05 and not Damage.line_clear(w, pos, cp):
			out.blocked += 1
			continue
		if d <= br:
			Damage.wound_hit(w, s, c, float(prof.blast_dmg) * (1.0 - 0.5 * d / maxf(br, 0.01)), "")
			out.hits += 1
			if not w.entities.has(int(id)):
				continue
			SimWorld.Wounds.vis_kd(w, c)   # LOOK7 display: blast knock-down pose (g7v.kd)
		if d > radius:
			continue
		var cnt := n   # point blank: every ray
		if d > hit_r:
			var half := atan(hit_r / d)
			var a := (cp - pos).angle()
			cnt = maxi(floori((a + half - base) / step) - ceili((a - half - base) / step) + 1, 0)
		if not zone_unit:
			if cnt > 0:   # plain units: all connecting fragments as one hit
				Damage.wound_hit(w, s, c, float(prof.dmg) * float(cnt) * (1.0 - 0.5 * d / radius), "")
				out.hits += 1
			continue
		var cl: int = SimWorld.Morale.cover_level(w, c)
		var pb := float(cb.get(str(cl), 0.0)) if cl > 0 else 0.0
		for _k in cnt:
			if not w.entities.has(int(id)):
				break
			if pb > 0.0 and w.rng.chance(pb):
				out.blocked += 1
				continue
			Damage.wound_hit(w, s, c, float(prof.dmg) * (1.0 - 0.5 * d / radius), "")
			out.hits += 1
	Blast8.on_burst(w, pos, prof, gnd, s, b8pre)   # G7 BLAST8 (13.9c-47): throw / knock out the survivors near the blast
	w.emit("ShrapnelBurst", {"pos": pos, "profile": String(prof.get("name", "")), "rays": n,
		"hits": int(out.hits), "blocked": int(out.blocked), "src": int(s.get("id", -1))})
	return out
