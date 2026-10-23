extends RefCounted
## Gather (owner: agent A / sim-econ). Engineers harvest salvage/ore and deliver to HQ/depot.
## Commands: gather. Contract: docs/CONTRACTS.md section 4.
## Order shape: {type:"gather", resource_id, res, phase:"to_res"|"harvest"|"to_drop", drop_id}.
## Integer accounting: fractional progress lives in e.gather_acc, only whole units move to carry.
## G3a: the harvest rate is scaled by w.econ("gather_mult"); validation uses the `can_gather` flag
## (Machine: m_hauler gathers, m_repair_bot does not); deposits are any `deposit` building.

const Movement = preload("res://sim/systems/movement.gd")
const Construction = preload("res://sim/systems/construction.gd")

const HARVEST_REACH := 1.2     # engineer harvests while within this distance of the resource pos
const DROP_REACH := 1.2        # delivers within this distance of the deposit footprint edge
                               # (== size*0.5 + 1.2 from its centre along an axis)


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var fid := int(cmd.issuer)
	var ok_units := _gatherers(w, cmd)
	if ok_units.is_empty():
		return "Only work crews (engineers) can gather resources."
	var r = w.entities.get(int(cmd.get("target_id", -1)))
	if r == null or r.kind != "resource":
		return "That is not a resource deposit."
	if int(r.amount) <= 0:
		return "That deposit is exhausted."
	if _nearest_drop(w, fid, Vector2(r.pos)) == null:
		return "You need a built Headquarters or Logistics Depot to deliver to."
	return ""


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var r: Dictionary = w.entities[int(cmd.target_id)]
	for id in _gatherers(w, cmd):
		var e: Dictionary = w.entities[id]
		e.order = {"type": "gather", "resource_id": int(r.id), "res": String(r.res), "phase": "to_res", "drop_id": -1}
		e.gather_acc = 0.0
		e.nav_for = -1
		e.nav_wait = 0
		var carry: Dictionary = e.carry
		if int(carry.amt) > 0 and String(carry.res) != String(r.res):
			# carrying something else: deliver it first, then go to the resource
			_begin_drop(w, e)
		else:
			Construction.stop_moving(e)


static func _gatherers(w: SimWorld, cmd: Dictionary) -> Array:
	var out := []
	for raw in cmd.get("unit_ids", []):
		var e = w.entities.get(int(raw))
		if e != null and e.kind == "unit" and bool(Content.unit(e.def).get("can_gather", false)):
			out.append(int(raw))
	return out


# ================================================================ lookups
static func _nearest_drop(w: SimWorld, fid: int, pos: Vector2):
	var best = null
	var best_d := INF
	for id in w.entities:
		var b: Dictionary = w.entities[id]
		if b.kind != "building" or int(b.owner) != fid or not b.built:
			continue
		if not bool(Content.building(b.def).get("deposit", false)):
			continue
		var d := Construction.footprint_dist(pos, b.cell, int(b.size))
		if d < best_d:
			best_d = d
			best = b
	return best


## The live resource for this order, or the nearest same-type one, or null.
static func _target_resource(w: SimWorld, e: Dictionary):
	var o: Dictionary = e.order
	var r = w.entities.get(int(o.get("resource_id", -1)))
	if r != null and r.kind == "resource" and int(r.amount) > 0:
		return r
	var want := String(o.get("res", e.carry.res))
	var best = null
	var best_d := INF
	for id in w.entities:
		var c: Dictionary = w.entities[id]
		if c.kind != "resource" or c.res != want or int(c.amount) <= 0:
			continue
		var d: float = Vector2(e.pos).distance_squared_to(c.pos)
		if d < best_d:
			best_d = d
			best = c
	if best != null:
		o.resource_id = int(best.id)
		o.res = String(best.res)
	return best


## Switch to the delivery phase; idle (keeping the load) if no deposit building exists.
static func _begin_drop(w: SimWorld, e: Dictionary) -> void:
	var o: Dictionary = e.order
	var drop = _nearest_drop(w, int(e.owner), Vector2(e.pos))
	if drop == null:
		Construction.make_idle(e)
		return
	o.phase = "to_drop"
	o.drop_id = int(drop.id)
	e.nav_for = -1
	e.nav_wait = 0
	Construction.stop_moving(e)


# ================================================================ tick
static func tick(w: SimWorld) -> void:
	for id in w.entities.keys():
		var e = w.entities.get(id)
		if e == null or e.kind != "unit":
			continue
		var o: Dictionary = e.order
		if o.type != "gather":
			continue
		match String(o.get("phase", "to_res")):
			"to_res":
				_do_to_res(w, e)
			"harvest":
				_do_harvest(w, e)
			"to_drop":
				_do_to_drop(w, e)
			_:
				o.phase = "to_res"


static func _do_to_res(w: SimWorld, e: Dictionary) -> void:
	var o: Dictionary = e.order
	var r = _target_resource(w, e)
	if r == null:
		if int(e.carry.amt) > 0:
			_begin_drop(w, e)
		else:
			Construction.make_idle(e)
		return
	if Vector2(e.pos).distance_to(r.pos) <= HARVEST_REACH:
		Construction.stop_moving(e)
		o.phase = "harvest"
		return
	Construction.approach_point(w, e, int(r.id), Vector2(r.pos))


static func _do_harvest(w: SimWorld, e: Dictionary) -> void:
	var o: Dictionary = e.order
	var d := Content.unit(e.def)
	var carry: Dictionary = e.carry
	var r = _target_resource(w, e)
	if r == null:
		if int(carry.amt) > 0:
			_begin_drop(w, e)
		else:
			Construction.make_idle(e)
		return
	if Vector2(e.pos).distance_to(r.pos) > HARVEST_REACH + 0.8:
		o.phase = "to_res"       # got pushed away
		return
	if int(carry.amt) > 0 and String(carry.res) != String(r.res):
		_begin_drop(w, e)
		return
	var cap := int(d.get("carry_capacity", 10))
	var acc := float(e.get("gather_acc", 0.0)) + float(d.get("gather_rate", 1.0)) * w.econ("gather_mult") * SimWorld.DT  # G3a profile
	var take := mini(mini(int(floor(acc)), cap - int(carry.amt)), int(r.amount))
	if take > 0:
		carry.res = String(r.res)
		carry.amt = int(carry.amt) + take
		r.amount = int(r.amount) - take
		acc -= float(take)
	var depleted: bool = int(r.amount) <= 0
	if depleted:
		var rid := int(r.id)
		var rres := String(r.res)
		var rpos: Vector2 = r.pos
		w.destroy(rid, "depleted")
		w.emit("ResourceDepleted", {"id": rid, "res": rres, "pos": rpos})
	if int(carry.amt) >= cap:
		e.gather_acc = 0.0
		_begin_drop(w, e)
	else:
		e.gather_acc = acc
		if depleted:
			if int(carry.amt) > 0:
				_begin_drop(w, e)
			else:
				o.phase = "to_res"   # picks the nearest same-type deposit, or goes idle


static func _do_to_drop(w: SimWorld, e: Dictionary) -> void:
	var o: Dictionary = e.order
	var fid := int(e.owner)
	var b = w.entities.get(int(o.get("drop_id", -1)))
	if b == null or b.kind != "building" or not b.built or int(b.owner) != fid:
		b = _nearest_drop(w, fid, Vector2(e.pos))
		if b == null:
			Construction.make_idle(e)
			return
		o.drop_id = int(b.id)
		e.nav_for = -1
	if Construction.footprint_dist(e.pos, b.cell, int(b.size)) <= DROP_REACH:
		Construction.stop_moving(e)
		var carry: Dictionary = e.carry
		var amt := int(carry.amt)
		if amt > 0:
			var res := String(carry.res)
			var pay := {}
			pay[res] = amt
			w.credit(fid, pay, "delivery")
			w.emit("Delivered", {"unit_id": int(e.id), "res": res, "amt": amt})
		e.carry = {"res": "", "amt": 0}
		o.phase = "to_res"
		e.nav_for = -1
		return
	Construction.approach(w, e, b)
