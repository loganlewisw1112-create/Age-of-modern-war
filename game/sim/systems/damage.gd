extends RefCounted
## Damage pipeline (owner: agent A2). Contract: docs/CONTRACTS_G2.md section 2.
##   apply_hit(w, shooter, target, s, hit)  called by combat._fire for EVERY shot (hit or miss).
##     hit:  damage = weapon damage x armor table x facing mult (vehicles) x cover mult (infantry),
##           quantized to 1/1024. Emits Damage. Then (if the target survives) a component roll for
##           AT/autocannon hits on vehicles and suppression for infantry.
##     miss: near-miss suppression on enemy infantry within NEAR_MISS_R of the intended target.
##   line_clear(w, from, to)  supercover grid walk; any RIDGE, CLIFF or BUILDING terrain cell (G4,
##     Terrain.blocks_los; owner NAT) or off-map cell blocks.
## RNG: only w.rng, in a fixed order per hit: [component chance] -> [component pick if chance hit].
## Infantry = units that carry a `morale` field (units.json `morale`); vehicles carry `comp`.
## Combat deaths are queued in w.cache.morale_deaths (with squad) for morale.gd, which consumes
## the queue in the same tick (Morale runs right after Combat), so the cache never spans a save.
## G5 (CORE10K): before destroying a unit at 0 HP, apply_hit calls Medical.on_zero_hp(w, e) (via
## SimWorld.Medical, no preload cycle); true = SUPPORT keeps it alive as Wounded, apply_hit returns.
## NOTE: do not preload combat.gd here (combat preloads this file; avoid a cyclic preload).

const Q := 1.0 / 1024.0
const SimIndex = preload("res://sim/systems/sim_index.gd")  # G3b scale (PERF5): per-kind lists
## G6 PERF6 (CONTRACTS_G6 section 5.1): SimIndex.g6h().on_destroyed(w, target) runs right before a target at 0 HP is
## removed (after Medical declined to keep it as Wounded), when the DESTROY bit of SimIndex.g6m(w) is set.
const G6Hooks = preload("res://sim/systems/g6_hooks.gd")
const Roof7 = preload("res://sim/systems/roof7.gd")   # G7 ROOF7 (13.9c-39): roof mounts out of reach of ground melee / demolition
const Ballistics8 = preload("res://sim/systems/ballistics8.gd")   # G7 LETHAL8 (13.9c-47): round physics (no preloads)
const Parts71 = preload("res://sim/systems/parts71.gd")   # G7.1 DAMAGE71 B2: LP Machine parts / plates (loads damage.gd lazily: no cycle)
const BUCKET := 2.0          # must match combat.gd BUCKET (w.cache.combat_grid layout)
const GRID_STRIDE := 1024    # must match combat.gd GRID_STRIDE
const NEAR_MISS_R := 1.5
const NEAR_MISS_NG := true   # G3b PERF4-3: near_miss reads w.cache.combat_ng (Combat then skips its GDScript grid)
const COMPONENTS := ["mobility", "weapon", "sensors"]
const FRONT_HALF := PI / 4.0          # front arc +-45 deg
const REAR_HALF := PI / 4.0           # rear arc +-45 deg around the back
const FOREST := 3                     # Terrain.FOREST (kept local: cheap, no global lookup)
const RIDGE := 7                      # Terrain.RIDGE
const BUILDING_T := 8                 # Terrain.BUILDING (G4, NAT: blocks LOS)
const CLIFF := 12                     # Terrain.CLIFF (G4, NAT: blocks LOS)


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
	if int(e.get("garrisoned_in", -1)) >= 0:
		return false   # G6 (ORCH CR garrison_no_in_cover): the garrison x0.5 in G6Hooks.damage_mult replaces cover
	if bool(e.get("in_cover", false)):
		return true
	var p: Vector2 = e.pos
	if w.terrain_at(Vector2i(floori(p.x), floori(p.y))) == FOREST:
		return true
	# G7.1 C6 (Last Protocol): wrecks give cover. Positions are cached on lp.wreck_pos by LastProtocol.
	if SimWorld.LastProtocol.active(w):
		var lp = w.sys_state.get("lp")
		if lp is Dictionary:
			var r2 := float(Content.rules().get("g71_director", {}).get("wreck_cover_r", 1.6))
			r2 *= r2
			for wp in (lp.get("wreck_pos", []) as Array):
				if p.distance_squared_to(Vector2(wp)) <= r2:
					return true
	return false


## Called by combat._fire for every shot (hit or miss).
static func apply_hit(w: SimWorld, shooter: Dictionary, target: Dictionary, s: Dictionary, hit: bool) -> void:
	var R: Dictionary = Content.rules()
	var sup: Dictionary = R.get("suppression", {})
	var sf: float = SimWorld.Morale.weapon_supp(s)  # G6.1 REAL61 CR 58: weapon-scaled suppression
	if not hit:
		if SimIndex.profiling:
			var tnm := Time.get_ticks_usec()
			near_miss(w, int(shooter.owner), target.pos, float(sup.get("per_near_miss", 8)), sf)
			SimIndex.pt("dmg.near_miss", tnm)
			return
		near_miss(w, int(shooter.owner), target.pos, float(sup.get("per_near_miss", 8)), sf)
		return
	if target.kind == "building" and Roof7.shielded(shooter, s, target):
		return   # G7 ROOF7 (13.9c-39): a melee / demolition hit from the ground cannot reach a roof mount (a charge at the building's foot included)
	var cls := String(s.get("cls", ""))
	var dmg := base_damage(s, target)
	var side := ""
	var cover := false
	# G7 LETHAL8 (13.9c-47): round physics. r8 = the weapon's round (null: old path); a8 = the target's armour class.
	var zone8 := ""
	var r8 = Ballistics8.round_of(String(s.get("weapon", ""))) if target.kind == "unit" and Ballistics8.enabled() else null
	var a8: Dictionary = Ballistics8.armour_w(w, Ballistics8.armour_of(target), target) if r8 != null else {}
	r8 = Ballistics8.round_w(w, r8, shooter)   # armory / ammo-type upgrades (e.r8up / e.a8up, CARDS8B; fact api.rounds8)
	if a8.is_empty():
		r8 = null
	# G7.1 DAMAGE71 (B2, Last Protocol only): a Machine with a part layout resolves the hit on its parts / plates
	# (Parts71.hit replaces the class-armour step below). Off LP: no parts71 state, p71 stays false.
	var p71: bool = target.kind == "unit" and (target.has("p71") or (Parts71.on(w) and Parts71.adopt(w, target)))
	if target.kind == "unit":
		if p71:
			if target.has("comp"):
				side = hit_side(shooter.pos, target)
				dmg *= float((R.get("armor_facing", {}) as Dictionary).get(side, 1.0))
			dmg = Parts71.hit(w, shooter, target, r8, a8, dmg, dmg, float(s.get("damage", 0.0)) / float(r8.base) if r8 != null else 1.0)
		elif target.has("comp"):
			side = hit_side(shooter.pos, target)
			dmg *= float((R.get("armor_facing", {}) as Dictionary).get(side, 1.0))
			if r8 != null and not bool(a8.get("body", false)):
				dmg = Ballistics8.vehicle_damage(r8, a8, target, Ballistics8.tiles_between(shooter, target), side, dmg,
					float(s.get("damage", 0.0)) / float(r8.base))
		elif r8 != null and not bool(a8.get("body", false)):
			# LETHAL8B: a vehicle-class unit without components (g7_m_weaver heavy walker): the round model by facing
			dmg = Ballistics8.vehicle_damage(r8, a8, target, Ballistics8.tiles_between(shooter, target), hit_side(shooter.pos, target), dmg,
				float(s.get("damage", 0.0)) / float(r8.base))
		elif r8 != null and bool(a8.get("body", false)):
			if target.has("morale") and SimWorld.Wounds.applies(target):
				zone8 = SimWorld.Wounds.pick_zone(w, target, Vector2(shooter.pos))   # the zone decides the armour hit
			dmg = Ballistics8.body_damage(r8, a8, target, Ballistics8.tiles_between(shooter, target), zone8,
				float(s.get("damage", 0.0)) / float(r8.base))
		if target.has("morale") and not target.has("comp"):
			cover = in_cover(w, target)
			if cover:
				dmg *= float((R.get("cover", {}) as Dictionary).get(cls, 1.0))
	# G7.1 C4: hive Conductor sync — Machines locked in formation hit harder (LP only via e.lp_sync).
	if bool(shooter.get("lp_sync", false)):
		var sm := float(Content.rules().get("g71_director", {}).get("sync_damage", 1.12))
		dmg *= sm
	dmg = snappedf(dmg, Q)
	if target.kind == "building" and target.has("nres"):   # G7.1 BASTION71 G3: nanite-resistant wall coating (LP walls only; CR seq 3364)
		dmg = snappedf(dmg * SimWorld.Walls71.nres_mult(w, shooter, target), Q)
	var g71: bool = target.kind == "unit" and SimWorld.Gore71.on(w)   # G7.1 DAMAGE71 J1 (Last Protocol only): gore outcome records
	if g71:
		SimWorld.Gore71.note_hit(target, String(r8.id) if r8 != null else "", Vector2(shooter.pos))
	var zr = null   # G7 (WOUND7): hit zones for single-soldier infantry (Wounds.applies); else plain hp as before
	if target.kind == "unit" and target.has("morale") and SimWorld.Wounds.applies(target):
		var tz := Time.get_ticks_usec() if SimIndex.profiling else 0
		zr = SimWorld.Wounds.apply_hit(w, target, zone8, dmg, shooter)
		if SimIndex.profiling:
			SimIndex.pt("dmg.zone", tz)
		if g71 and String(zr.get("result", "hit")) == "hit":
			SimWorld.Gore71.limb_hit(w, target, String(zr.get("zone", "")), dmg / maxf(SimWorld.Wounds.max_hp(target), 1.0))   # G7.1 J1: severed limbs
	else:
		target.hp = snappedf(float(target.hp) - dmg, Q)
	var cev = w.cache.get("cmb_ev")   # SIM10K: Combat.tick wakes skipped shooters hit / aiming at this
	if cev != null:
		cev[int(target.id)] = true
	if target.kind == "unit":
		target.last_attacker = int(shooter.id)
		target.last_hit_tick = w.tick
		# G7.1 C4 Glass stalker: a hit strips light-bending camo (Fog.hid).
		if bool(target.get("hid", false)) and String(Content.unit(String(target.get("def", ""))).get("g71_special", "")) == "glass_stalker":
			target.erase("hid")
			w.emit("LpGlassReveal", {"id": int(target.id), "by": int(shooter.id)})
	# G5 (AIRSYS CR 2590): a cratering weapon closes airfield strips at the impact point
	var cwd: Dictionary = Content.weapon(String(s.get("weapon", ""))) if String(s.get("weapon", "")) != "" else {}
	if bool(cwd.get("cratering", false)):
		var oi := Callable(SimWorld.Airfield, "on_impact")
		if oi.is_valid():
			oi.call(w, cwd, target.pos)
	w.emit("Damage", {"shooter": int(shooter.id), "target": int(target.id), "amount": dmg,
		"hit_side": side, "in_cover": cover, "cls": cls, "weapon": String(s.get("weapon", ""))})
	if g71 and r8 != null and SimWorld.Gore71.outcome(String(r8.id)).has("line"):
		SimWorld.Gore71.rail_line(w, shooter, target, String(r8.id), dmg)   # G7.1 J1: railgun slug goes on through the line
	if zr != null and _zone_after(w, shooter, target, zr):
		return   # G7: head kill (final) or knocked unconscious
	if float(target.hp) <= 0.0:
		if p71 and Parts71.on_zero(w, shooter, target):
			return   # G7.1 DAMAGE71 J3: lives on half-dead (a heavy one that dies topples first inside on_zero)
		if target.kind == "building" and SimWorld.Turrets71.on_zero_hp(w, target):
			return   # G7.1 BASTION71 CR 971: an LP defence is disabled, not destroyed (false off LP)
		# G5 (CORE10K, CONTRACTS_G5 section 5 core.zero_hp_hook_ready): SUPPORT's Medical may keep a
		# unit alive as Wounded (true = do not destroy). The stub returns false: G4 results unchanged.
		if target.kind == "unit" and SimWorld.Medical.on_zero_hp(w, target):
			return
		if SimIndex.g6m(w) & SimIndex.G6_DESTROY:
			SimIndex.g6h().on_destroyed(w, target)  # G6: pilot eject, promotion, wreck registry
		_note_death(w, target)
		if SimIndex.profiling:
			var tde := Time.get_ticks_usec()
			w.destroy(int(target.id), "killed", int(shooter.owner))
			SimIndex.pt("dmg.death", tde)
			return
		w.destroy(int(target.id), "killed", int(shooter.owner))
		return
	if target.kind != "unit":
		return
	if target.has("comp") and (cls == "at" or cls == "autocannon") and not p71:   # G7.1: layout Machines use their parts
		_component_roll(w, target, dmg, R)
	if target.has("morale"):
		suppress(w, target, float(sup.get("per_hit", 18)), sf)


## G7 (WOUND7): after Wounds.apply_hit. true = handled here (head kill: destroyed without the Medical
## Wounded save; "down": Wounds.go_down). false = the caller continues (hp <= 0 death path, suppression).
static func _zone_after(w: SimWorld, shooter: Dictionary, target: Dictionary, zr: Dictionary) -> bool:
	var res := String(zr.get("result", "hit"))
	if res == "dead" and bool(target.get("wkill", false)):
		_kill(w, shooter, target)
		return true
	if res == "down" and float(target.hp) > 0.0:
		if SimWorld.Medical.has_medical(w, int(target.owner)):
			SimWorld.Wounds.go_down(w, target)
		else:   # ORCH G5 design rule kept: no medics / hospitals -> an unconscious soldier dies
			target.hp = 0.0
			_kill(w, shooter, target)
		return true
	return false


## The 0 hp path of apply_hit (Medical Wounded save, G6 destroy hook, morale death queue, destroy).
static func _kill(w: SimWorld, shooter: Dictionary, target: Dictionary) -> void:
	if target.has("p71") and Parts71.on_zero(w, shooter, target):
		return   # G7.1 DAMAGE71 J3: half-dead
	if target.kind == "building" and SimWorld.Turrets71.on_zero_hp(w, target):
		return   # G7.1 BASTION71 CR 971: an LP defence is disabled, not destroyed (false off LP)
	if target.kind == "unit" and not bool(target.get("wkill", false)) and SimWorld.Medical.on_zero_hp(w, target):
		return
	if SimIndex.g6m(w) & SimIndex.G6_DESTROY:
		SimIndex.g6h().on_destroyed(w, target)
	_note_death(w, target)
	w.destroy(int(target.id), "killed", int(shooter.get("owner", -1)))


## G7 (WOUND7, Shrapnel): one fragment / blast hit of `dmg` on a ground unit, LOS and cover already resolved by
## the caller. Zone soldiers take a hit-zone wound (zone_hint "" = drawn); everything else takes plain hp damage
## (x armor table for class "frag"). Same event, death path and suppression as apply_hit.
static func wound_hit(w: SimWorld, shooter: Dictionary, target: Dictionary, dmg: float, zone_hint: String = "", sf: float = 1.0) -> void:
	if not w.entities.has(int(target.id)):
		return
	var zr = null
	if target.kind == "unit" and target.has("morale") and SimWorld.Wounds.applies(target):
		dmg = snappedf(dmg, Q)
		if SimWorld.Gore71.on(w):   # G7.1 DAMAGE71 J1: splash outcome (callers set Gore71.ctx_rc; default blast)
			SimWorld.Gore71.note_hit(target, SimWorld.Gore71.ctx_rc if SimWorld.Gore71.ctx_rc != "" else "blast", Vector2(shooter.get("pos", target.pos)))
		zr = SimWorld.Wounds.apply_hit(w, target, zone_hint, dmg, shooter)
	else:
		dmg = snappedf(dmg * Content.armor_mult("frag", armor_of(target)), Q)
		target.hp = snappedf(float(target.hp) - dmg, Q)
		if target.has("p71"):
			Parts71.note_damage(w, target)   # G7.1 DAMAGE71: splash on an LP Machine; it may regrow after the lull
	var cev = w.cache.get("cmb_ev")
	if cev != null:
		cev[int(target.id)] = true
	if target.kind == "unit" and int(shooter.get("id", -1)) >= 0:
		target.last_attacker = int(shooter.id)
		target.last_hit_tick = w.tick
	w.emit("Damage", {"shooter": int(shooter.get("id", -1)), "target": int(target.id), "amount": dmg,
		"hit_side": "", "in_cover": false, "frag": true})
	if zr != null and _zone_after(w, shooter, target, zr):
		return
	if float(target.hp) <= 0.0:
		_kill(w, shooter, target)
		return
	if target.has("morale"):
		var sup: Dictionary = Content.rules().get("suppression", {})
		suppress(w, target, float(sup.get("per_hit", 18)), sf)


## Adds suppression to one infantry unit (clamped 0..100) and marks it under fire.
## G6.1 (REAL61 CR 58): Morale.add_supp scales by the weapon factor sf, cover, rank and leaders (same field
## check, clamp, supp_tick and pinning as before).
static func suppress(w: SimWorld, e: Dictionary, amount: float, sf: float = 1.0) -> void:
	SimWorld.Morale.add_supp(w, e, amount, sf)


## Near-miss suppression: infantry hostile to shooter_owner within NEAR_MISS_R of `at`.
## Uses combat's per-tick unit grid when present (always during a sim tick); falls back to a scan.
static func near_miss(w: SimWorld, shooter_owner: int, at: Vector2, amount: float, sf: float = 1.0) -> void:
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
				suppress(w, e, amount, sf)
		return
	var grid = w.cache.get("combat_grid")
	if grid == null:
		for e in SimIndex.of(w, "unit"):
			if e.has("morale") and w.is_enemy(shooter_owner, int(e.owner)) and SimIndex.alive(w, e):
				var p: Vector2 = e.pos
				if p.distance_squared_to(at) <= r2:
					suppress(w, e, amount, sf)
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
						suppress(w, e, amount, sf)


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
	if SimWorld.Gore71.on(w):
		SimWorld.Gore71.on_death(w, t, "killed")   # G7.1 DAMAGE71 J1: the body stays all match (Last Protocol)
	if not w.cache.has("morale_deaths"):
		w.cache["morale_deaths"] = []
	w.cache["morale_deaths"].append({"id": int(t.id), "owner": int(t.owner),
		"squad": int(t.get("squad", -1)), "pos": t.pos})


static func _blocks(terr: PackedByteArray, mw: int, mh: int, c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= mw or c.y >= mh:
		return true
	var t := terr[c.y * mw + c.x]
	return t == RIDGE or t == CLIFF or t == BUILDING_T  # == Terrain.blocks_los (kept local: hot path)


## False if the line of fire from -> to crosses a RIDGE / CLIFF / BUILDING terrain cell. Supercover grid walk (Amanatides-Woo;
## when the segment passes exactly through a cell corner, both side cells are tested).
## Building entities do not block (G2); BUILDING terrain decor does (G4).
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
