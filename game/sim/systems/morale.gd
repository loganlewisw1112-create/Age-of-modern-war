extends RefCounted
## Morale (owner: agent A2). Cover flags, suppression decay, morale, break/rally.
## Contract: docs/CONTRACTS_G2.md section 2. Runs in SYSTEM_ORDER right after Combat.
## Infantry only (units with a `morale` field: riflemen, AT, recon, engineers, officers).
## Every tick: squadmate deaths queued by damage.gd this tick (w.cache.morale_deaths; plus any
##   EntityDestroyed event that carries a `squad` field) cost per_squadmate_death morale to living
##   same-owner units of that squad within SQUAD_RADIUS of the death.
## Every UPDATE_EVERY ticks (dt = 0.2 s), per infantry unit:
##   in_cover = on FOREST, or within COVER_R of a building footprint or wreck.
##   supp decays decay_per_second once the unit has not been suppressed for UNDER_FIRE_TICKS.
##   pinned = supp >= pinned_at.
##   morale: -pinned_drain_per_second while pinned; +recover_per_second once out of combat
##   (no suppression for OUT_OF_COMBAT_TICKS); clamped to 0..units.json morale.
##   break (morale < break_at): broken, order {type:"retreat", target}, path to the nearest own
##   HQ/depot (Movement.order_path), UnitBroken. Rally (morale >= rally_at): broken=false, a retreat
##   order becomes idle, UnitRallied.

const Movement = preload("res://sim/systems/movement.gd")
const Tiers = preload("res://sim/systems/tiers.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
## G3b PERF4: loops read the shared SimIndex. REDUCED-tier units (Tiers: no enemy near) update on
## every 2nd morale update (staggered by id) with twice the dt, so recovery/decay rates are kept.
## Squadmate losses use one squad index per tick instead of one full pass per death.

const Q := 1.0 / 1024.0
const UPDATE_EVERY := 4
const UNDER_FIRE_TICKS := 20
const OUT_OF_COMBAT_TICKS := 60
const SQUAD_RADIUS := 8.0
const COVER_R := 1.0
const CB := 4.0              # cover-index bucket size (tiles)
const CB_STRIDE := 1024
const FOREST := 3            # Terrain.FOREST
const HOME_DEFS := ["hq", "depot"]

static var _mmax: Dictionary = {}   # def -> max morale (units.json `morale`)


static func max_morale(def_id: String) -> float:
	if not _mmax.has(def_id):
		_mmax[def_id] = float(Content.unit(def_id).get("morale", 100))
	return _mmax[def_id]


static func tick(w: SimWorld) -> void:
	_process_deaths(w)
	if w.tick % UPDATE_EVERY != 0:
		return
	var R: Dictionary = Content.rules()
	var sup: Dictionary = R.get("suppression", {})
	var mor: Dictionary = R.get("morale", {})
	var dt := float(UPDATE_EVERY) / float(SimWorld.TICK_RATE)
	var p := {
		"decay": float(sup.get("decay_per_second", 12)) * dt,
		"pin_at": float(sup.get("pinned_at", 60)),
		"drain": float(mor.get("pinned_drain_per_second", 3)) * dt,
		"recover": float(mor.get("recover_per_second", 4)) * dt,
		"break_at": float(mor.get("break_at", 25)),
		"rally_at": float(mor.get("rally_at", 60)),
	}
	var covers = null   # built lazily, only if some infantry is off-forest
	var mw := int(w.map.w)
	var terr: PackedByteArray = w.map.terrain
	var tiers_on := Tiers.enabled(w)
	var p2 := {}
	for k in p:
		p2[k] = p[k]
	for k in ["decay", "drain", "recover"]:
		p2[k] = float(p[k]) * 2.0
	var slot := (w.tick / UPDATE_EVERY) % 2
	for e in SimIndex.of(w, "unit"):
		if not e.has("morale") or not w.entities.has(int(e.id)):
			continue
		var pu := p
		if tiers_on and int(e.get("tier", 0)) == Tiers.REDUCED:
			if (int(e.id) + slot) % 2 != 0:
				continue
			pu = p2
		var pos: Vector2 = e.pos
		var cell := Vector2i(floori(pos.x), floori(pos.y))
		var cov := false
		if w.in_bounds(cell) and terr[cell.y * mw + cell.x] == FOREST:
			cov = true
		else:
			if covers == null:
				covers = _cover_index(w)
			cov = _near_cover(covers, pos)
		e.in_cover = cov
		# steady state (unsuppressed, full morale, not broken): nothing else can change
		if float(e.get("supp", 0.0)) <= 0.0 and not e.get("pinned", false) and not e.get("broken", false) and float(e.morale) >= max_morale(e.def):
			continue
		_update_unit(w, e, pu)


static func _update_unit(w: SimWorld, e: Dictionary, p: Dictionary) -> void:
	var since := w.tick - int(e.get("supp_tick", -100000))
	var supp := float(e.get("supp", 0.0))
	if supp > 0.0 and since >= UNDER_FIRE_TICKS:
		supp = snappedf(maxf(supp - float(p.decay), 0.0), Q)
		e.supp = supp
	var pinned := supp >= float(p.pin_at)
	e.pinned = pinned
	var m := float(e.morale)
	var mmax := max_morale(e.def)
	if pinned:
		m -= float(p.drain)
	elif since >= OUT_OF_COMBAT_TICKS:
		m += float(p.recover)
	m = snappedf(clampf(m, 0.0, mmax), Q)
	e.morale = m
	var broken := bool(e.get("broken", false))
	if not broken and m < float(p.break_at):
		_break(w, e)
	elif broken and m >= float(p.rally_at):
		_rally(w, e)


static func _break(w: SimWorld, e: Dictionary) -> void:
	e.broken = true
	e.target = -1
	var home = _home_of(w, e)
	if home == null:
		e.order = {"type": "retreat", "target": e.pos}
		Movement.stop_path(e)
	else:
		var hp: Vector2 = home
		e.order = {"type": "retreat", "target": hp}
		if not Movement.order_path(w, e, hp):
			Movement.stop_path(e)
	w.emit("UnitBroken", {"id": int(e.id), "owner": int(e.owner)})


static func _rally(w: SimWorld, e: Dictionary) -> void:
	e.broken = false
	if String(e.order.get("type", "idle")) == "retreat":
		e.order = {"type": "idle"}
		e.target = -1
		Movement.stop_path(e)
	w.emit("UnitRallied", {"id": int(e.id), "owner": int(e.owner)})


## Position of the nearest own built HQ or depot (ties -> lower id), or null.
static func _home_of(w: SimWorld, e: Dictionary):
	var pos: Vector2 = e.pos
	var best = null
	var best_d := INF
	for b in SimIndex.of(w, "building"):
		if int(b.owner) != int(e.owner) or not bool(b.get("built", false)) or not w.entities.has(int(b.id)):
			continue
		if not bool(Content.building(b.def).get("home", false)):  # G3a: flag replaces HOME_DEFS
			continue
		var bp: Vector2 = b.pos
		var d := pos.distance_squared_to(bp)
		if d < best_d:
			best_d = d
			best = bp
	return best


## Squadmate losses. Deaths come from damage.gd's queue (combat kills) and from EntityDestroyed
## events that carry a squad (if world.destroy adds it); each id counts once.
static func _process_deaths(w: SimWorld) -> void:
	var deaths: Array = []
	var seen := {}
	var q = w.cache.get("morale_deaths")
	if q != null:
		for d in q:
			if not seen.has(int(d.id)):
				seen[int(d.id)] = true
				deaths.append(d)
		w.cache.erase("morale_deaths")
	for ev in w.events:
		if ev.type == "EntityDestroyed" and ev.get("kind", "") == "unit" and ev.has("squad"):
			if not seen.has(int(ev.id)):
				seen[int(ev.id)] = true
				deaths.append({"id": int(ev.id), "owner": int(ev.owner), "squad": int(ev.squad), "pos": ev.pos})
	if deaths.is_empty():
		return
	var loss := float((Content.rules().get("morale", {}) as Dictionary).get("per_squadmate_death", 15))
	var r2 := SQUAD_RADIUS * SQUAD_RADIUS
	var want := {}   # squad -> true
	for d in deaths:
		if int(d.squad) >= 0:
			want[int(d.squad)] = true
	if want.is_empty():
		return
	var members := {}   # squad -> [living infantry of that squad], entity order
	for e in SimIndex.of(w, "unit"):
		if not e.has("morale"):
			continue
		var sq := int(e.get("squad", -1))
		if sq >= 0 and want.has(sq) and w.entities.has(int(e.id)):
			if members.has(sq):
				members[sq].append(e)
			else:
				members[sq] = [e]
	for d in deaths:
		var sq := int(d.squad)
		if sq < 0 or not members.has(sq):
			continue
		var dp: Vector2 = d.pos
		for e in members[sq]:
			if int(e.owner) != int(d.owner):
				continue
			var ep: Vector2 = e.pos
			if ep.distance_squared_to(dp) <= r2:
				e.morale = snappedf(maxf(float(e.morale) - loss, 0.0), Q)


## Buckets of cover rectangles (building footprints and wrecks), each grown by COVER_R.
## Built from current state when needed; never saved (lives only in this call).
static func _cover_index(w: SimWorld) -> Dictionary:
	var idx := {}
	var src: Array = SimIndex.of(w, "building") + SimIndex.of(w, "wreck")
	for e in src:
		if not w.entities.has(int(e.id)):
			continue
		var r: Rect2
		if e.kind == "building":
			var o: Vector2i = e.cell
			r = Rect2(Vector2(o), Vector2(float(e.size), float(e.size)))
		elif e.kind == "wreck":
			var h := float(e.get("size", 1)) * 0.5
			var wp: Vector2 = e.pos
			r = Rect2(wp - Vector2(h, h), Vector2(2.0 * h, 2.0 * h))
		else:
			continue
		var g := r.grow(COVER_R)
		for by in range(floori(g.position.y / CB), floori(g.end.y / CB) + 1):
			for bx in range(floori(g.position.x / CB), floori(g.end.x / CB) + 1):
				var k := bx + by * CB_STRIDE
				if idx.has(k):
					idx[k].append(r)
				else:
					idx[k] = [r]
	return idx


static func _near_cover(idx: Dictionary, p: Vector2) -> bool:
	var arr = idx.get(floori(p.x / CB) + floori(p.y / CB) * CB_STRIDE)
	if arr == null:
		return false
	for r in arr:
		var rr: Rect2 = r
		var q := Vector2(clampf(p.x, rr.position.x, rr.end.x), clampf(p.y, rr.position.y, rr.end.y))
		if p.distance_squared_to(q) <= COVER_R * COVER_R:
			return true
	return false
