extends RefCounted
## Engineer7 (owner: ENG7). G7_REFERENCE 13.9c-11 (Facility Engineer) and 13.9c-12 (facility staff run themselves).
## Content: content/g7/defs_g7_engineer.json (units g7_fac_engineer / g7_b_fac_engineer, rules.g7_engineer). Every
## number PROVISIONAL.
##  - The counter-nanite facility's own work crew (Human A / Human B), pistol only, no chain of command. A raised
##    facility starts with rules.start_count of them at its workshop; more are trained at the Sentinel Barracks and
##    join the roster by themselves (ProductionCompleted).
##  - Fully automatic through the ONE shared facility job board (Sentinels7, fact facility.job_board): every engineer
##    is a board worker (role "engineer"); the board hands the most urgent job to the nearest fit unit, never the same
##    job to two units, re-planned every few seconds (staggered). This system executes what the board handed out:
##      repair  walls, towers, facility buildings (board job) and wall turrets / other facility buildings outside
##              F.parts (external job "repair:<bid>", same id format) with the normal Repair order (salvage paid as
##              for any repair).
##      build   wall-turret construction sites the facility rebuys (WallTurret7 external job): assist_build.
##      locker  ready-ammo locker refill: walk to the special ammo magazine, load a pallet on the forklift (ammo drawn
##              from the side's stock, rules.locker.ammo_per_load per load), drive it to the locker, unload, drive
##              the empty forklift back to the magazine.
##      fuel    APCs / ground vehicles parked at the facility and landed dropships below rules.fuel.below: walk to
##              the fuel point, take the fuel bowser, drive to the vehicle, pump (fuel drawn from the side's stock),
##              drive the bowser back (external job "fuel:<uid>").
##      rest    stand by at the workshop.
##    A driving job, once the vehicle is moving with a load, is finished (vehicle parked) before the unit follows a
##    new board job. While driving: e.eng7_drv = "forklift" | "forklift_empty" | "fuel" and the event
##    Eng7Job {unit, job} (LIFE7 fact life7.engineer_hook: the display forklift / bowser attaches; job "" = ended).
##  - Player control first: any order this system did not give hands the unit to the player (board record k
##    "player"); it returns to automatic duty when that order completes (idle) or, for a plain move / attack, after
##    rules.own_timeout_s. A unit on Hold Position is never pulled back by a timeout.
## State (saved, hashed): w.sys_state.eng7 = {ver, seeded [fac ids], ids [uid], run {"uid": run}, ext {"fac":
## {job id: true}}}; entity fields e.eng7 (facility id), e.eng7_drv (while driving). Created only when a facility
## exists; no facility and no engineer: tick returns after two dictionary lookups.
## Public API (fact eng7.api): is_engineer, engineers_of, staffed, def_for, seed_facility, enlist.

const KEY := "eng7"
const VER := 1
const S7_PATH := "res://sim/systems/sentinels7.gd"
const CF_PATH := "res://sim/systems/cn_facility.gd"
const Repair = preload("res://sim/systems/repair.gd")
const Construction = preload("res://sim/systems/construction.gd")
const Movement = preload("res://sim/systems/movement.gd")
const DRIVE_PHASES := ["haul", "unload", "ret", "drive", "pump"]
const C7_PATH := "res://sim/systems/ciws7.gd"   # G7 CIWS7 (13.9c-32): roof CIWS drum swap jobs (kind "ciws7"), lazy

static var _s7 = null
## A/B switch for perf / fallout checks (tools and scratch scripts only; never saved, never set by the sim).
static var enabled := true
static var _cf = null
static var _c7 = null


## G7 CIWS7: the Ciws7 script (lazy), or null while missing.
static func C7():
	if _c7 == null and ResourceLoader.exists(C7_PATH):
		_c7 = load(C7_PATH)
	return _c7


static func S7():
	if _s7 == null:
		_s7 = load(S7_PATH)
	return _s7


static func CF():
	if _cf == null:
		_cf = load(CF_PATH)
	return _cf


static func R() -> Dictionary:
	return Content.rules().get("g7_engineer", {})


static func ticks(sec: float) -> int:
	return maxi(roundi(sec * SimWorld.TICK_RATE), 1)


static func state(w: SimWorld):
	return w.sys_state.get(KEY)


static func _st(w: SimWorld) -> Dictionary:
	var S = w.sys_state.get(KEY)
	if S == null:
		S = {"ver": VER, "seeded": [], "ids": [], "run": {}, "ext": {}}
		w.sys_state[KEY] = S
	return S


# ================================================================ public API
static func is_engineer(e) -> bool:
	return e is Dictionary and e.has("eng7")


## Facility Engineer def id of side fid ("" = that faction has none).
static func def_for(w: SimWorld, fid: int) -> String:
	if not w.factions.has(fid):
		return ""
	return String((R().get("defs", {}) as Dictionary).get(String(w.factions[fid].get("faction_def", "")), ""))


## Live engineers of facility fac (ascending ids).
static func engineers_of(w: SimWorld, fac: int) -> Array:
	var out := []
	var S = state(w)
	if S == null:
		return out
	for id in S.ids:
		var e = w.entities.get(int(id))
		if e != null and int(e.get("eng7", -1)) == fac:
			out.append(int(id))
	return out


## True when facility F has at least one live engineer on automatic duty (the pads then leave refuelling to them).
static func staffed(w: SimWorld, F: Dictionary) -> bool:
	var S = state(w)
	if S == null or F.is_empty():
		return false
	var fac := int(F.id)
	for id in S.ids:
		var e = w.entities.get(int(id))
		if e == null or int(e.get("eng7", -1)) != fac or int(e.owner) != int(F.owner):
			continue
		if String(_rec(w, int(id)).get("k", "auto")) != "player":
			return true
	return false


## Makes unit e a Facility Engineer of facility fac: a worker on its job board (no squad, no leader).
static func enlist(w: SimWorld, e: Dictionary, fac: int) -> void:
	var S := _st(w)
	e.eng7 = fac
	e.squad = -1
	e.erase("rank_role")
	var id := int(e.id)
	if not (S.ids as Array).has(id):
		S.ids.append(id)
		S.ids.sort()
	S7().add_worker(w, id, "engineer", fac)


## The starting work crew of a raised facility F (rules.start_count), at its workshop.
static func seed_facility(w: SimWorld, F: Dictionary) -> Array:
	var S := _st(w)
	var fac := int(F.id)
	if (S.seeded as Array).has(fac):
		return []
	S.seeded.append(fac)
	S.seeded.sort()
	var out := []
	var fid := int(F.owner)
	var def_id := def_for(w, fid)
	if def_id == "" or Content.unit(def_id).is_empty():
		return out
	var home := _home(F)
	var team := _team(w, fid)
	for i in int(R().get("start_count", 3)):
		var c: Vector2i = w.cell_of(home + Vector2(float(i % 3) - 1.0, float(i / 3)))
		if not Movement.is_passable(w, c, "foot", team):
			c = Movement.nearest_free_cell(w, c, "foot", team)
		var uid := w.spawn_unit(def_id, fid, Vector2(c) + Vector2(0.5, 0.5))
		var e: Dictionary = w.entities[uid]
		e.order = {"type": "idle"}
		enlist(w, e, fac)
		out.append(uid)
	w.emit("Eng7Mustered", {"fac": fac, "owner": fid, "units": out.duplicate()})
	return out


static func validate_command(_w: SimWorld, _cmd: Dictionary) -> String:
	return "Unknown engineer command."


static func apply_command(_w: SimWorld, _cmd: Dictionary) -> void:
	pass


# ================================================================ system
static func tick(w: SimWorld) -> void:
	if not enabled:
		return
	var S = w.sys_state.get(KEY)
	var cn = w.sys_state.get("cn_facility")
	if S == null and cn == null:
		return
	if cn != null:
		if w.tick % 10 == 4:
			var ks := []
			for k in cn.facs:
				ks.append(int(k))
			ks.sort()
			for k in ks:
				if S == null or not (S.seeded as Array).has(k):
					seed_facility(w, cn.facs[str(k)])
					S = state(w)
		_enlist_trained(w, cn)
		S = state(w)
	if S == null or (S.ids as Array).is_empty():
		return
	var te := int(R().get("think_every", 10))
	var keep := []
	var dirty := false
	for id in S.ids:
		var e = w.entities.get(int(id))
		if e == null or e.kind != "unit":
			dirty = true
			S.run.erase(str(id))
			continue
		keep.append(int(id))
		if (w.tick + int(id)) % te == 0:
			_think(w, S, e)
	if dirty:
		S.ids = keep
	if cn != null:
		var se := int(R().get("scan_every", 100))
		var ks2 := []
		for k in cn.facs:
			ks2.append(int(k))
		ks2.sort()
		var pe := int(S7().R().get("plan", {}).get("every", 100))
		for k in ks2:
			var F: Dictionary = cn.facs[str(k)]
			if (w.tick + k) % se == se / 2:
				if not engineers_of(w, k).is_empty():
					_post_ext(w, S, F)
			if (w.tick + k) % pe == 0 and not engineers_of(w, k).is_empty():
				_plan_unguarded(w, F)


## Sentinels7 re-plans a board only while the side has Sentinels; with every Sentinel gone the crew still works:
## plan it here on the same cadence (never twice in one tick).
static func _plan_unguarded(w: SimWorld, F: Dictionary) -> void:
	var s7 = S7()
	var SS = s7.state(w)
	if SS != null and int(SS.get("board", {}).get(str(int(F.id)), {}).get("at", -1)) == w.tick:
		return
	if not s7.sentinels_of(w, int(F.owner)).is_empty():
		return
	s7.plan(w, F)


## Engineers the barracks finished this tick join the nearest own facility's roster.
static func _enlist_trained(w: SimWorld, cn: Dictionary) -> void:
	for ev in w.events:
		if String(ev.type) != "ProductionCompleted":
			continue
		for uid in ev.get("unit_ids", []):
			var e = w.entities.get(int(uid))
			if e == null or e.has("eng7") or not bool(Content.unit(String(e.def)).get("fac_engineer", false)):
				continue
			var best := -1
			var bd := INF
			var ks := []
			for k in cn.facs:
				ks.append(int(k))
			ks.sort()
			for k in ks:
				var F: Dictionary = cn.facs[str(k)]
				if int(F.owner) != int(e.owner):
					continue
				var d := Vector2(e.pos).distance_squared_to(CF().compound_rect(F).get_center())
				if d < bd:
					bd = d
					best = k
			if best < 0:
				continue
			e.order = {"type": "idle"}   # staff: no rally walk; the board gives it its first job
			e.path = []
			e.path_i = 0
			e.moving = false
			enlist(w, e, best)


## External jobs of facility F on its board: repairs of facility buildings outside F.parts (wall turrets) and
## refuelling of own vehicles parked there / dropships landed there. Jobs no longer needed are taken down.
static func _post_ext(w: SimWorld, S: Dictionary, F: Dictionary) -> void:
	var fac := int(F.id)
	var fid := int(F.owner)
	var r := R()
	var ttl := float(r.get("ext_ttl_s", 8.0))
	var s7 = S7()
	var now := {}
	var parts := {}
	for pid in F.get("parts", []):
		parts[int(pid)] = true
	var below := float(r.get("repair", {}).get("below", 0.9))
	for b in SimWorld.SimIndex.of(w, "building"):
		# DET7: skip destroyed index entries (kept until the 1/8 rebuild; a loaded world starts clean)
		if int(b.get("cn_fac", -1)) != fac or int(b.owner) != fid or parts.has(int(b.id)) or not bool(b.get("built", true)) or not w.entities.has(int(b.id)):
			continue
		var fr := float(b.hp) / maxf(float(b.max_hp), 1.0)
		if fr >= below:
			continue
		var jid := "repair:%d" % int(b.id)
		s7.post_job(w, fac, {"id": jid, "kind": "repair", "pos": _bpos(b), "prio": 1.0 + 3.0 * (1.0 - fr),
			"roles": ["mender", "engineer"], "slots": 1, "bid": int(b.id), "ttl_s": ttl})
		now[jid] = true
	var FU: Dictionary = r.get("fuel", {})
	var fbelow := float(FU.get("below", 0.85))
	var rect: Rect2 = CF().compound_rect(F).grow(float(FU.get("zone_pad", 3.0)))
	var mine: Array = SimWorld.SimIndex.units_by_owner(w).get(fid, [])
	for u in mine:
		if not u.has("fuel") or not rect.has_point(u.pos) or not w.entities.has(int(u.id)):   # DET7: stale index entries
			continue
		var d := Content.unit(String(u.def))
		var fmax := float(d.get("fuel_max", 0.0))
		if fmax <= 0.0 or bool(d.get("energy", false)):
			continue
		var fr := float(u.fuel) / fmax
		if fr >= fbelow:
			continue
		if bool(d.get("is_air", false)):
			if not bool(u.get("air_landed", false)):
				continue
		elif bool(u.get("moving", false)):
			continue
		var jid := "fuel:%d" % int(u.id)
		s7.post_job(w, fac, {"id": jid, "kind": "fuel", "pos": Vector2(u.pos),
			"prio": (float(FU.get("prio", 2.0)) + float(FU.get("prio_empty", 2.5)) * (1.0 - fr)) * S7()._sup8p(w, int(u.owner), "aircraft" if bool(d.get("is_air", false)) else "vehicles"),
			"roles": ["engineer"], "slots": 1, "bid": int(u.id), "ttl_s": ttl})
		now[jid] = true
	var old: Dictionary = S.ext.get(str(fac), {})
	var ok := old.keys()
	ok.sort()
	for jid in ok:
		if not now.has(jid):
			s7.done_job(w, fac, String(jid))
	S.ext[str(fac)] = now


# ================================================================ thinking (staggered: (tick + id) % think_every)
## Board record of uid (copy): {k, j, fac, bid, pos} | {k: "auto" / "player"}.
static func _rec(w: SimWorld, uid: int) -> Dictionary:
	return S7().job_of(w, uid)


static func _set_rec(w: SimWorld, uid: int, rec: Dictionary) -> void:
	var s7 = S7()
	if s7.has_method("set_worker_job"):
		s7.set_worker_job(w, uid, rec)
		return
	var SS = s7.state(w)   # fallback until SENT7-2 ships set_worker_job (CR change_request.eng7.board)
	if SS != null:
		SS.jobs[str(uid)] = rec


static func _think(w: SimWorld, S: Dictionary, e: Dictionary) -> void:
	var uid := int(e.id)
	var s8 = w.sys_state.get("supply8")   # SUPPLY8 (13.9c-48): an engineer on an airdrop retrieval is run by Supply8
	if s8 != null and (s8.m as Dictionary).has(str(uid)):
		return
	var rec := _rec(w, uid)
	var k := String(rec.get("k", "auto"))
	var run: Dictionary = S.run.get(str(uid), {})
	if k == "player":   # 13.9c-12: back on automatic duty when the order is done or after own_timeout_s
		var ot := String(e.order.get("type", "idle"))
		var timed := ["move", "attack_move", "attack"].has(ot) and w.tick - int(rec.get("t", 0)) > ticks(float(R().get("own_timeout_s", 45.0)))
		if ot == "idle" or timed:
			_set_rec(w, uid, {"k": "auto", "fac": int(e.eng7)})
			w.emit("Eng7Duty", {"unit": uid, "owner": int(e.owner), "fac": int(e.eng7)})
		return
	if _player_took(e, run):
		_drive(w, e, "")
		S.run.erase(str(uid))
		_set_rec(w, uid, {"k": "player", "t": w.tick, "fac": int(e.eng7)})
		return
	if not run.is_empty() and DRIVE_PHASES.has(String(run.get("ph", ""))):
		_step(w, S, e, run)   # a vehicle in use is parked before the next job
		return
	var jid := String(rec.get("j", ""))
	if run.is_empty() or String(run.j) != jid:
		run = _start(rec)
		if run.is_empty():
			S.run.erase(str(uid))
			return
		S.run[str(uid)] = run
		w.emit("Eng7Task", {"unit": uid, "owner": int(e.owner), "kind": String(run.k), "job": jid})
	_step(w, S, e, run)


## True when the player re-tasked e (an order this system did not give).
static func _player_took(e: Dictionary, run: Dictionary) -> bool:
	var o: Dictionary = e.order
	var ty := String(o.get("type", "idle"))
	if ty == "idle":
		return false
	if run.is_empty():
		return true
	match ty:
		"repair":
			return String(run.k) != "repair" or int(o.get("target_id", -1)) != int(run.get("bid", -2))
		"build":
			return String(run.k) != "build" or int(o.get("building_id", -1)) != int(run.get("bid", -2))
		"move":
			var g = run.get("g")
			var tg = o.get("target")
			return g == null or not (tg is Vector2) or Vector2(tg).distance_to(Vector2(g)) > 0.01
	return true


static func _start(rec: Dictionary) -> Dictionary:
	var kind := String(rec.get("k", "auto"))
	if not ["repair", "build", "locker", "fuel", "rest", "ciws7"].has(kind):
		return {}
	var ph := "go"
	if kind == "locker":
		ph = "to_mag"
	elif kind == "fuel":
		ph = "to_fp"
	return {"k": kind, "j": String(rec.get("j", "")), "fac": int(rec.get("fac", -1)), "bid": int(rec.get("bid", -1)), "ph": ph, "t": 0, "n": 0}


static func _finish(w: SimWorld, S: Dictionary, e: Dictionary, run: Dictionary) -> void:
	var uid := int(e.id)
	_drive(w, e, "")
	S.run.erase(str(uid))
	if String(_rec(w, uid).get("j", "")) == String(run.j):
		_set_rec(w, uid, {"k": "auto", "fac": int(run.fac)})


static func _step(w: SimWorld, S: Dictionary, e: Dictionary, run: Dictionary) -> void:
	match String(run.k):
		"repair":
			_repair(w, S, e, run)
		"build":
			_build(w, S, e, run)
		"locker":
			_locker(w, S, e, run)
		"fuel":
			_fuel(w, S, e, run)
		"rest":
			_rest(w, e, run)
		"ciws7":
			_ciws7(w, S, e, run)


# ---------------------------------------------------------------- jobs
static func _repair(w: SimWorld, S: Dictionary, e: Dictionary, run: Dictionary) -> void:
	var bid := int(run.bid)
	var b = w.entities.get(bid)
	if b == null or b.kind != "building" or int(b.owner) != int(e.owner) or Repair.job_for(b).is_empty():
		if String(e.order.get("type", "")) == "repair":
			Construction.make_idle(e)
		_finish(w, S, e, run)
		return
	if String(e.order.get("type", "")) == "repair" and int(e.order.get("target_id", -1)) == bid:
		return   # walking there / working (Repair pays and restores)
	if w.tick < int(run.get("t", 0)):
		return   # blocked (no salvage): try again shortly
	var cmd := {"type": "repair", "issuer": int(e.owner), "unit_ids": [int(e.id)], "target_id": bid}
	if Repair.validate_command(w, cmd) != "":
		_finish(w, S, e, run)
		return
	Repair.apply_command(w, cmd)
	run.t = w.tick + ticks(float(R().get("repair", {}).get("retry_s", 6.0)))


## G7 CIWS7 (13.9c-32, owner: "an Engineer walks up to the roof and swaps the drum"): walk to the command centre stair
## door (the job position), climb (climb_s), swap the drum on the roof (swap_s: the mount shows its swap frames;
## drum_ammo_cost from the side's ammo stock, retried while short), come back down (down_s). Timings: the cn_ciws7
## def's ciws7 block. The job ends when the mount is gone or no longer dry.
static func _ciws7(w: SimWorld, S: Dictionary, e: Dictionary, run: Dictionary) -> void:
	var c7 = C7()
	var bid := int(run.bid)
	var ph := String(run.ph)
	if c7 == null or (ph != "down" and not c7.needs_swap(w, bid)):
		_finish(w, S, e, run)
		return
	var c: Dictionary = c7.cfg()
	match ph:
		"go":
			var door: Vector2 = c7.stair_door(w, bid)
			if Vector2(e.pos).distance_to(door) > 1.0:
				_go_if(w, e, run, door)
				return
			_halt(e)
			run.ph = "up"
			run.t = w.tick + ticks(float(c.get("climb_s", 10.0)))
		"up":
			if w.tick < int(run.t):
				return
			c7.begin_swap(w, bid, int(e.id))
			run.ph = "swap"
			run.t = w.tick + ticks(float(c.get("swap_s", 8.0)))
		"swap":
			if w.tick < int(run.t):
				return
			if not c7.swap_drum(w, bid, int(e.id)):
				run.t = w.tick + ticks(float(c.get("retry_s", 3.0)))
				return
			run.ph = "down"
			run.t = w.tick + ticks(float(c.get("down_s", 4.0)))
		"down":
			if w.tick >= int(run.t):
				_finish(w, S, e, run)


static func _build(w: SimWorld, S: Dictionary, e: Dictionary, run: Dictionary) -> void:
	var bid := int(run.bid)
	var b = w.entities.get(bid)
	if b == null or b.kind != "building" or int(b.owner) != int(e.owner) or bool(b.get("built", true)):
		_finish(w, S, e, run)
		return
	if String(e.order.get("type", "")) == "build" and int(e.order.get("building_id", -1)) == bid:
		return
	if w.tick < int(run.get("t", 0)):
		return
	var cmd := {"type": "assist_build", "issuer": int(e.owner), "unit_ids": [int(e.id)], "target_id": bid}
	if Construction.validate_command(w, cmd) != "":
		_finish(w, S, e, run)
		return
	Construction.apply_command(w, cmd)
	run.t = w.tick + ticks(float(R().get("build", {}).get("retry_s", 4.0)))


static func _locker(w: SimWorld, S: Dictionary, e: Dictionary, run: Dictionary) -> void:
	var L: Dictionary = R().get("locker", {})
	var F: Dictionary = CF().fac(w, int(run.fac))
	var mag = w.entities.get(int(F.get("mag", 0))) if not F.is_empty() else null
	var lid := int(run.bid)
	var stock := int(S7().locker_stock(w, lid))
	var per := int(L.get("ammo_per_load", 10))
	var fid := int(e.owner)
	var arrive := float(R().get("arrive", 1.5))
	match String(run.ph):
		"to_mag":
			if mag == null or stock < 0:
				_finish(w, S, e, run)
				return
			if _bdist(e.pos, mag) <= arrive + 0.5:
				_halt(e)
				run.ph = "load"
				run.t = w.tick + ticks(float(L.get("load_s", 4.0)))
			else:
				_go_if(w, e, run, _bpos(mag))
		"load":
			if mag == null or stock < 0:
				_finish(w, S, e, run)
				return
			if w.tick < int(run.t):
				return
			var cap := int(S7().R().get("locker", {}).get("cap", 14))
			var need := cap - stock
			if need <= 0:
				_finish(w, S, e, run)
				return
			var n := need
			if per > 0:
				n = mini(need, maxi(0, w._balance(w.factions[fid], "ammo")) / per)
				if n <= 0 or not w.spend(fid, {"ammo": n * per}, "eng7_locker"):
					if w.tick >= int(run.get("sx", 0)):
						run.sx = w.tick + ticks(float(L.get("short_event_s", 30.0)))
						w.emit("Eng7Shortage", {"unit": int(e.id), "owner": fid, "res": "ammo", "locker": lid})
					run.t = w.tick + ticks(float(L.get("load_s", 4.0)))
					return
			run.n = n
			run.ph = "haul"
			_drive(w, e, "forklift")
			_go(w, e, run, _bpos(w.entities[lid]))
		"haul":
			if stock < 0:
				run.ph = "ret"
				_drive(w, e, "forklift")
				return
			var lk: Dictionary = w.entities[lid]
			if _bdist(e.pos, lk) <= float(L.get("reach", 1.8)):
				_halt(e)
				run.ph = "unload"
				run.t = w.tick + ticks(float(L.get("unload_s", 3.0)))
			else:
				_go_if(w, e, run, _bpos(lk))
		"unload":
			if w.tick < int(run.t) and stock >= 0:
				return
			var put := 0
			if stock >= 0:
				put = int(S7().locker_add(w, lid, int(run.n)))
				w.emit("Eng7Locker", {"unit": int(e.id), "owner": fid, "locker": lid, "loads": put})
			run.n = int(run.n) - put
			run.ph = "ret"
			_drive(w, e, "forklift_empty" if int(run.n) <= 0 else "forklift")
		"ret":
			if mag == null or _bdist(e.pos, mag) <= arrive + 0.5:
				if int(run.n) > 0 and per > 0:
					w.credit(fid, {"ammo": int(run.n) * per}, "eng7_return")   # undelivered loads back into the magazine
				run.n = 0
				_halt(e)
				_finish(w, S, e, run)
			else:
				_go_if(w, e, run, _bpos(mag))


static func _fuel(w: SimWorld, S: Dictionary, e: Dictionary, run: Dictionary) -> void:
	var FU: Dictionary = R().get("fuel", {})
	var F: Dictionary = CF().fac(w, int(run.fac))
	# POLISH7-4 (owner 13.9c-21): the bowser lives in its one marked parking bay (BOWSER_BAY, out of every lane / pad /
	# APC bay / route): the engineer walks there to take it and always drives it back there to park.
	var fp := Rect2()
	if not F.is_empty():
		fp = bowser_bay(F)
	var has_fp := fp.size.x > 0.0
	var arrive := float(R().get("arrive", 1.5))
	var v = w.entities.get(int(run.bid))
	var fid := int(e.owner)
	var fmax := 0.0
	if v != null and v.kind == "unit" and v.has("fuel") and int(v.owner) == fid:
		fmax = float(Content.unit(String(v.def)).get("fuel_max", 0.0))
	var full := fmax <= 0.0 or float(v.fuel) >= fmax - 0.001
	var reach := float(FU.get("reach", 2.2))
	if v != null and String(Content.unit(String(v.def)).get("move_class", "")).begins_with("air"):
		reach = float(FU.get("reach_air", reach))   # a landed dropship: park the bowser clear of the wings / rotors, hose across
	match String(run.ph):
		"to_fp":
			if full:
				_finish(w, S, e, run)
				return
			if not has_fp:
				run.ph = "drive"
				return
			if Vector2(e.pos).distance_to(fp.get_center()) <= arrive * 0.4 or (fp.grow(0.25).has_point(e.pos) and String(e.order.get("type", "idle")) == "idle"):
				_halt(e)   # at the bowser in its bay: take it from there (the display truck attaches where it stands)
				run.ph = "drive"
				_drive(w, e, "fuel")
			else:
				_go_if(w, e, run, fp.get_center())
		"drive":
			if full:
				run.ph = "ret"
				return
			if Vector2(e.pos).distance_to(v.pos) <= reach:
				_halt(e)
				run.ph = "pump"
				w.emit("Eng7Pump", {"unit": int(e.id), "target": int(run.bid), "on": true})   # display: hose bowser -> vehicle
			elif run.get("g") == null or Vector2(run.g).distance_to(v.pos) > 1.0 or String(e.order.get("type", "idle")) == "idle":
				_go(w, e, run, Vector2(v.pos))
		"pump":
			if full:
				w.emit("Eng7Refuel", {"unit": int(e.id), "owner": fid, "target": int(run.bid), "fuel": float(v.fuel) if v != null else 0.0})
				w.emit("Eng7Pump", {"unit": int(e.id), "target": int(run.bid), "on": false})
				run.ph = "ret"
				return
			if Vector2(e.pos).distance_to(v.pos) > reach + 1.0:
				w.emit("Eng7Pump", {"unit": int(e.id), "target": int(run.bid), "on": false})
				run.ph = "drive"
				return
			var dt := float(R().get("think_every", 10)) / float(SimWorld.TICK_RATE)
			var want := mini(ceili(float(FU.get("rate_s", 30.0)) * dt), ceili(fmax - float(v.fuel)))
			var have := maxi(0, w._balance(w.factions[fid], "fuel"))
			var take := mini(want, have)
			if take <= 0 or not w.spend(fid, {"fuel": take}, "eng7_fuel"):
				if w.tick >= int(run.get("sx", 0)):
					run.sx = w.tick + ticks(float(R().get("locker", {}).get("short_event_s", 30.0)))
					w.emit("Eng7Shortage", {"unit": int(e.id), "owner": fid, "res": "fuel", "target": int(run.bid)})
				return
			v.fuel = minf(fmax, float(v.fuel) + float(take))
			if float(v.fuel) >= fmax - 0.001:   # POLISH7-4: done this think (the event lands the tick the tank is full, not
				w.emit("Eng7Refuel", {"unit": int(e.id), "owner": fid, "target": int(run.bid), "fuel": float(v.fuel)})   # one
				w.emit("Eng7Pump", {"unit": int(e.id), "target": int(run.bid), "on": false})   # think later, after the
				run.ph = "ret"   # longer bay run let a test's "both full" break land between the fill and the event)
		"ret":   # parked when on the bay centre (or as close as the path got, inside the bay)
			var db := Vector2(e.pos).distance_to(fp.get_center())
			if not has_fp or db <= BAY_ARRIVE or (fp.grow(0.25).has_point(e.pos) and String(e.order.get("type", "idle")) == "idle"):
				_halt(e)
				_finish(w, S, e, run)
			else:
				if not e.has("eng7_drv"):
					_drive(w, e, "fuel")
				_go_if(w, e, run, fp.get_center())


static func _rest(w: SimWorld, e: Dictionary, run: Dictionary) -> void:
	var F: Dictionary = CF().fac(w, int(run.fac))
	if F.is_empty():
		return
	var home := _home(F) + Vector2(float(int(e.id) % 3) - 1.0, 0.0) * 0.8
	if String(e.order.get("type", "idle")) == "idle" and Vector2(e.pos).distance_to(home) > 2.0:
		_go(w, e, run, home)


# ---------------------------------------------------------------- helpers
static func _drive(w: SimWorld, e: Dictionary, job: String) -> void:
	var cur := String(e.get("eng7_drv", ""))
	if cur == job:
		return
	if job == "":
		e.erase("eng7_drv")
	else:
		e.eng7_drv = job
	w.emit("Eng7Job", {"unit": int(e.id), "job": job})


static func _go(w: SimWorld, e: Dictionary, run: Dictionary, goal: Vector2) -> void:
	e.order = {"type": "move", "target": goal}
	run["g"] = goal
	Movement.order_path(w, e, goal)
	SimWorld.HotState.touch(w, int(e.id))


## Moves toward goal unless already on the way there.
static func _go_if(w: SimWorld, e: Dictionary, run: Dictionary, goal: Vector2) -> void:
	var g = run.get("g")
	if String(e.order.get("type", "idle")) == "move" and g != null and Vector2(g).distance_to(goal) < 0.01:
		return
	_go(w, e, run, goal)


static func _halt(e: Dictionary) -> void:
	Construction.make_idle(e)


static func _bpos(b: Dictionary) -> Vector2:
	var sz := float(b.get("size", 1))
	return Vector2(b.cell) + Vector2(sz, sz) * 0.5


static func _bdist(p: Vector2, b: Dictionary) -> float:
	var sz := float(b.get("size", 1))
	var lo := Vector2(b.cell)
	var q := Vector2(clampf(p.x, lo.x, lo.x + sz), clampf(p.y, lo.y, lo.y + sz))
	return p.distance_to(q)


## POLISH7-4 (owner 13.9c-21 "a specified parking spot within the facility it will always park at unless actively
## working") + POLISH7-5 (owner 13.9c-21a "should not be placed in front of any door, garage, etc its placement HAS to
## make sense"): the fuel bowser's one parking bay, compound-local tiles. A lay-by in the service alley between the
## workshop's south side and the barracks' back wall (FACB7-5 layout: workshop [16,9,4,4], barracks [16,14,4,2], the
## free row y13 between them), at its WEST end: the bay's mouth opens straight onto the spine lane x12..15, whose
## northbound lane runs 4 tiles straight up to the fuel point / helipad apron (x15..17); the east garages are 3 tiles
## east. Nothing opens onto it: no door / garage door / gate / pad or helipad edge / lane mouth / other bay is within a
## tile of it (the workshop doors face west at [15,10] / east at [20,10], the stair-core door east at [20,12], the
## barracks door south at [17,16]); no fac_drive7 route enters it (tests/test_life7.gd test_fuel_bay_makes_sense checks
## all of this against content/g7/defs_g7_facility.json). 9.6 x 3.6 m: the 7.5 x 2.4 m truck fits inside with room.
## Parked nose west (BOWSER_HEADING = PI, toward the mouth): it drives straight out onto the spine and reverses back
## in. (The old spot x7 y2..4 stood across the core block's east shutter and against the loading pad's west edge.)
## LIFE7 draws the bay markings (ATMO7 ground pass) and parks its display truck here.
const BOWSER_BAY := Rect2(16.0, 13.05, 2.4, 0.9)
const BOWSER_HEADING := PI
const BAY_ARRIVE := 0.35
## The bay as the layout gives it: _g7_facility "fuel_bay": [x, y, w, h, heading_deg] (compound-local; heading = the
## parked nose = the drive-out side onto its lane), else BOWSER_BAY / BOWSER_HEADING.
static func bay_local() -> Rect2:
	var b = CF().conf().get("fuel_bay")
	if b is Array and (b as Array).size() >= 4:
		return Rect2(float(b[0]), float(b[1]), float(b[2]), float(b[3]))
	return BOWSER_BAY


static func bay_heading() -> float:
	var b = CF().conf().get("fuel_bay")
	if b is Array and (b as Array).size() >= 5:
		return deg_to_rad(float(b[4]))
	return BOWSER_HEADING


static func bowser_bay(F: Dictionary) -> Rect2:
	var o: Vector2i = CF().origin(F)
	var b := bay_local()
	return Rect2(Vector2(o) + b.position, b.size)


## Stand-by point: the workshop (else the fuel point, else the compound centre).
static func _home(F: Dictionary) -> Vector2:
	var dr: Array = (CF().conf().get("doors", {}) as Dictionary).get("workshop", [])
	if not dr.is_empty():
		var o: Vector2i = CF().origin(F)
		return Vector2(o) + Vector2(float(dr[0][0]), float(dr[0][1])) + Vector2(0.5, 0.5)
	for zn in ["workshop", "fuel_point"]:
		var r: Rect2 = CF().zone(F, zn)
		if r.size.x > 0.0:
			return r.get_center()
	return CF().compound_rect(F).get_center()


static func _team(w: SimWorld, fid: int) -> int:
	var f = w.factions.get(fid)
	return int(f.get("team", fid)) if f != null else fid
