extends RefCounted
## G7 (THREAT7): Machine threat units (master scope section 8, brainstorm B13-B15, B17). Owner: THREAT7.
## Defs: content/g7/defs_g7_threats.json (units with a `t7` kind tag; rules.g7_threats), numbers PROVISIONAL.
##   burrower    tunnels under the creep (hidden, holds fire, faster), up to tunnel_tiles off the creep edge; erupts
##               under an enemy vehicle / convoy or soldiers in a deployment ring (blast + vehicle damage), fights,
##               re-burrows on creep after reburrow_s.
##   spitter     ranged nanite slugs (Wounds.puncture on every soldier hit: the main source of suit breaches);
##               prefers sealed-suit soldiers.
##   mimic       disguised (hidden from enemies, attacks nothing, drawn as rules mimic.as_foot by the view) until
##               exposed by a scanner technician in scan_radius, CNFAC7's decontamination walkway (e.mimic_exposed)
##               or its own strike; then it fights (MimicExposed {id, by}).
##   packhunter  packs of 4-6 (e.t7.pk): members take flank slots around the target at flank_radius, then close in;
##               talon swipes puncture suits; on a vehicle they wreck the gun mounts (e.t7w).
##   leech       latches onto an enemy vehicle (e.leech_on = vehicle id, CREEP7's field; rides on the hull) and
##               drills its parts one by one (vehicle e.t7w {mg_front, mg_rear, panel_l, panel_r, dome} 0..1):
##               a wrecked dome drops (Apc7.set_dome off), both mounts wrecked = the vehicle holds fire. Comes off
##               when shot dead, pried off (soldiers within pry_radius of the vehicle; crew inside slowly while it
##               is stopped), by the APC EMP / Creep.detach_leeches / MachineEW7.stun (they erase e.leech_on).
##   weaver      web spit: vehicles slowed (e.t7slow, read by Morale: CR), soldiers cocooned (e.t7c {by, cut, on};
##               suit breached via Wounds.puncture) and hauled toward the nearest creep; a cocoon on creep for
##               lost_on_creep_s = soldier lost (CocoonLost). Friendly soldiers in cut_radius cut it open (slow;
##               fast_roles fast). Spawns only while allow_weavers(w, true) (LPMODE7).
## AI (AI-run Machine sides only, w.ai_state): movement orders on a staggered think cadence; reads MachineReact7's
## learned reactions (1 defend sites, 2 hunt teams, 3 raid facility). Attacks / latching / cocoons run for every
## owner. Extra threat units join escalation waves (rules waves by unit tier, own timer).
## State: w.sys_state.threats7 {ver, ids, weavers, wave_t, next_pk, cocoons, slowed, scan_t}, created only when a
## threat unit exists (spawn / adopt / wave) or the Weaver gate is set: a match without them is hash-identical.
## Commands: t7_pry {unit_ids, target vehicle id}, t7_cut {unit_ids, target cocooned soldier id} (ORCH registers).

const HotState = preload("res://sim/hot_state.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const Creep = preload("res://sim/systems/creep.gd")
const Cores = preload("res://sim/systems/cores.gd")
const MachineEW7 = preload("res://sim/systems/machine_ew7.gd")
const Damage = preload("res://sim/systems/damage.gd")

const VER := 1
const Q := 1.0 / 1024.0
const KINDS := ["burrower", "spitter", "mimic", "packhunter", "leech", "weaver"]
const PARTS := ["mg_front", "mg_rear", "panel_l", "panel_r", "dome"]


# ================================================================ helpers
static func RT() -> Dictionary:
	return Content.rules().get("g7_threats", {})


static func RK(kind: String) -> Dictionary:
	return RT().get(kind, {})


static func kind_of(def_id: String) -> String:
	return String(Content.unit(def_id).get("t7", ""))


static func st(w: SimWorld):
	return w.sys_state.get("threats7")


static func _st(w: SimWorld) -> Dictionary:
	var s = w.sys_state.get("threats7")
	if s == null:
		s = {"ver": VER, "ids": [], "weavers": false, "wave_t": w.tick, "next_pk": 1, "cocoons": [], "slowed": [],
			"scan_t": 0}
		w.sys_state["threats7"] = s
	return s


static func _t(secs: float) -> int:
	return maxi(roundi(secs * SimWorld.TICK_RATE), 1)


static func _pos(w: SimWorld, e: Dictionary) -> Vector2:
	return HotState.get_pos(w, int(e.id))


static func _set_pos(w: SimWorld, e: Dictionary, p: Vector2) -> void:
	HotState.set_pos(w, int(e.id), Vector2(snappedf(p.x, Q), snappedf(p.y, Q)))


## Weapon cooldown in ticks read from the dict (authoritative: Combat writes e.cd_ticks; the hot array can lag it,
## and reading the hot copy broke the save round-trip hash).
static func _cd(e: Dictionary) -> int:
	if e.has("cd_ticks"):
		return int(e.cd_ticks)
	return maxi(ceili(float(e.get("cooldown", 0.0)) * SimWorld.TICK_RATE - 1e-6), 0)


## EMP / EW hold: the unit does nothing this tick.
static func held(w: SimWorld, e: Dictionary) -> bool:
	return MachineEW7.held(w, int(e.id)) != "" or w.tick < int(e.get("emp_until", -1))


static func is_soldier(e: Dictionary) -> bool:
	return e.kind == "unit" and e.has("morale")


static func is_vehicle(e: Dictionary) -> bool:
	if e.kind != "unit" or e.has("morale"):
		return false
	var d := Content.unit(String(e.def))
	return not bool(d.get("is_air", false)) and String(d.get("move_class", "")) != "foot" and kind_of(String(e.def)) == ""


## Units within r of p (ascending id). Exact scan of the unit index (Combat's neighbour grid is not used: it is
## a cache that a loaded save rebuilds on its own cadence, which broke the save round-trip hash).
static func near(w: SimWorld, p: Vector2, r: float) -> Array:
	var out := []
	var r2 := r * r
	for u in SimIndex.of(w, "unit"):
		if w.entities.has(int(u.id)) and p.distance_squared_to(Vector2(u.pos)) <= r2:
			out.append(u)
	out.sort_custom(func(a, b): return int(a.id) < int(b.id))
	return out


## Enemy ground units of fid within r of p that a threat may attack (ascending id; air, hidden units and
## cocooned soldiers excluded).
static func enemies_near(w: SimWorld, fid: int, p: Vector2, r: float) -> Array:
	var out := []
	for u in near(w, p, r):
		if not w.entities.has(int(u.id)) or not w.is_enemy(fid, int(u.owner)):
			continue
		if bool(Content.unit(String(u.def)).get("is_air", false)) or u.has("t7c") or bool(u.get("hid", false)):
			continue
		out.append(u)
	return out


static func closest(units: Array, p: Vector2) -> Variant:
	var best = null
	var bd := INF
	for u in units:
		var d := p.distance_squared_to(Vector2(u.pos))
		if d < bd:
			bd = d
			best = u
	return best


## One attack of atk {dmg, acc, puncture} from e on t (hit roll on w.rng). true on a hit.
static func strike(w: SimWorld, e: Dictionary, t: Dictionary, atk: Dictionary, zone := "") -> bool:
	if w.rng.randf() >= float(atk.get("acc", 1.0)):
		w.emit("ThreatMiss", {"id": int(e.id), "target": int(t.id)})
		return false
	if bool(atk.get("puncture", false)) and is_soldier(t):
		SimWorld.Wounds.puncture(w, t, e)
	Damage.wound_hit(w, e, t, float(atk.get("dmg", 10.0)), zone)
	return true


# ================================================================ public API
## Spawns a threat unit (def with a t7 tag). Weavers only while allow_weavers is on. Returns the id or -1.
static func spawn(w: SimWorld, def_id: String, fid: int, pos: Vector2) -> int:
	var k := kind_of(def_id)
	if k == "" or (k == "weaver" and not weavers_allowed(w)):
		return -1
	var id := w.spawn_unit(def_id, fid, pos)
	adopt(w, id)
	return id


## Registers an existing unit (map placement, other systems). false when it is not a threat unit.
static func adopt(w: SimWorld, id: int) -> bool:
	var e = w.entities.get(id)
	if e == null or e.kind != "unit":
		return false
	var k := kind_of(String(e.def))
	if k == "":
		return false
	var s := _st(w)
	if (s.ids as Array).has(id):
		return true
	s.ids.append(id)
	s.ids.sort()
	e.t7 = {"k": k, "st": "hunt", "cd": w.tick + (id % 7), "tk": -1}
	_init_kind(w, e, k)
	w.emit("ThreatSpawned", {"id": id, "owner": int(e.owner), "kind": k, "pos": e.pos})
	return true


## LPMODE7 opens / closes the Weaver window (60-75% into a Last Protocol run).
static func allow_weavers(w: SimWorld, on: bool) -> void:
	var s := _st(w)
	if bool(s.weavers) != on:
		s.weavers = on
		w.emit("WeaversAllowed", {"on": on})


static func weavers_allowed(w: SimWorld) -> bool:
	var s = st(w)
	return s != null and bool(s.weavers)


static func is_disguised(e: Dictionary) -> bool:
	return e.has("t7") and String(e.t7.k) == "mimic" and String(e.t7.st) == "disguised"


static func is_burrowed(e: Dictionary) -> bool:
	return e.has("t7") and String(e.t7.k) == "burrower" and String(e.t7.st) == "burrowed"


## Vehicle part integrity 0..1 (1.0 = intact). p in PARTS.
static func part(e: Dictionary, p: String) -> float:
	return float(e.get("t7w", {}).get(p, 1.0))


static func part_ok(e: Dictionary, p: String) -> bool:
	return part(e, p) > 0.0


static func cocooned(e: Dictionary) -> bool:
	return e.has("t7c")


## Leech ids latched onto vehicle vid (ascending).
static func leeches_on(w: SimWorld, vid: int) -> Array:
	var out := []
	var s = st(w)
	if s == null:
		return out
	for id in s.ids:
		var e = w.entities.get(int(id))
		if e != null and int(e.get("leech_on", -1)) == vid:
			out.append(int(id))
	return out


## Render info for the view (LOOK7): {} for a non-threat, else {k, st, on (vehicle id), as (disguise def)}.
static func render_info(e: Dictionary) -> Dictionary:
	if not e.has("t7"):
		return {}
	var out := {"k": e.t7.k, "st": e.t7.st}
	if e.has("leech_on"):
		out["on"] = int(e.leech_on)
	if is_disguised(e):
		out["as"] = String(e.get("mimic_as", ""))
	return out


# ================================================================ per-kind setup
static func _init_kind(w: SimWorld, e: Dictionary, k: String) -> void:
	match k:
		"burrower":
			_go_under(w, e)
		"mimic":
			e.t7.st = "disguised"
			e.mimic = true
			e.mimic_as = String(RK("mimic").get("as_foot", "g7_cn_gunner"))
			e.hid = true
			e.spot = []


static func _go_under(w: SimWorld, e: Dictionary) -> void:
	e.t7.st = "burrowed"
	e.t7.tun = 0.0
	e.hid = true
	e.spot = []
	w.emit("BurrowerUnder", {"id": int(e.id), "pos": e.pos})


static func _surface(w: SimWorld, e: Dictionary, why: String) -> void:
	e.t7.st = "up"
	e.t7.up = w.tick
	e.hid = false
	e.spot = []
	e.erase("t7mv")
	w.emit("BurrowerSurfaced", {"id": int(e.id), "pos": e.pos, "why": why})


## Mimic exposure (scanner technician, decontamination walkway, own strike or any caller). false if not disguised.
static func expose(w: SimWorld, e: Dictionary, by: String) -> bool:
	if not is_disguised(e):
		return false
	e.t7.st = "exposed"
	e.hid = false
	e.spot = []
	e.mimic_exposed = true
	e.erase("mimic_as")
	w.emit("MimicExposed", {"id": int(e.id), "owner": int(e.owner), "by": by, "pos": e.pos})
	return true


# ================================================================ behaviours (one unit per call)
## Generic close / ranged attack on the cadence atk.every_s. Returns the target hit attempt or null.
static func _attack(w: SimWorld, e: Dictionary, p: Vector2, atk: Dictionary, prefer_suit := false) -> Variant:
	if w.tick < int(e.t7.cd):
		return null
	var en := enemies_near(w, int(e.owner), p, float(atk.get("range", 1.3)))
	if en.is_empty():
		return null
	var t = null
	if prefer_suit:
		var suits := []
		for u in en:
			if bool(u.get("suit", false)) and not bool(u.get("wpunct", false)):
				suits.append(u)
		t = closest(suits, p)
	if t == null:
		t = closest(en, p)
	e.t7.cd = w.tick + _t(float(atk.get("every_s", 1.0)))
	e.t7.tk = int(t.id)
	e.facing = snappedf((Vector2(t.pos) - p).angle(), Q) if Vector2(t.pos) != p else float(e.get("facing", 0.0))
	return t


static func _burrower(w: SimWorld, _s: Dictionary, e: Dictionary, p: Vector2) -> void:
	var r := RK("burrower")
	var t7: Dictionary = e.t7
	if String(t7.st) == "burrowed":
		e.t7mv = float(r.get("speed_mult_burrowed", 1.5))
		if not Creep.on_creep(w, w.cell_of(p)):
			t7.tun = snappedf(float(t7.tun) + p.distance_to(Vector2(t7.get("lp", p))), Q)
		t7.lp = p
		if float(t7.tun) >= float(r.get("tunnel_tiles", 48.0)):
			_surface(w, e, "tunnel_end")
			return
		if (w.tick + int(e.id)) % 5 == 0:
			var en := enemies_near(w, int(e.owner), p, float(r.get("trigger_radius", 2.0)))
			if not en.is_empty():
				_erupt(w, e, p, r)
		return
	var t = _attack(w, e, p, r.get("atk", {}))
	if t != null:
		strike(w, e, t, r.get("atk", {}))
	elif w.tick - int(t7.get("up", 0)) >= _t(float(r.get("reburrow_s", 20.0))) and Creep.on_creep(w, w.cell_of(p)) \
			and enemies_near(w, int(e.owner), p, 4.0).is_empty():
		_go_under(w, e)


static func _erupt(w: SimWorld, e: Dictionary, p: Vector2, r: Dictionary) -> void:
	_surface(w, e, "erupt")
	var n := 0
	for u in enemies_near(w, int(e.owner), p, float(r.get("erupt_radius", 2.5))):
		var dmg := float(r.get("erupt_vehicle_dmg", 160.0)) if is_vehicle(u) else float(r.get("erupt_dmg", 70.0))
		Damage.wound_hit(w, e, u, dmg, "leg_l" if is_soldier(u) else "")
		n += 1
	w.emit("BurrowerErupt", {"id": int(e.id), "owner": int(e.owner), "pos": p, "hit": n})


static func _spitter(w: SimWorld, _s: Dictionary, e: Dictionary, p: Vector2) -> void:
	var r := RK("spitter")
	var atk: Dictionary = r.get("atk", {})
	var t = _attack(w, e, p, atk, bool(r.get("suit_pref", true)))
	if t == null:
		return
	var ok := Damage.line_clear(w, p, Vector2(t.pos))
	var hit := ok and strike(w, e, t, atk, "torso")
	w.emit("NaniteSlug", {"id": int(e.id), "target": int(t.id), "from": p, "to": t.pos, "hit": hit})


static func _mimic(w: SimWorld, _s: Dictionary, e: Dictionary, p: Vector2) -> void:
	var r := RK("mimic")
	if is_disguised(e):
		e.hid = true
		if bool(e.get("mimic_exposed", false)):
			e.mimic_exposed = false
			expose(w, e, "decon")
			return
		if (w.tick + int(e.id)) % 5 != 0:
			return
		for u in near(w, p, float(r.get("scan_radius", 4.0))):
			if w.is_enemy(int(e.owner), int(u.owner)) and String(Content.unit(String(u.def)).get("cn_role", "")) == "scanner":
				expose(w, e, "scanner")
				return
		var tgt = closest(enemies_near(w, int(e.owner), p, float(r.get("strike_radius", 1.5))), p)
		if tgt == null or not bool(e.t7.get("go", false)):
			return
		expose(w, e, "strike")
	var t = _attack(w, e, p, r.get("atk", {}))
	if t != null:
		strike(w, e, t, r.get("atk", {}), "torso")


static func _packhunter(w: SimWorld, _s: Dictionary, e: Dictionary, p: Vector2) -> void:
	var r := RK("packhunter")
	var atk: Dictionary = r.get("atk", {})
	var t = _attack(w, e, p, atk)
	if t == null:
		return
	var hit := strike(w, e, t, atk, "")
	if hit and is_vehicle(t) and w.entities.has(int(t.id)):
		for pt in ["mg_front", "mg_rear"]:
			if part_ok(t, pt):
				wreck(w, t, pt, float(r.get("mount_wreck", 0.12)), int(e.id))
				break
	w.emit("PackhunterSwipe", {"id": int(e.id), "target": int(t.id), "hit": hit})


## Damages vehicle part p by amt (0..1). Emits PartWrecked when it reaches 0.
static func wreck(w: SimWorld, v: Dictionary, p: String, amt: float, by: int) -> void:
	if not v.has("t7w"):
		v.t7w = {}
	var cur := part(v, p)
	if cur <= 0.0:
		return
	var nv := snappedf(maxf(cur - amt, 0.0), Q)
	v.t7w[p] = nv
	var s := _st(w)
	if not (s.slowed as Array).has(int(v.id)):
		s.slowed.append(int(v.id))
		s.slowed.sort()
	if nv <= 0.0:
		w.emit("PartWrecked", {"vehicle": int(v.id), "owner": int(v.owner), "part": p, "by": by})
	_part_effects(w, v)


## Wrecked parts act on the vehicle: dome down, no mounts = holds fire.
static func _part_effects(w: SimWorld, v: Dictionary) -> void:
	if not v.has("t7w"):
		return
	if not part_ok(v, "dome") and v.has("a7") and bool(v.a7.get("dome_on", false)):
		SimWorld.Apc7.set_dome(w, v, false)
	if not part_ok(v, "mg_front") and not part_ok(v, "mg_rear"):
		if _cd(v) < 2:
			HotState.set_cd(w, int(v.id), 2)


static func _friendly_helpers(w: SimWorld, fid: int, p: Vector2, r: float, skip: int) -> Array:
	var out := []
	for u in near(w, p, r):
		if int(u.id) == skip or not is_soldier(u) or u.has("t7c") or bool(u.get("hid", false)) or u.has("t7"):
			continue
		if int(u.owner) != fid and not w.is_ally(int(u.owner), fid):
			continue
		if SimWorld.Wounds.is_down(u):
			continue
		out.append(u)
	return out


static func _leech(w: SimWorld, _s: Dictionary, e: Dictionary, p: Vector2) -> void:
	var r := RK("leech")
	var t7: Dictionary = e.t7
	var vid := int(e.get("leech_on", -1))
	if vid < 0:
		if String(t7.st) == "latched":   # knocked off by the EMP / Creep.detach_leeches / MachineEW7.stun
			t7.st = "hunt"
			t7.drop = w.tick + _t(float(r.get("drop_stun_s", 3.0)))
		if w.tick < int(t7.get("drop", -1)) or w.tick < int(t7.cd):
			return
		t7.cd = w.tick + 5
		for u in enemies_near(w, int(e.owner), p, float(r.get("latch_range", 1.3))):
			if is_vehicle(u):
				e.leech_on = int(u.id)
				t7.st = "latched"
				t7.pry = 0.0
				t7.cd = w.tick + _t(float(r.get("drill_every_s", 2.0)))
				w.emit("LeechLatched", {"id": int(e.id), "vehicle": int(u.id), "owner": int(u.owner)})
				return
		return
	var v = w.entities.get(vid)
	if v == null:
		e.erase("leech_on")
		t7.st = "hunt"
		return
	var vp := _pos(w, v)
	var a := TAU * float(int(e.id) % 6) / 6.0
	_set_pos(w, e, vp + Vector2(cos(a), sin(a)) * 0.5)
	HotState.set_moving(w, int(e.id), false)
	if w.tick >= int(t7.cd):
		t7.cd = w.tick + _t(float(r.get("drill_every_s", 2.0)))
		var hitp := ""
		for pt in r.get("parts", PARTS):
			if part_ok(v, String(pt)):
				hitp = String(pt)
				wreck(w, v, hitp, float(r.get("part_dmg", 0.1)), int(e.id))
				break
		w.emit("LeechDrill", {"id": int(e.id), "vehicle": vid, "part": hitp})
		Damage.wound_hit(w, e, v, float(r.get("hull_dmg", 4.0)))
		if not w.entities.has(vid):
			e.erase("leech_on")
			return
	if (w.tick + int(e.id)) % 10 == 0:
		_pry_step(w, e, v, vp, r)


## Soldiers next to the vehicle (and the crew inside while it is stopped) pry the leech off.
static func _pry_step(w: SimWorld, e: Dictionary, v: Dictionary, vp: Vector2, r: Dictionary) -> void:
	var rate := 0.0
	var by = null
	for u in _friendly_helpers(w, int(v.owner), vp, float(r.get("pry_radius", 1.8)), -1):
		rate += 1.0 / maxf(float(r.get("pry_s_outside", 5.0)), 0.1)
		if by == null:
			by = u
	if not HotState.get_moving(w, int(v.id)) and not (v.get("cargo", []) as Array).is_empty():
		rate += 1.0 / maxf(float(r.get("pry_s_crew", 14.0)), 0.1)
		if by == null:
			by = v
	if rate <= 0.0:
		return
	e.t7.pry = snappedf(float(e.t7.get("pry", 0.0)) + rate * 10.0 / SimWorld.TICK_RATE, Q)
	if float(e.t7.pry) >= 1.0:
		pry_off(w, e, by, "pry")


## Takes a latched leech off (pried, or any caller). by = the helper entity or null.
static func pry_off(w: SimWorld, e: Dictionary, by, how: String) -> bool:
	if not e.has("leech_on"):
		return false
	var vid := int(e.leech_on)
	e.erase("leech_on")
	var r := RK("leech")
	e.t7.st = "hunt"
	e.t7.pry = 0.0
	e.t7.drop = w.tick + _t(float(r.get("drop_stun_s", 3.0)))
	var v = w.entities.get(vid)
	if v != null:
		var a := TAU * float(int(e.id) % 6) / 6.0
		_set_pos(w, e, _pos(w, v) + Vector2(cos(a), sin(a)) * 1.6)
	var src: Dictionary = by if typeof(by) == TYPE_DICTIONARY else {"id": -1, "owner": -1}
	w.emit("LeechPried", {"id": int(e.id), "vehicle": vid, "by": int(src.get("id", -1)), "how": how})
	Damage.wound_hit(w, src, e, float(r.get("throw_dmg", 25.0)))
	return true


static func _weaver(w: SimWorld, s: Dictionary, e: Dictionary, p: Vector2) -> void:
	var r := RK("weaver")
	var t7: Dictionary = e.t7
	var co := []
	for cid in t7.get("co", []):
		var c = w.entities.get(int(cid))
		if c != null and c.has("t7c") and int(c.t7c.by) == int(e.id):
			co.append(int(cid))
	t7.co = co
	if w.tick >= int(t7.get("wcd", 0)):
		var en := enemies_near(w, int(e.owner), p, float(r.get("web_range", 7.0)))
		var sol := []
		var veh := []
		for u in en:
			if is_soldier(u):
				sol.append(u)
			elif is_vehicle(u) and not u.has("t7mv"):
				veh.append(u)
		var tgt = closest(sol, p) if co.size() < int(r.get("max_cocoons", 2)) else null
		if tgt == null:
			tgt = closest(veh, p)
		if tgt != null:
			t7.wcd = w.tick + _t(float(r.get("web_every_s", 6.0)))
			if is_soldier(tgt):
				_cocoon(w, s, e, tgt)
				co.append(int(tgt.id))
			else:
				tgt.t7mv = float(r.get("web_slow", 0.45))
				tgt.t7mv_until = w.tick + _t(float(r.get("web_slow_s", 8.0)))
				if not (s.slowed as Array).has(int(tgt.id)):
					s.slowed.append(int(tgt.id))
					s.slowed.sort()
				w.emit("WebSpit", {"id": int(e.id), "target": int(tgt.id), "kind": "slow", "from": p, "to": tgt.pos})
	if not co.is_empty():
		_haul(w, e, p, r, co)
		return
	var t = _attack(w, e, p, r.get("atk", {}))
	if t != null:
		strike(w, e, t, r.get("atk", {}))


static func _cocoon(w: SimWorld, s: Dictionary, e: Dictionary, t: Dictionary) -> void:
	t.t7c = {"by": int(e.id), "cut": 0.0, "on": 0, "p": t.pos}
	SimWorld.Wounds.puncture(w, t, e)   # a cocooned soldier's suit counts as breached
	t.order = {"type": "hold"}
	HotState.touch(w, int(t.id))
	HotState.set_moving(w, int(t.id), false)
	if not (s.cocoons as Array).has(int(t.id)):
		s.cocoons.append(int(t.id))
		s.cocoons.sort()
	w.emit("Cocooned", {"id": int(t.id), "owner": int(t.owner), "by": int(e.id), "pos": t.pos})
	w.emit("WebSpit", {"id": int(e.id), "target": int(t.id), "kind": "cocoon", "from": e.pos, "to": t.pos})


## Nearest creep tile centre within 64 tiles (square rings every 4 tiles, fixed scan order) or null.
static func _creep_home(w: SimWorld, p: Vector2) -> Variant:
	if not Creep.enabled(w):
		return null
	var c0 := w.cell_of(p)
	for rad in range(0, 68, 4):
		var best = null
		var bd := INF
		for dy in range(-rad, rad + 1, 4):
			for dx in range(-rad, rad + 1, 4):
				if maxi(absi(dx), absi(dy)) != rad:
					continue
				var c := c0 + Vector2i(dx, dy)
				if Creep.on_creep(w, c):
					var d := Vector2(dx, dy).length_squared()
					if d < bd:
						bd = d
						best = Vector2(c) + Vector2(0.5, 0.5)
		if best != null:
			return best
	return null


static func _haul(w: SimWorld, e: Dictionary, p: Vector2, r: Dictionary, co: Array) -> void:
	var t7: Dictionary = e.t7
	if not t7.has("home") or (w.tick + int(e.id)) % 100 == 0:
		var h = _creep_home(w, p)
		if h != null:   # aim past the creep edge so the trailing cocoons end up on the creep too
			h = Vector2(h) + (Vector2(h) - p).normalized() * (float(r.get("haul_offset", 1.6)) + 2.0)
			h = Vector2(snappedf(h.x, Q), snappedf(h.y, Q))
		t7.home = h
	var dir := Vector2.RIGHT.rotated(float(e.get("facing", 0.0)))
	if t7.home != null and p.distance_to(t7.home) > 0.5:
		var np := p.move_toward(t7.home, float(r.get("haul_speed", 1.2)) / SimWorld.TICK_RATE)
		if Terrain.passable(w.terrain_at(w.cell_of(np)), "foot"):
			dir = (Vector2(t7.home) - p).normalized()
			e.facing = snappedf(dir.angle(), Q)
			_set_pos(w, e, np)
			p = np
		HotState.set_moving(w, int(e.id), false)
	var off := float(r.get("haul_offset", 1.6))
	for i in co.size():
		var c: Dictionary = w.entities[int(co[i])]
		var cp := p - dir.rotated((float(i) - 0.5 * float(co.size() - 1)) * 0.5) * off
		c.t7c.p = Vector2(snappedf(cp.x, Q), snappedf(cp.y, Q))


## Cocoons: held in place (or dragged), lost after lost_on_creep_s on creep, cut open by friendly soldiers.
static func _cocoons(w: SimWorld, s: Dictionary) -> void:
	var r := RK("weaver")
	var keep := []
	for cid in s.cocoons:
		var c = w.entities.get(int(cid))
		if c == null or not c.has("t7c"):
			continue
		var tc: Dictionary = c.t7c
		var cp: Vector2 = tc.p
		if _pos(w, c) != cp:
			_set_pos(w, c, cp)
		HotState.set_moving(w, int(cid), false)
		if _cd(c) < 2:
			HotState.set_cd(w, int(cid), 2)
		if Creep.on_creep(w, w.cell_of(cp)):
			tc.on = int(tc.on) + 1
			if int(tc.on) >= _t(float(r.get("lost_on_creep_s", 4.0))):
				w.emit("CocoonLost", {"id": int(cid), "owner": int(c.owner), "by": int(tc.by), "pos": cp})
				w.destroy(int(cid), "cocoon_lost")
				continue
		else:
			tc.on = 0
		if (w.tick + int(cid)) % 5 == 0:
			var fast: Array = r.get("fast_roles", [])
			var rate := 0.0
			var by := -1
			for u in _friendly_helpers(w, int(c.owner), cp, float(r.get("cut_radius", 1.4)), int(cid)):
				var role := String(Content.unit(String(u.def)).get("cn_role", ""))
				rate += 1.0 / maxf(float(r.get("cut_s_fast" if fast.has(role) else "cut_s_slow", 14.0)), 0.1)
				if by < 0:
					by = int(u.id)
			if rate > 0.0:
				tc.cut = snappedf(float(tc.cut) + rate * 5.0 / SimWorld.TICK_RATE, Q)
				if float(tc.cut) >= 1.0:
					c.erase("t7c")
					c.order = {"type": "idle"}
					HotState.touch(w, int(cid))
					w.emit("CocoonCut", {"id": int(cid), "owner": int(c.owner), "by": by, "pos": cp})
					continue
		keep.append(int(cid))
	s.cocoons = keep


## Web slow expiry and wrecked-part effects on vehicles.
static func _vehicles(w: SimWorld, s: Dictionary) -> void:
	var keep := []
	for vid in s.slowed:
		var v = w.entities.get(int(vid))
		if v == null:
			continue
		if v.has("t7mv_until") and w.tick >= int(v.t7mv_until):
			v.erase("t7mv")
			v.erase("t7mv_until")
		_part_effects(w, v)
		if v.has("t7mv") or v.has("t7w"):
			keep.append(int(vid))
	s.slowed = keep


# ================================================================ system entry points
static func tick(w: SimWorld) -> void:
	var s = st(w)
	var every := maxi(int(RT().get("scan_every", 50)), 1)
	if s == null:
		if Creep.enabled(w) and w.tick % every == 0:
			_scan(w)
			_waves(w)
		return
	if w.tick % every == 0:
		_scan(w)
	_waves(w)
	var ai := not w.ai_state.is_empty()
	var think := maxi(int(RT().get("think_every", 20)), 1)
	var live := []
	for id in (s.ids as Array).duplicate():
		var e = w.entities.get(int(id))
		if e == null or not e.has("t7"):
			continue
		live.append(int(id))
		if held(w, e):
			continue
		var p := _pos(w, e)
		match String(e.t7.k):
			"burrower": _burrower(w, s, e, p)
			"spitter": _spitter(w, s, e, p)
			"mimic": _mimic(w, s, e, p)
			"packhunter": _packhunter(w, s, e, p)
			"leech": _leech(w, s, e, p)
			"weaver": _weaver(w, s, e, p)
		if ai and (w.tick + int(id)) % think == 0 and w.ai_state.has(int(e.owner)) and w.entities.has(int(id)):
			_think(w, s, e)
	for id in s.ids:
		if not live.has(int(id)) and w.entities.has(int(id)):
			live.append(int(id))
	live.sort()
	s.ids = live
	if not (s.cocoons as Array).is_empty():
		_cocoons(w, s)
	if not (s.slowed as Array).is_empty():
		_vehicles(w, s)


## Adopts threat units placed by others (map, MachineReact7 waves) on Machine sides.
static func _scan(w: SimWorld) -> void:
	var ubo := SimIndex.units_by_owner(w)
	for fid in Creep.machine_fids(w):
		for e in ubo.get(fid, []):
			if not e.has("t7") and w.entities.has(int(e.id)) and kind_of(String(e.def)) != "":
				adopt(w, int(e.id))


## Extra threat units per escalation wave (rules waves[unit tier]) for AI-run Machine sides, own timer.
static func _waves(w: SimWorld) -> void:
	if w.sys_state.get("cores") == null or w.ai_state.is_empty():
		return
	var pi := Cores.phase_info(w)
	var every := roundi(float(pi.get("wave_every_s", 0)) * SimWorld.TICK_RATE)
	var s = st(w)
	if every <= 0 or w.tick - (0 if s == null else int(s.wave_t)) < every:
		return
	var defs: Array = RT().get("waves", {}).get(str(int(pi.get("unit_tier", 1))), [])
	if defs.is_empty():
		return
	for fid in Creep.machine_fids(w):
		if not w.ai_state.has(fid) or not bool(w.factions[fid].alive):
			continue
		var blds := []
		for b in SimIndex.of(w, "building"):
			if int(b.owner) == fid and w.entities.has(int(b.id)):
				blds.append(b)
		if blds.is_empty():
			continue
		var n := 0
		for i in defs.size():
			var b: Dictionary = blds[i % blds.size()]
			var off := Vector2(float(int(b.get("size", 2))) + 1.5, 0.0).rotated(TAU * float(i) / 8.0 + 0.4)
			if spawn(w, String(defs[i]), fid, (b.pos as Vector2) + off) >= 0:
				n += 1
		if n > 0:
			w.emit("ThreatWave", {"fid": fid, "phase": int(pi.get("n", 0)), "units": n})
	_st(w).wave_t = w.tick


# ================================================================ AI (AI-run Machine sides)
static func _go(w: SimWorld, e: Dictionary, to: Vector2) -> void:
	var last = e.t7.get("goto")
	if last != null and Vector2(last).distance_to(to) < 2.0 and HotState.get_moving(w, int(e.id)):
		return
	var to2 := Vector2(snappedf(to.x, Q), snappedf(to.y, Q))
	var r := w.submit({"type": "move", "issuer": int(e.owner), "unit_ids": [int(e.id)], "target": to2})
	if bool(r.get("ok", false)):
		e.t7.goto = to2


## Fog-legal targets of fid (visible enemy ground units, ascending id), cached per tick.
static func _seen(w: SimWorld, fid: int) -> Array:
	var key := "t7_seen_%d" % fid
	var c = w.cache.get(key)
	if c != null and int(c.t) == w.tick:
		return c.v
	var out := []
	for u in w.visible_enemies(fid):
		if u.kind == "unit" and not bool(Content.unit(String(u.def)).get("is_air", false)) and not u.has("t7c"):
			out.append(u)
	out.sort_custom(func(a, b): return int(a.id) < int(b.id))
	w.cache[key] = {"t": w.tick, "v": out}
	return out


static func _is_cn(u: Dictionary) -> bool:
	# ORCH (CNROLE7 audit): the old g7_b_ prefix also caught Human B Sentinels, drones and facility engineers;
	# CnRole7.is_cn is the one definition of a counter-nanite strike / tactical unit (13.9c-29)
	return preload("res://sim/systems/cn_role7.gd").is_cn(u)


## Closest visible enemy within r preferring CN units, then the filter (veh / sol / any).
static func _pick(w: SimWorld, e: Dictionary, p: Vector2, r: float, want: String) -> Variant:
	var pref := []
	var rest := []
	for u in _seen(w, int(e.owner)):
		if p.distance_to(Vector2(u.pos)) > r:
			continue
		if (want == "veh" and not is_vehicle(u)) or (want == "sol" and not is_soldier(u)):
			continue
		(pref if _is_cn(u) else rest).append(u)
	var t = closest(pref, p)
	return t if t != null else closest(rest, p)


static func _think(w: SimWorld, s: Dictionary, e: Dictionary) -> void:
	var p := _pos(w, e)
	var lr: Array = Cores.MachineReact7.learned(w)
	var reach := 1.0e9 if lr.has(2) else 50.0
	match String(e.t7.k):
		"burrower":
			if not is_burrowed(e):
				return
			var t = _pick(w, e, p, reach, "veh")
			if t == null:
				t = _pick(w, e, p, 30.0, "sol")
			if t != null:
				_go(w, e, Vector2(t.pos))
			elif lr.has(1):
				var cs = Creep.st(w)
				if cs != null and not (cs.sites as Array).is_empty():
					_go(w, e, Vector2(cs.sites[cs.sites.size() - 1].pos))
		"spitter":
			var t = _pick(w, e, p, reach, "sol")
			if t != null:
				var tp := Vector2(t.pos)
				var kr := float(RK("spitter").get("keep_range", 7.0))
				if p.distance_to(tp) > kr + 1.0 or p.distance_to(tp) < kr - 3.0:
					_go(w, e, tp + (p - tp).normalized() * kr)
		"mimic":
			_think_mimic(w, e, p, lr)
		"packhunter":
			_think_pack(w, s, e, p, reach)
		"leech":
			if not e.has("leech_on"):
				var t = _pick(w, e, p, maxf(float(RK("leech").get("seek_radius", 14.0)), minf(reach, 40.0)), "veh")
				if t != null:
					_go(w, e, Vector2(t.pos))
		"weaver":
			if (e.t7.get("co", []) as Array).is_empty():
				var t = _pick(w, e, p, minf(reach, 30.0), "sol")
				if t != null:
					_go(w, e, Vector2(t.pos))


static func _think_mimic(w: SimWorld, e: Dictionary, p: Vector2, lr: Array) -> void:
	if not is_disguised(e):
		var t = _pick(w, e, p, 20.0, "")
		if t != null:
			_go(w, e, Vector2(t.pos))
		return
	var t = _pick(w, e, p, 60.0, "")
	if lr.has(3) or t == null:
		var mem: Dictionary = w.memory.get(int(e.owner), {})
		var keys := mem.keys()
		keys.sort()
		for k in keys:
			if String(mem[k].get("def", "")).contains("facility"):
				e.t7.go = p.distance_to(Vector2(mem[k].pos)) < 8.0
				_go(w, e, Vector2(mem[k].pos))
				return
	if t != null:
		e.t7.go = p.distance_to(Vector2(t.pos)) < 6.0
		_go(w, e, Vector2(t.pos))


## Packs of 4-6: idle packhunters near each other form a pack; members take flank slots around the pack target.
static func _think_pack(w: SimWorld, s: Dictionary, e: Dictionary, p: Vector2, reach: float) -> void:
	var r := RK("packhunter")
	var pk := int(e.t7.get("pk", 0))
	if pk == 0:
		var mates := [e]
		for u in near(w, p, 12.0):
			if int(u.id) != int(e.id) and int(u.owner) == int(e.owner) and u.has("t7") \
					and String(u.t7.k) == "packhunter" and int(u.t7.get("pk", 0)) == 0:
				mates.append(u)
		var sz: Array = r.get("pack", [4, 6])
		if mates.size() < int(sz[0]):
			return
		pk = int(s.next_pk)
		s.next_pk = pk + 1
		mates = mates.slice(0, int(sz[1]))
		for i in mates.size():
			mates[i].t7.pk = pk
			mates[i].t7.slot = i
			mates[i].t7.n = mates.size()
		w.emit("PackFormed", {"pk": pk, "owner": int(e.owner), "units": mates.size()})
	if not s.has("pkt"):
		s.pkt = {}
	var key := str(pk)
	var t = w.entities.get(int(s.pkt.get(key, -1)))
	if t == null or not w.is_enemy(int(e.owner), int(t.owner)) or t.has("t7c"):
		t = _pick(w, e, p, reach, "veh")
		if t == null:
			t = _pick(w, e, p, minf(reach, 30.0), "")
		s.pkt[key] = -1 if t == null else int(t.id)
	if t == null:
		return
	var tp := Vector2(t.pos)
	if p.distance_to(tp) <= float(r.get("close_radius", 6.5)):
		_go(w, e, tp)
		return
	var base := float(t.get("facing", 0.0)) + PI
	var ang := base + TAU * float(e.t7.get("slot", 0)) / float(maxi(int(e.t7.get("n", 1)), 1))
	_go(w, e, tp + Vector2.RIGHT.rotated(ang) * float(r.get("flank_radius", 5.0)))


# ================================================================ commands (ORCH registers t7_pry / t7_cut)
static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var typ := String(cmd.get("type", ""))
	var fid := int(cmd.get("issuer", -1))
	var ids: Array = cmd.get("unit_ids", [])
	if ids.is_empty():
		return "No units selected."
	for id in ids:
		var u = w.entities.get(int(id))
		if u == null or int(u.owner) != fid or not is_soldier(u):
			return "Only your own soldiers can do that."
	var t = w.entities.get(int(cmd.get("target", -1)))
	if t == null:
		return "Target is missing."
	if int(t.owner) != fid and not w.is_ally(int(t.owner), fid):
		return "Target is not friendly."
	match typ:
		"t7_pry":
			return "" if not leeches_on(w, int(t.id)).is_empty() else "No leech on that vehicle."
		"t7_cut":
			return "" if cocooned(t) else "That soldier is not cocooned."
	return "%s: unknown command" % typ


## Sends the soldiers next to the vehicle / cocoon; prying and cutting then run in tick().
static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var t = w.entities.get(int(cmd.get("target", -1)))
	if t == null:
		return
	var tp: Vector2 = t.t7c.p if t.has("t7c") else _pos(w, t)
	var mv := {"type": "move", "issuer": int(cmd.issuer), "unit_ids": cmd.unit_ids, "target": tp}
	if SimWorld.Movement.validate_command(w, mv) == "":
		SimWorld.Movement.apply_command(w, mv)
	w.emit("ThreatAssist", {"kind": String(cmd.type), "target": int(t.id), "units": (cmd.unit_ids as Array).size()})
