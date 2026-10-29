extends RefCounted
## G7 (CNOPS7): counter-nanite progression, master scope 6.10 + 13.4. Owner: CNOPS7.
## Named operators (name, call sign from CNSIM7's e.call_sign, kill / purge / wound record, scars), named teams
## ("Team Halcyon"), team XP (missions = completed purges, facility drills, kills) with levels; losing a veteran
## costs XP (and so levels); personalities (calm_veteran, nervous_rookie, joker, hardliner) with a voice index;
## bonds (pairs in the same squad who complete missions together); one signature skill per operator; specialist
## upgrade paths (cn_specialize: lab / workshop / medical).
## Content: content/g7/defs_g7_cnops.json rules.g7_cnops.progress (PROVISIONAL).
## State: w.sys_state.cnprog7 (string keys), created only once CNSIM7's cn7 state has a team, so a match without
## counter-nanite units never gets it (hash-identical). Saved and hashed with sys_state.
## Determinism: names / personalities / skills are pure functions of (seed, unit id) through String.hash();
## sorted iteration; staggered cadence; no w.rng.
## Events (AUDIO7 barks / OPSUI7 cards): CnOperatorsNamed {team, owner, name, ops:[{id,name,cs,pers,voice,skill}]},
##   CnBark {id, team, owner, call_sign, pers, voice, kind wounded|down|kill|hero|buddy_wounded|buddy_down|level},
##   CnBuddyCallout {id, buddy, team, owner, call_sign, buddy_cs, pers, kind wounded|down},
##   CnBondLoss {id, lost, team, owner, bond, morale_loss}, CnVeteranLost {id, team, owner, call_sign, xp_lost, level},
##   CnTeamLevel {team, owner, name, level, from}, CnTeamXp {team, owner, xp, why} (missions/drills only),
##   CnScar {id, team, owner, zone}, CnSpecialized {id, team, owner, path, tier}.

const VER := 1
const KEY := "cnprog7"
const PERS := ["calm_veteran", "nervous_rookie", "joker", "hardliner"]


static func R() -> Dictionary:
	return (Content.rules().get("g7_cnops", {}) as Dictionary).get("progress", {})


static func ticks(sec: float) -> int:
	return maxi(roundi(sec * SimWorld.TICK_RATE), 1)


static func state(w: SimWorld):
	return w.sys_state.get(KEY)


static func _st(w: SimWorld) -> Dictionary:
	var st = w.sys_state.get(KEY)
	if st == null:
		st = {"ver": VER, "ops": {}, "teams": {}, "bonds": {}, "hits": {}, "fxp": {}}
		w.sys_state[KEY] = st
	return st


## Deterministic pick in [0, n) from (seed, id, salt).
static func pick(w: SimWorld, id: int, salt: String, n: int) -> int:
	if n <= 0:
		return 0
	var h := ("%d:%d:%s" % [w.seed_value, id, salt]).hash() & 0xFFFFFFFF   # djb2: weak low bits, so mix
	h = (((h >> 16) ^ h) * 0x45d9f3b) & 0xFFFFFFFF
	h = (((h >> 16) ^ h) * 0x45d9f3b) & 0xFFFFFFFF
	h = (h >> 16) ^ h
	return h % n


# ================================================================ records
static func op(w: SimWorld, uid: int) -> Dictionary:
	var st = state(w)
	return {} if st == null else (st.ops as Dictionary).get(str(uid), {})


static func team_rec(w: SimWorld, tid: int) -> Dictionary:
	var st = state(w)
	return {} if st == null else (st.teams as Dictionary).get(str(tid), {})


static func _register_team(w: SimWorld, st: Dictionary, t: Dictionary) -> void:
	var tid := int(t.id)
	var tr := {"id": tid, "fid": int(t.fid), "name": "Team " + String(t.name), "kind": String(t.kind), "xp": 0.0, "lvl": 0,
		"missions": 0, "kills": 0, "vets_lost": 0, "lost": []}
	st.teams[str(tid)] = tr
	var P := R()
	var fn: Array = P.get("first_names", ["Sam"])
	var ln: Array = P.get("last_names", ["Doe"])
	var pw: Dictionary = P.get("personalities", {})
	var wsum := 0
	for p in PERS:
		wsum += int((pw.get(p, {}) as Dictionary).get("weight", 1))
	var named := []
	var used := {}
	for uid in t.members:
		var id := int(uid)
		var e = SimWorld.CounterNanite.find(w, id)
		var role := SimWorld.CounterNanite.role_of(e) if e != null else ""
		var r := pick(w, id, "pers", wsum)
		var pers := PERS[0]
		for p in PERS:
			r -= int((pw.get(p, {}) as Dictionary).get("weight", 1))
			if r < 0:
				pers = p
				break
		var sk: Array = (P.get("skills_by_role", {}) as Dictionary).get(role, ["eagle_eye"])
		var fi := pick(w, id, "fn", fn.size())
		var li := pick(w, id, "ln", ln.size())
		var nm := "%s %s" % [String(fn[fi]), String(ln[li])]
		var tries := 0
		while used.has(nm) and tries < ln.size():   # unique within the team
			tries += 1
			nm = "%s %s" % [String(fn[(fi + tries) % fn.size()]), String(ln[(li + 7 * tries) % ln.size()])]
		used[nm] = true
		var rec := {"id": id, "team": tid, "fid": int(t.fid), "role": role,
			"name": nm,
			"cs": String(e.get("call_sign", "")) if e != null else "", "sq": String(e.get("cn_sq", "A")) if e != null else "A",
			"pers": pers, "voice": pick(w, id, "voice", maxi(int((pw.get(pers, {}) as Dictionary).get("voices", 2)), 1)),
			"skill": String(sk[pick(w, id, "skill", sk.size())]) if not sk.is_empty() else "",
			"kills": 0, "purges": 0, "wounds": 0, "scars": [], "missions": 0, "path": "", "tier": 0,
			"alive": true, "hero": false, "bark": -100000, "co": -100000}
		st.ops[str(id)] = rec
		named.append({"id": id, "name": rec.name, "cs": rec.cs, "pers": pers, "voice": rec.voice, "skill": rec.skill})
	w.emit("CnOperatorsNamed", {"team": tid, "owner": int(t.fid), "name": tr.name, "ops": named})


## Registers every counter-nanite team not yet known (creates the state on the first team).
static func ensure(w: SimWorld) -> void:
	var cn = w.sys_state.get("cn7")
	if cn == null or (cn.teams as Dictionary).is_empty():
		return
	var st := _st(w)
	for tid in SimWorld.CounterNanite.team_ids(w):
		if not (st.teams as Dictionary).has(str(tid)):
			_register_team(w, st, cn.teams[tid])


# ================================================================ levels and XP
static func level_of_xp(xp: float) -> int:
	var lv := 0
	var lvls: Array = R().get("team_levels", [0])
	for i in lvls.size():
		if xp >= float(lvls[i]):
			lv = i
	return lv


static func level(w: SimWorld, tid: int) -> int:
	return int(team_rec(w, tid).get("lvl", 0))


static func _relevel(w: SimWorld, tr: Dictionary) -> void:
	var lv := level_of_xp(float(tr.xp))
	if lv != int(tr.lvl):
		var old := int(tr.lvl)
		tr.lvl = lv
		w.emit("CnTeamLevel", {"team": int(tr.id), "owner": int(tr.fid), "name": String(tr.name), "level": lv, "from": old})


static func add_xp(w: SimWorld, tid: int, amt: float, why: String) -> void:
	var tr := team_rec(w, tid)
	if tr.is_empty() or amt == 0.0:
		return
	tr.xp = maxf(0.0, snappedf(float(tr.xp) + amt, 0.001))
	if why != "kill":
		w.emit("CnTeamXp", {"team": tid, "owner": int(tr.fid), "xp": float(tr.xp), "why": why})
	_relevel(w, tr)


## Team-level speed factor for key arm | convoy | dismount (< 1 = faster / tighter). 1.0 without a record.
static func level_mult(w: SimWorld, tid: int, key: String) -> float:
	var fx := float((R().get("level_fx", {}) as Dictionary).get(key, 0.0))
	return maxf(0.3, 1.0 - fx * float(level(w, tid)))


## Arming-time factor for a CN team dict (CNSIM7 hook): team level x the best quick_arm / lab path among its
## live deployment specialists.
static func arm_mult(w: SimWorld, t: Dictionary) -> float:
	return level_mult(w, int(t.get("id", -1)), "arm") * minf(role_mult(w, t, "deploy", "arm"), role_mult(w, t, "purge", "arm"))


## Best (lowest) skill / path factor for key among the team's live operators of role (1.0 when none): e.g.
## role_mult(w, t, "scanner", "scan") for the scan phase, ("ew", "jam") for the jam phase (CNSIM7 hooks).
static func role_mult(w: SimWorld, t: Dictionary, role: String, key: String) -> float:
	var best := 1.0
	for uid in t.get("members", []):
		var o := op(w, int(uid))
		if not o.is_empty() and bool(o.alive) and String(o.role) == role:
			best = minf(best, skill_mult(w, int(uid), key))
	return best


# ================================================================ skills, bonds
static func skill(w: SimWorld, uid: int) -> String:
	return String(op(w, uid).get("skill", ""))


static func skill_label(key: String) -> String:
	return String(((R().get("skills", {}) as Dictionary).get(key, {}) as Dictionary).get("label", key))


## Product of the operator's signature skill and specialist-path factors for key (arm, scan, jam, cut, exposure,
## dismount < 1 = faster / less; gunner_acc, heal_mult > 1 = better; sight_add, heal_hp additive -> 0 default).
## Returns 1.0 (0.0 for additive keys) for anyone without a record.
static func skill_mult(w: SimWorld, uid: int, key: String) -> float:
	var add := key == "sight_add" or key == "heal_hp"
	var o := op(w, uid)
	var v := 0.0 if add else 1.0
	if o.is_empty():
		return v
	var s: Dictionary = (R().get("skills", {}) as Dictionary).get(String(o.skill), {})
	if s.has(key):
		v = v + float(s[key]) if add else v * float(s[key])
	if String(o.path) != "" and int(o.tier) > 0:
		var tiers: Array = ((R().get("spec_paths", {}) as Dictionary).get(String(o.path), {}) as Dictionary).get("tiers", [])
		if int(o.tier) - 1 < tiers.size():
			var T: Dictionary = tiers[int(o.tier) - 1]
			if T.has(key):
				v = v + float(T[key]) if add else v * float(T[key])
	return v


static func _bkey(a: int, b: int) -> String:
	return "%d_%d" % [mini(a, b), maxi(a, b)]


static func bond(w: SimWorld, a: int, b: int) -> int:
	var st = state(w)
	return 0 if st == null else int((st.bonds as Dictionary).get(_bkey(a, b), 0))


## The live teammate this operator is closest to (highest bond >= 1, ties -> lower id); -1 if none.
static func buddy_of(w: SimWorld, uid: int) -> int:
	var o := op(w, uid)
	if o.is_empty():
		return -1
	var t = SimWorld.CounterNanite.team(w, int(o.team))
	if t == null:
		return -1
	var best := -1
	var bb := 0
	var ids: Array = (t.members as Array).duplicate()
	ids.sort()
	for m in ids:
		var mid := int(m)
		if mid == uid or not SimWorld.CounterNanite.alive(w, mid):
			continue
		var b := bond(w, uid, mid)
		if b > bb:
			bb = b
			best = mid
	return best


# ================================================================ reactions (events of this tick)
static func _live_e(w: SimWorld, uid: int):
	return w.entities.get(uid)   # on the map (not riding); null otherwise


static func _bark(w: SimWorld, o: Dictionary, kind: String, about: int = -1) -> void:
	if w.tick - int(o.bark) < ticks(float(R().get("bark_cd_s", 6))) and kind != "hero":
		return
	o.bark = w.tick
	w.emit("CnBark", {"id": int(o.id), "team": int(o.team), "owner": int(o.fid), "call_sign": String(o.cs),
		"pers": String(o.pers), "voice": int(o.voice), "kind": kind, "about": about})


## A buddy (bond >= 1, alive, within bond_near) calls out o's wound / fall.
static func _callout(w: SimWorld, o: Dictionary, kind: String) -> void:
	var bid := buddy_of(w, int(o.id))
	if bid < 0:
		return
	var b := op(w, bid)
	var be = _live_e(w, bid)
	var oe = _live_e(w, int(o.id))
	if b.is_empty() or be == null or oe == null:
		return
	if Vector2(be.pos).distance_to(Vector2(oe.pos)) > float(R().get("bond_near", 10.0)):
		return
	if w.tick - int(b.co) < ticks(float(R().get("callout_cd_s", 8))):
		return
	b.co = w.tick
	w.emit("CnBuddyCallout", {"id": bid, "buddy": int(o.id), "team": int(o.team), "owner": int(o.fid), "call_sign": String(b.cs),
		"buddy_cs": String(o.cs), "pers": String(b.pers), "kind": kind})
	_bark(w, b, "buddy_" + kind, int(o.id))


static func _is_vet(o: Dictionary) -> bool:
	return int(o.missions) >= int(R().get("vet_missions", 2)) or int(o.kills) >= int(R().get("vet_kills", 6))


static func _on_death(w: SimWorld, st: Dictionary, o: Dictionary) -> void:
	if not bool(o.alive):
		return
	o.alive = false
	var tr := team_rec(w, int(o.team))
	if tr.is_empty():
		return
	(tr.lost as Array).append(int(o.id))
	if _is_vet(o):
		var loss := float(R().get("vet_loss_xp", 35))
		tr.vets_lost = int(tr.vets_lost) + 1
		tr.xp = maxf(0.0, float(tr.xp) - loss)
		_relevel(w, tr)
		w.emit("CnVeteranLost", {"id": int(o.id), "team": int(o.team), "owner": int(o.fid), "call_sign": String(o.cs),
			"xp_lost": loss, "level": int(tr.lvl)})
	# close teammates take a morale hit (personality-scaled) and bark
	var close := int(R().get("bond_close", 2))
	var pw: Dictionary = R().get("personalities", {})
	var keys: Array = (st.ops as Dictionary).keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for k in keys:
		var y: Dictionary = st.ops[k]
		if int(y.team) != int(o.team) or not bool(y.alive) or int(y.id) == int(o.id):
			continue
		var b := bond(w, int(o.id), int(y.id))
		if b < close:
			continue
		var ml := float(R().get("bond_morale", 25.0)) * float((pw.get(String(y.pers), {}) as Dictionary).get("morale_loss", 1.0))
		var ye = SimWorld.CounterNanite.find(w, int(y.id))
		if ye != null and ye.has("morale"):
			ye.morale = maxf(0.0, float(ye.morale) - ml)
			if w.entities.has(int(y.id)):
				SimWorld.HotState.touch(w, int(y.id))
		w.emit("CnBondLoss", {"id": int(y.id), "lost": int(o.id), "team": int(o.team), "owner": int(o.fid), "bond": b,
			"morale_loss": ml, "call_sign": String(y.cs), "lost_cs": String(o.cs), "pers": String(y.pers)})
		_bark(w, y, "buddy_down", int(o.id))


static func _credit_kill(w: SimWorld, st: Dictionary, killer: int) -> void:
	var o := op(w, killer)
	var tid := -1
	if not o.is_empty():
		o.kills = int(o.kills) + 1
		tid = int(o.team)
		_bark(w, o, "kill")
	else:
		var a = w.entities.get(killer)
		if a != null and a.has("cn_team") and (st.teams as Dictionary).has(str(SimWorld.CounterNanite.team_of(a))):
			tid = SimWorld.CounterNanite.team_of(a)
	if tid < 0:
		return
	var tr := team_rec(w, tid)
	if tr.is_empty():
		return
	tr.kills = int(tr.kills) + 1
	add_xp(w, tid, float((R().get("xp", {}) as Dictionary).get("kill", 2)), "kill")


## A completed purge = one mission: XP, records, and +1 bond for every live pair in the same squad.
static func _on_mission(w: SimWorld, st: Dictionary, tid: int) -> void:
	var tr := team_rec(w, tid)
	var t = SimWorld.CounterNanite.team(w, tid)
	if tr.is_empty() or t == null:
		return
	tr.missions = int(tr.missions) + 1
	var live := []
	for uid in t.members:
		var o := op(w, int(uid))
		if not o.is_empty() and bool(o.alive) and SimWorld.CounterNanite.alive(w, int(uid)):
			o.missions = int(o.missions) + 1
			o.purges = int(o.purges) + 1
			live.append(o)
	for i in live.size():
		for j in range(i + 1, live.size()):
			if String(live[i].sq) == String(live[j].sq):
				var k := _bkey(int(live[i].id), int(live[j].id))
				st.bonds[k] = int((st.bonds as Dictionary).get(k, 0)) + 1
	add_xp(w, tid, float((R().get("xp", {}) as Dictionary).get("mission", 40)), "mission")


static func _events(w: SimWorld, st: Dictionary) -> void:
	for ev in w.events:
		match String(ev.type):
			"Damage":
				# G7 REGFIX7-4: a team member's hit is remembered at once. _sample_hits alone (every 10 ticks) lost the
				# credit for an enemy dropped within a few ticks of its first hit (WOUND7 zone kills: test_cnops7
				# test_xp_levels_and_veteran_loss saw the rifleman die 4 ticks after spawning, before any sample).
				var sh = w.entities.get(int(ev.get("shooter", -1)))
				if sh != null and sh.has("cn_team") and (st.teams as Dictionary).has(str(int(sh.cn_team))):
					var tg = w.entities.get(int(ev.get("target", -1)))
					if tg == null or w.is_enemy(int(sh.owner), int(tg.owner)):
						st.hits[str(int(ev.get("target", -1)))] = int(sh.id)
			"EntityDestroyed":
				var id := int(ev.get("id", -1))
				var o := op(w, id)
				if not o.is_empty():
					_on_death(w, st, o)
				var killer := int(ev.get("killer", (st.hits as Dictionary).get(str(id), -1)))
				st.hits.erase(str(id))
				if killer >= 0 and w.is_enemy(int(ev.get("owner", -1)), int(ev.get("killer_owner", -1))):
					_credit_kill(w, st, killer)
			"Wound":
				var o := op(w, int(ev.get("id", -1)))
				if o.is_empty() or not bool(o.alive):
					continue
				o.wounds = int(o.wounds) + 1
				var z := String(ev.get("zone", ""))
				if z != "" and not (o.scars as Array).has(z) and (o.scars as Array).size() < int(R().get("scars_max", 4)):
					(o.scars as Array).append(z)
					w.emit("CnScar", {"id": int(o.id), "team": int(o.team), "owner": int(o.fid), "zone": z})
				_bark(w, o, "wounded")
				_callout(w, o, "wounded")
			"Unconscious":
				var o := op(w, int(ev.get("id", -1)))
				if not o.is_empty() and bool(o.alive):
					_callout(w, o, "down")
			"CnPurge":
				if (st.teams as Dictionary).has(str(int(ev.get("team", -1)))):
					_on_mission(w, st, int(ev.team))
			"CnHeroDetonation":
				var o := op(w, int(ev.get("id", -1)))
				if not o.is_empty():
					o.hero = true
					_bark(w, o, "hero")


# ================================================================ periodic pass (every rules.progress.every ticks)
static func _team_ids_of(w: SimWorld, t: Dictionary) -> Dictionary:
	var s := {}
	for id in t.members:
		s[int(id)] = true
	for id in t.apcs:
		s[int(id)] = true
	return s


static func _anchor(w: SimWorld, t: Dictionary):
	for id in t.apcs:
		var a = w.entities.get(int(id))
		if a != null:
			return Vector2(a.pos)
	for id in t.members:
		var e = w.entities.get(int(id))
		if e != null:
			return Vector2(e.pos)
	return null


## Remembers which team member last hit each enemy near the team (kill credit when the death event has no killer).
static func _sample_hits(w: SimWorld, st: Dictionary, t: Dictionary) -> void:
	var c = _anchor(w, t)
	if c == null:
		return
	var mine := _team_ids_of(w, t)
	for u in SimWorld.G4bMech.near_units(w, c, 16.0):
		var la := int(u.get("last_attacker", -1))
		if la >= 0 and mine.has(la) and w.is_enemy(int(t.fid), int(u.owner)):
			st.hits[str(int(u.id))] = la
	if (st.hits as Dictionary).size() > 256:
		for k in (st.hits as Dictionary).keys():
			if not w.entities.has(int(k)):
				st.hits.erase(k)


static func _drills(w: SimWorld, st: Dictionary) -> void:
	var fs = w.sys_state.get("cn_facility")
	if fs == null:
		return
	var ks: Array = (fs.get("teams", {}) as Dictionary).keys()
	ks.sort_custom(func(a, b): return int(a) < int(b))
	for k in ks:
		var T: Dictionary = fs.teams[k]
		var tid := int(T.get("ext", 0))
		if not (st.teams as Dictionary).has(str(tid)):
			continue
		var cur := float(T.get("xp", 0.0))
		var d := cur - float((st.fxp as Dictionary).get(str(k), 0.0))
		if d >= 1.0:
			st.fxp[str(k)] = cur
			add_xp(w, tid, d * float((R().get("xp", {}) as Dictionary).get("drill_mult", 1.0)), "drill")


## Signature skill field_surgeon (and the medical path): heals wounded teammates on the map nearby.
static func _heal(w: SimWorld, st: Dictionary, t: Dictionary) -> void:
	var S: Dictionary = (R().get("skills", {}) as Dictionary).get("field_surgeon", {})
	var every := int(S.get("heal_every", 20))
	if (w.tick + int(t.id)) % every != 0:
		return
	var r := float(S.get("heal_r", 2.5))
	for uid in t.members:
		var hp_add := skill_mult(w, int(uid), "heal_hp")
		var m = w.entities.get(int(uid))
		if hp_add <= 0.0 or m == null:
			continue
		hp_add *= skill_mult(w, int(uid), "heal_mult")
		for vid in t.members:
			var v = w.entities.get(int(vid))
			if v == null or int(vid) == int(uid) or float(v.hp) <= 0.0 or float(v.hp) >= float(v.max_hp):
				continue
			if Vector2(v.pos).distance_to(Vector2(m.pos)) <= r:
				v.hp = minf(float(v.max_hp), float(v.hp) + hp_add)
				SimWorld.HotState.touch(w, int(vid))


static func tick(w: SimWorld) -> void:
	var cn = w.sys_state.get("cn7")
	if cn == null:
		return
	if state(w) == null and (cn.teams as Dictionary).is_empty():
		return
	ensure(w)
	var st = state(w)
	if st == null:
		return
	_events(w, st)
	var every := int(R().get("every", 10))
	for tid in SimWorld.CounterNanite.team_ids(w):
		var t: Dictionary = cn.teams[tid]
		if bool(t.get("dead", false)) or not (st.teams as Dictionary).has(str(tid)):
			continue
		_heal(w, st, t)
		if (w.tick + int(tid)) % every == 0:
			_sample_hits(w, st, t)
	if w.tick % every == 0:
		_drills(w, st)


# ================================================================ UI data (OPSUI7 team card)
static func team_card(w: SimWorld, tid: int) -> Dictionary:
	var tr := team_rec(w, tid)
	var t = SimWorld.CounterNanite.team(w, tid)
	if tr.is_empty() or t == null:
		return {}
	var lvls: Array = R().get("team_levels", [0])
	var lv := int(tr.lvl)
	var ms := []
	for uid in t.members:
		var o := op(w, int(uid))
		if o.is_empty():
			continue
		ms.append({"id": int(uid), "name": String(o.name), "cs": String(o.cs), "role": String(o.role), "pers": String(o.pers),
			"skill": String(o.skill), "skill_label": skill_label(String(o.skill)), "kills": int(o.kills), "purges": int(o.purges),
			"wounds": int(o.wounds), "scars": (o.scars as Array).duplicate(), "missions": int(o.missions), "alive": bool(o.alive),
			"hero": bool(o.hero), "buddy": buddy_of(w, int(uid)), "path": String(o.path), "tier": int(o.tier), "vet": _is_vet(o)})
	return {"team": tid, "name": String(tr.name), "level": lv, "xp": float(tr.xp),
		"next": float(lvls[lv + 1]) if lv + 1 < lvls.size() else -1.0, "missions": int(tr.missions), "kills": int(tr.kills),
		"vets_lost": int(tr.vets_lost), "members": ms}


# ================================================================ cn_specialize {issuer, unit_id, path}
static func spec_reason(w: SimWorld, fid: int, uid: int, path: String) -> String:
	var o := op(w, uid)
	if o.is_empty() or not bool(o.alive):
		return "Not a named operator."
	if int(o.fid) != fid:
		return "Not your operator."
	var P: Dictionary = (R().get("spec_paths", {}) as Dictionary).get(path, {})
	if P.is_empty():
		return "Unknown upgrade path."
	if not (P.get("roles", []) as Array).has(String(o.role)):
		return "This specialist can't take that path."
	if String(o.path) != "" and String(o.path) != path:
		return "Already on the %s path." % String(o.path)
	var tiers: Array = P.get("tiers", [])
	var nt := int(o.tier) if String(o.path) == path else 0
	if nt >= tiers.size():
		return "Path complete."
	if SimWorld.CnFacility.facilities(w, fid).is_empty():
		return "Needs a Counter-Nanite facility."
	var T: Dictionary = tiers[nt]
	if T.has("lab_tier") and SimWorld.CnFacility.package_tier(w, fid) < int(T.lab_tier):
		return "Needs package lab tier %d." % int(T.lab_tier)
	return w.can_afford(fid, T.get("cost", {}))


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	if String(cmd.get("type", "")) != "cn_specialize":
		return "Unknown command."
	return spec_reason(w, int(cmd.get("issuer", -1)), int(cmd.get("unit_id", -1)), String(cmd.get("path", "")))


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var fid := int(cmd.issuer)
	var uid := int(cmd.unit_id)
	var path := String(cmd.path)
	if spec_reason(w, fid, uid, path) != "":
		return
	var o := op(w, uid)
	var T: Dictionary = ((R().spec_paths as Dictionary)[path].tiers as Array)[int(o.tier) if String(o.path) == path else 0]
	if not w.spend(fid, T.get("cost", {}), "cn_specialize"):
		return
	o.tier = (int(o.tier) if String(o.path) == path else 0) + 1
	o.path = path
	w.emit("CnSpecialized", {"id": uid, "team": int(o.team), "owner": fid, "path": path, "tier": int(o.tier)})
