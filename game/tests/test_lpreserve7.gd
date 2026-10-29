extends "res://tests/test_base.gd"
## G7 acceptance (owner: LPRES7). G7_REFERENCE 13.9c-34 (Last Protocol: the 100-Sentinel barracks reserve, released in
## tiers: post refills -> QRF squads -> breach surge, ~20% last stand for the core; auto + manual; slow paid trickle).
## LP worlds run on industrial_heartland_m like test_lpmode7 (the facility is the same pre-built compound).

const S7 = preload("res://sim/systems/sentinels7.gd")
const LR = preload("res://sim/systems/lp_reserve7.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const Garrison = preload("res://sim/systems/garrison.gd")
const Movement = preload("res://sim/systems/movement.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const MAP := "industrial_heartland_m"

static var _base_dict: Dictionary = {}


func _ensure_g7() -> void:
	if Content.unit("g7_sent_warden").is_empty() or Content.building("a_cn_facility").is_empty():
		Content._merge_fragment_dir("res://content/g7")
		Content._link_fragment_production()


## A Last Protocol world after setup + facility fill (cached; deep copy per test), Machine AI off.
func _lp() -> SimWorld:
	if _base_dict.is_empty():
		var w0 := SimWorld.new_match(LastProtocol.make_config(4242, MAP))
		check(w0 != null, "Last Protocol config is a valid match")
		if w0 == null:
			return null
		w0.run_ticks(25)
		_base_dict = w0.to_dict().duplicate(true)
	var w := SimWorld.from_dict(_base_dict.duplicate(true))
	w.ai_state = {}
	return w


func _fid(w: SimWorld) -> int:
	return int(w.sys_state.lp.fid)


func _mfid(w: SimWorld) -> int:
	return int(w.sys_state.lp.mfid)


func _fac(w: SimWorld) -> Dictionary:
	var l := LR.reserves_of(w, _fid(w))
	return CnFacility.fac(w, int(l[0])) if not l.is_empty() else {}


func _rr(w: SimWorld) -> Dictionary:
	var F := _fac(w)
	return LR.rec(w, int(F.id)) if not F.is_empty() else {}


## Enemy (Machine side) soldiers at compound-local (x, y) + i rows, held in place and hard to kill (pressure stays up).
func _enemies(w: SimWorld, F: Dictionary, lx: float, ly: float, n: int, tough: bool = true) -> Array:
	var out := []
	var o := Vector2(CnFacility.origin(F))
	for i in n:
		var c: Vector2i = Movement.nearest_free_cell(w, w.cell_of(o + Vector2(lx + float(i % 4), ly + float(i / 4))), "foot", _mfid(w))
		var uid := w.spawn_unit("rifleman", _mfid(w), Vector2(c) + Vector2(0.5, 0.5))
		w.entities[uid].order = {"type": "hold"}
		if tough:   # test fixture: no hit-zone wound model (Wounds.applies needs morale) and a deep hp pool, so the push lasts
			w.entities[uid].erase("morale")
			SimWorld.HotState.set_hp(w, uid, 60000.0)
		out.append(uid)
	return out


func _events(w: SimWorld, n: int, ty: String) -> Array:
	var out := []
	for i in n:
		w.step()
		for ev in w.events:
			if String(ev.type) == ty:
				out.append(ev)
	return out


func _ls_in(w: SimWorld, Rr: Dictionary) -> Array:
	var n_in := 0
	var n := 0
	for k in Rr.mem:
		if String(Rr.mem[k].g) == "l":
			n += 1
			var e = w.entities.get(int(k))
			if e != null and int(e.get("garrisoned_in", -1)) == int(Rr.bar):
				n_in += 1
	return [n_in, n]


## Skirmish facility under a small infantry attack (the "skirmish unchanged" probe).
func _skirmish(ticks: int) -> SimWorld:
	var w := make_world()
	_ensure_g7()
	w.ai_state = {}
	var mw := int(w.map.w)
	var mh := int(w.map.h)
	var n := mini(60, mini(mw, mh) - 2)
	var o := Vector2i(mw / 2 - n / 2, mh / 2 - n / 2)
	var r := Rect2i(o, Vector2i(n, n))
	var t: PackedByteArray = w.map.terrain
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			t[y * mw + x] = Terrain.GRASS
	w.map.terrain = t
	for id in w.entities.keys():
		if r.has_point(w.cell_of(w.entities[id].pos)):
			w.entities.erase(id)
	w.cache.clear()
	Movement.rebuild_nav(w)
	var off: Array = CnFacility.conf().core_offset
	w.spawn_building("a_cn_facility", 0, o + Vector2i(2, 2) + Vector2i(int(off[0]), int(off[1])), true)
	w.run_ticks(CnFacility.DISCOVER_EVERY + 4)
	var cs := int(CnFacility.conf().compound)
	for i in 10:
		var c: Vector2i = Movement.nearest_free_cell(w, Vector2i(o.x + cs + 14, o.y + 6 + i), "foot", 1)
		var uid := w.spawn_unit("rifleman", 1, Vector2(c) + Vector2(0.5, 0.5))
		w.entities[uid].order = {"type": "attack_move", "target": Vector2(o.x + 2 + cs / 2, o.y + 2 + cs / 2)}
		Movement.order_path(w, w.entities[uid], Vector2(o.x + 2 + cs / 2, o.y + 2 + cs / 2))
	w.run_ticks(ticks)
	return w


# ================================================================ 1. present only in LP, size 100, barracks fits it
func test_reserve_lp_only_size_100() -> void:
	var w := _lp()
	var fid := _fid(w)
	var F := _fac(w)
	check(not F.is_empty(), "LP facility holds a barracks reserve")
	if F.is_empty():
		return
	var sm := LR.summary(w, int(F.id))
	var Rr := _rr(w)
	check_eq(int(sm.size), 100, "reserve size 100 (owner answer)")
	check_eq(int(sm.total), 100, "100 reserve Sentinels alive")
	check_eq(int(sm["in"]), 100, "all 100 inside the barracks (garrisoned, not on the map)")
	check_eq(int(sm.ls), 20, "last-stand group = 20% of the reserve")
	var b: Dictionary = w.entities[int(Rr.bar)]
	# WATCH7 authority record: G7_REFERENCE 13.9c-38 (owner "Double the watch": starting garrison 24 -> 48 in every mode);
	# the LP barracks extra slots grow 20 -> 48 so reserve 100 + the whole garrison 48 + 20 free fit (120 + 48 = 168).
	check_eq(Garrison.cap_of(b), 168, "LP barracks cap 120 + 48 extra = 168 (13.9c-38: reserve 100 + garrison 48 + 20 free)")
	var occ := Garrison.occupants(w, int(b.id)).size()
	check(Garrison.free_slots(w, b) >= 20, "at least 20 barracks slots stay free for returning wounded (occupants %d / 168)" % occ)
	check(Garrison.cap_of(b) >= 100 + (S7.R().start.force as Array).size() + 20, "the reserve, the whole starting garrison and 20 free slots fit the LP barracks")
	var mx := LR.mix(100)
	var have := {}
	for k in Rr.mem:
		have[String(Rr.mem[k].t)] = int(have.get(String(Rr.mem[k].t), 0)) + 1
		var e: Dictionary = w.entities[int(k)]
		check(not e.has("cn_team"), "reserve men are Sentinels, never strike-team units")
	check_eq(have, mx, "type mix = rules.start.force proportions without the bearer")
	var regular := 0
	for uid in S7.sentinels_of(w, fid):
		if not LR.is_member(w, uid):
			regular += 1
	check_eq(regular, (S7.R().start.force as Array).size(), "the normal starting garrison is still there on top of the reserve")
	print("LPRES7 LP start: reserve %d (ls %d), regulars %d, barracks occupants %d / %d, mix %s" % [int(sm.total), int(sm.ls), regular, occ, Garrison.cap_of(b), str(mx)])
	# skirmish: nothing of this exists
	var sk := _skirmish(600)
	check(not sk.sys_state.has("lpres7"), "a skirmish facility never creates reserve state")
	for id in sk.entities:
		var e: Dictionary = sk.entities[id]
		if e.kind == "building" and String(e.def) == "cn_sentinel_barracks":
			check_eq(Garrison.cap_of(e), 120, "skirmish barracks keeps 120 slots")
	check_eq(S7.sentinels_of(sk, 0).size(), 48, "skirmish facility keeps its normal 48-man garrison (13.9c-38: was 24)")
	print("LPRES7 skirmish facility hash = %s (pre-LPRES7 baseline 24927879802c9ccfe4da06b2ffa6d4282012b15759121495c8687f247841a220)" % str(sk.state_hash()))


# ================================================================ 2. tiers fire in order under rising pressure
func test_tiers_in_order_and_last_stand_held() -> void:
	var w := _lp()
	var F := _fac(w)
	if F.is_empty():
		check(false, "no reserve")
		return
	var Rr := _rr(w)
	var first := {}
	var watch := func(n: int) -> void:
		for i in n:
			w.step()
			for ev in w.events:
				if String(ev.type) == "LpReserveRelease" and not first.has(String(ev.tier)):
					first[String(ev.tier)] = w.tick
	# stage 0: calm -> nothing released
	watch.call(60)
	check(first.is_empty(), "calm: the reserve stays in the barracks (%s)" % str(first))
	# stage 1: two roster Sentinels killed -> one-for-one post refills
	var killed := []
	for uid in S7.sentinels_of(w, _fid(w)):
		if not LR.is_member(w, uid) and String(w.entities[uid].s7) != "bearer" and killed.size() < 2:
			killed.append(uid)
	for uid in killed:
		w.destroy(int(uid), "test")
	watch.call(45)
	check(first.has("post"), "tier 1: dead post Sentinels replaced from the reserve")
	check(int(Rr.rel.post) >= 2, "two replacements for two casualties (%d)" % int(Rr.rel.post))
	check(not first.has("qrf") and not first.has("surge"), "light pressure: no QRF / surge yet")
	# stage 2: a heavy push on the north wall -> QRF squad of 4-8 to the north face
	_enemies(w, F, 12.0, -4.0, 10)
	watch.call(60)
	check(first.has("qrf"), "tier 2: a quick-reaction squad goes to the pressed wall")
	var q_ok := false
	for q in Rr.sq:
		var Q: Dictionary = Rr.sq[q]
		if String(Q.t) == "q":
			var n := 0
			for k in Rr.mem:
				if int(Rr.mem[k].sq) == int(q):
					n += 1
			q_ok = q_ok or (String(Q.sec) == "n" and n >= 4 and n <= 8)
	check(q_ok, "QRF squad of 4-8 tasked to the north face (%s)" % str(Rr.sq))
	var moved := 0
	for k in Rr.mem:
		var M: Dictionary = Rr.mem[k]
		if String(M.st) == "out":
			var e: Dictionary = w.entities[int(k)]
			var j: Dictionary = S7.job_of(w, int(k))
			if not e.has("garrisoned_in") and String(j.get("k", "")) == "standto" and int(e.get("gait", 0)) >= 1:
				moved += 1
	check(moved >= 2, "QRF men are out of the barracks on the Sentinel stand-to drill with a tactical gait (%d)" % moved)
	check(not first.has("surge"), "no breach yet: no surge")
	var li := _ls_in(w, Rr)
	check_eq(int(li[0]), int(li[1]), "last stand held in the barracks during the wall fight")
	# stage 3: enemies inside the walls (away from the core) -> breach surge
	_enemies(w, F, 21.0, 11.0, 4)
	watch.call(45)
	check(first.has("surge"), "tier 3: a counter-attack surge on a real breach")
	check(int(Rr.rel.surge) >= 12, "the surge is big (>= 12 men: %d)" % int(Rr.rel.surge))
	li = _ls_in(w, Rr)
	check_eq(int(li[0]), int(li[1]), "last stand still held in the barracks during the breach")
	check(not first.has("ls"), "last stand not committed before the core is threatened")
	# stage 4: an enemy at the core rooms -> the last stand commits there
	_enemies(w, F, 6.5, 12.0, 2)
	watch.call(45)
	check(first.has("ls"), "the last stand commits when the core rooms are threatened")
	var ls_goal_ok := true
	var core := Rect2(Vector2(CnFacility.origin(F)) + Vector2(2, 2), Vector2(11, 15)).grow(4.0)
	for k in Rr.mem:
		if String(Rr.mem[k].g) == "l" and String(Rr.mem[k].st) == "out":
			var j: Dictionary = S7.job_of(w, int(k))
			ls_goal_ok = ls_goal_ok and core.has_point(Vector2(j.get("pos", Vector2(-99, -99))))
	check(ls_goal_ok, "last-stand men are posted only at the core doors")
	check(int(first.get("post", 0)) < int(first.get("qrf", 0)) and int(first.get("qrf", 0)) < int(first.get("surge", 0)) and int(first.get("surge", 0)) < int(first.get("ls", 0)),
		"tiers fired in order post < qrf < surge < last stand (%s)" % str(first))
	check_eq(int(Rr.tier_max), 4, "card tier reached LAST STAND")
	# 13.9c-29: never strike teams / spec ops
	var cn_ok := true
	var n_cn := 0
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.has("cn_team"):
			n_cn += 1
			var j: Dictionary = S7.job_of(w, int(id))
			cn_ok = cn_ok and not LR.is_member(w, int(id)) and not String(j.get("j", "")).begins_with("lpr:")
	check(n_cn > 0 and cn_ok, "strike teams / spec ops (%d units) never touched by the reserve" % n_cn)
	print("LPRES7 tiers first tick: %s rel %s" % [str(first), str(Rr.rel)])


# ================================================================ 3. quiet sectors send the men home
func test_quiet_sector_returns_home() -> void:
	var w := _lp()
	var F := _fac(w)
	var Rr := _rr(w)
	var en := _enemies(w, F, 12.0, -4.0, 10)
	w.run_ticks(45)
	var out0 := int(LR.summary(w, int(F.id)).field)
	check(out0 >= 4, "QRF out (%d)" % out0)
	for uid in en:
		w.destroy(int(uid), "test")
	var rc := _events(w, 20 * 30, "LpReserveRecall")
	check(not rc.is_empty(), "sector quiet for quiet_s -> squad recalled")
	w.run_ticks(20 * 30)
	var sm := LR.summary(w, int(F.id))
	check(int(sm.field) <= 1, "the squad walked back into the barracks (field %d, in %d)" % [int(sm.field), int(sm["in"])])
	var full := 0
	for k in Rr.mem:
		var e: Dictionary = w.entities[int(k)]
		if int(e.get("garrisoned_in", -1)) == int(Rr.bar) and int(e.get("ammo", 0)) == int(Content.unit(String(e.def)).get("ammo_max", -1)):
			full += 1
	check(full >= int(sm["in"]) - 1, "men back in the barracks are refilled (%d / %d)" % [full, int(sm["in"])])


# ================================================================ 4. manual control: release / recall / auto off
func test_manual_release_recall_auto() -> void:
	var w := _lp()
	var F := _fac(w)
	var Rr := _rr(w)
	var fid := _fid(w)
	check(LR.validate_command(w, {"type": "lpres_release", "issuer": _mfid(w)}) != "", "another side cannot release this reserve")
	check(LR.validate_command(w, {"type": "lpres_recall", "issuer": fid}) != "", "recall refused while nobody is out")
	check(LR.validate_command(w, {"type": "lpres_auto", "issuer": fid}) != "", "auto needs on")
	check_eq(LR.validate_command(w, {"type": "lpres_auto", "issuer": fid, "on": false, "building_id": int(Rr.bar)}), "", "auto toggle valid (by barracks id)")
	LR.apply_command(w, {"type": "lpres_auto", "issuer": fid, "on": false, "building_id": int(Rr.bar)})
	check(not bool(Rr.auto), "AUTO OFF")
	_enemies(w, F, 12.0, -4.0, 10)
	var ev := _events(w, 80, "LpReserveRelease")
	check(ev.is_empty(), "auto off: heavy pressure releases nobody by itself")
	check_eq(LR.validate_command(w, {"type": "lpres_release", "issuer": fid}), "", "release squad valid")
	LR.apply_command(w, {"type": "lpres_release", "issuer": fid})
	var sm := LR.summary(w, int(F.id))
	check_eq(int(sm.rel.man), 6, "manual release = one squad of 6")
	var man_sec := ""
	for q in Rr.sq:
		if String(Rr.sq[q].t) == "m":
			man_sec = String(Rr.sq[q].sec)
	check_eq(man_sec, "n", "the manual squad goes to the most pressed face")
	w.run_ticks(60)
	check(int(LR.summary(w, int(F.id)).field) >= 6, "the manual squad is out")
	check_eq(LR.validate_command(w, {"type": "lpres_recall", "issuer": fid}), "", "recall valid")
	LR.apply_command(w, {"type": "lpres_recall", "issuer": fid})
	var ret := 0
	for k in Rr.mem:
		if String(Rr.mem[k].st) == "ret":
			ret += 1
	check(ret >= 6, "recall sends every man out home (%d)" % ret)
	LR.apply_command(w, {"type": "lpres_auto", "issuer": fid, "on": true})
	check(bool(Rr.auto), "AUTO ON again")
	var ev2 := _events(w, 60, "LpReserveRelease")
	var qrf := 0
	for e in ev2:
		if String(e.tier) == "qrf":
			qrf += 1
	check_eq(qrf, 0, "recall holds automatic QRF release for recall_hold_s")
	var ev3 := _events(w, 20 * 20, "LpReserveRelease")
	var qrf3 := 0
	for e in ev3:
		if String(e.tier) == "qrf":
			qrf3 += 1
	check(qrf3 > 0, "after the hold, auto release resumes under pressure")


# ================================================================ 5. trickle: slow, paid, up to size, stops with the barracks
func test_trickle_paid_and_stops() -> void:
	var w := _lp()
	var F := _fac(w)
	var Rr := _rr(w)
	var fid := _fid(w)
	var killed := 0
	for k in _sorted(Rr.mem):
		if killed < 3 and String(Rr.mem[str(k)].g) == "r":
			w.destroy(int(k), "test")
			killed += 1
	w.run_ticks(25)
	check_eq(int(LR.summary(w, int(F.id)).total), 97, "three reserve men lost")
	var c0 := int(w.factions[fid].credits)
	Rr.tr_at = w.tick + 1
	var tr := _events(w, 25, "LpReserveTrained")
	check_eq(tr.size(), 1, "one replacement per trickle period")
	check(int(w.factions[fid].credits) < c0, "the replacement is paid (%d -> %d)" % [c0, int(w.factions[fid].credits)])
	check(int(Rr.tr_at) - w.tick > 20 * 30, "next replacement only after every_s (slow)")
	var sm := LR.summary(w, int(F.id))
	check_eq(int(sm.total), 98, "reserve 97 -> 98")
	check_eq(int(sm.trained), 1, "trained counter")
	# up to size only
	var w2 := _lp()
	var R2 := _rr(w2)
	R2.tr_at = w2.tick + 1
	check(_events(w2, 25, "LpReserveTrained").is_empty(), "a full reserve trains nobody")
	# barracks gone: trickle stops, reserve joins the roster, last stand holds the core
	var bar := int(Rr.bar)
	w.destroy(bar, "test")
	w.run_ticks(25)
	check(bool(Rr.gone), "barracks loss noticed")
	Rr.tr_at = w.tick + 1
	check(_events(w, 40, "LpReserveTrained").is_empty(), "trickle stops when the barracks is gone")
	var ls_out := 0
	var r_left := 0
	for k in Rr.mem:
		if String(Rr.mem[k].g) == "l" and String(Rr.mem[k].st) == "out":
			ls_out += 1
		elif String(Rr.mem[k].g) == "r":
			r_left += 1
	check(ls_out >= 15, "the last stand holds the core when the barracks is gone (%d)" % ls_out)
	check_eq(r_left, 0, "the rest of the reserve joined the duty roster")


func _sorted(d: Dictionary) -> Array:
	var ks := []
	for k in d:
		ks.append(int(k))
	ks.sort()
	return ks


# ================================================================ 6. save / load mid-release: same future
func test_save_load_mid_release() -> void:
	var w := _lp()
	var F := _fac(w)
	_enemies(w, F, 12.0, -4.0, 10, false)
	_enemies(w, F, 21.0, 11.0, 4, false)
	w.run_ticks(50)
	var Rr := _rr(w)
	check(int(Rr.rel.qrf) + int(Rr.rel.surge) > 0, "mid-release (rel %s)" % str(Rr.rel))
	var c := SimWorld.from_dict(bytes_to_var(var_to_bytes(w.to_dict())))
	check_eq(c.state_hash(), w.state_hash(), "deep round trip = same hash")
	w.run_ticks(200)
	c.run_ticks(200)
	check_eq(c.state_hash(), w.state_hash(), "deep save/load mid-release gives the same future (200 ticks)")
	var a := SimWorld.from_dict(_base_dict.duplicate(true))
	var b := SimWorld.from_dict(_base_dict.duplicate(true))
	a.ai_state = {}
	b.ai_state = {}
	_enemies(a, _fac(a), 12.0, -4.0, 10, false)
	_enemies(b, _fac(b), 12.0, -4.0, 10, false)
	a.run_ticks(120)
	b.run_ticks(120)
	check_eq(a.state_hash(), b.state_hash(), "same start + same pressure = same hash")



# ================================================================ 7. cost probe (informational; the gate is test_lpperf7)
## Same LP world twice under the same north-wall push: with the reserve (A) and with the 100 reserve men removed (B).
## Prints the sim ms/tick of both and LpReserve7's own step cost; checks only that its own cadence stays cheap.
func test_cost_probe() -> void:
	var a := _lp()
	var b := _lp()
	var Fa := _fac(a)   # same facility in both worlds; read before b's reserve state is erased
	var Rb := _rr(b)
	for k in _sorted(Rb.mem):
		b.destroy(int(k), "test")
	b.sys_state.erase("lpres7")
	for wv in [a, b]:
		_enemies(wv, Fa, 12.0, -4.0, 10)
		wv.run_ticks(20)
	var n := 300
	var t0 := Time.get_ticks_usec()
	a.run_ticks(n)
	var ta := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	b.run_ticks(n)
	var tb := Time.get_ticks_usec() - t0
	var st = a.sys_state.get("lpres7")
	var t1 := Time.get_ticks_usec()
	for i in 50:
		LR._step(a, st, st.facs[st.facs.keys()[0]])
	var per := float(Time.get_ticks_usec() - t1) / 50.0
	print("LPRES7 cost: with reserve %.2f ms/tick, without %.2f ms/tick (x%.3f); LpReserve7 step %.0f us (once a second per facility)" % [float(ta) / n / 1000.0, float(tb) / n / 1000.0, float(ta) / maxf(float(tb), 1.0), per])
	check(per < 3000.0, "the reserve's once-a-second step stays cheap (%.0f us)" % per)
