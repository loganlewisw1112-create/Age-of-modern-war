extends RefCounted
## G7 OPSUI7: read-only data model for the operations room (G7_REFERENCE master scope 6.11, 13.6, 13.7, 13.1).
## Every function here only READS the world (no sys_state key is ever created: CnFacility.st / Air._st / CN._st are
## never called), so opening any operations screen leaves w.state_hash() unchanged (tests/test_opsui7.gd checks it).
## Callers: ops_panel.gd (operations panel + hub), deploy_tracker.gd, strat_map.gd, war_table.gd, team_cam.gd,
## team_card.gd, protocol_advisor.gd, codex.gd and the playtest flow tools/pt7_opsui7.gd.

const CN = preload("res://sim/systems/counter_nanite.gd")
const CnFacility = preload("res://sim/systems/cn_facility.gd")
const CnOps7 = preload("res://sim/systems/cn_ops7.gd")
const CnProgress7 = preload("res://sim/systems/cn_progress7.gd")
const Creep = preload("res://sim/systems/creep.gd")
const Cores = preload("res://sim/systems/cores.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const Fog = preload("res://sim/systems/fog.gd")
const HotState = preload("res://sim/hot_state.gd")
const Air = preload("res://sim/systems/air.gd")
const Apc7 = preload("res://sim/systems/apc7.gd")

const GRID_N := 10                    # map sectors per axis: columns A..J, rows 1..10 ("grid D4")
const PHASES := ["scan", "jam", "arm"]
const PHASE_NAME := {"scan": "SCANNING", "jam": "JAMMING", "arm": "ARMING", "hero": "HERO DETONATION", "park": "DISMOUNTING"}
const STALL_TEXT := {"no_scanner": "no scanner on site", "no_ew": "no EW specialist on site", "no_deployer": "no deployer on site",
	"dome_down": "dome down", "apc_lost": "APC lost"}
const FAC_PHASE := {"garage": "IN GARAGE", "to_pad": "TO PAD", "loading": "LOADING", "to_gate": "ROLLING OUT", "out": "IN FIELD",
	"returning": "RETURNING", "to_garage": "TO GARAGE"}
const INCOMING_R := 34.0              # tiles around a deployment site watched for incoming forces
const DROPSHIP_DEFS := ["cn_stealth_dropship", "a_vtol_dropship", "b_vtol_dropship"]


# ---------------------------------------------------------------- small helpers
static func grid_ref(w: SimWorld, pos: Vector2) -> String:
	if w == null:
		return "--"
	var cw := maxf(float(w.map.w) / float(GRID_N), 1.0)
	var ch := maxf(float(w.map.h) / float(GRID_N), 1.0)
	var cx := clampi(int(pos.x / cw), 0, GRID_N - 1)
	var cy := clampi(int(pos.y / ch), 0, GRID_N - 1)
	return "%s%d" % [char(65 + cx), cy + 1]


static func fmt_s(s: float) -> String:
	var t := maxi(int(ceil(s)), 0)
	if t >= 3600:
		return "%d:%02d:%02d" % [t / 3600, (t / 60) % 60, t % 60]
	return "%d:%02d" % [t / 60, t % 60]


static func pretty(id: String) -> String:
	return id.replace("g7_b_", "").replace("g7_", "").replace("a_", "").replace("b_", "").replace("_", " ").capitalize()


static func hp_frac(w: SimWorld, e: Dictionary) -> float:
	var mx := maxf(float(e.get("max_hp", 1.0)), 1.0)
	var hp: float = HotState.get_hp(w, int(e.id)) if String(e.kind) == "unit" else float(e.get("hp", mx))
	return clampf(hp / mx, 0.0, 1.0)


static func cn_rules() -> Dictionary:
	return Content.rules().get("g7_cn", {})


static func package_kinds() -> Array:
	var ks: Array = (cn_rules().get("packages", {}) as Dictionary).keys()
	ks.sort()
	return ks


## Does side fid have anything the operations room can show (a counter-nanite team, facility or Last Protocol)?
static func has_ops(w: SimWorld, fid: int) -> bool:
	if w == null:
		return false
	if LastProtocol.active(w) or not CnFacility.facilities(w, fid).is_empty():
		return true
	for tid in CN.team_ids(w):
		var t = CN.team(w, int(tid))
		if t != null and int(t.fid) == fid:
			return true
	return false


## Team ids of side fid (ascending), dead teams last.
static func team_ids(w: SimWorld, fid: int) -> Array:
	var live := []
	var dead := []
	for tid in CN.team_ids(w):
		var t = CN.team(w, int(tid))
		if t == null or int(t.fid) != fid:
			continue
		if bool(t.get("dead", false)) or CN.live_members(w, t).is_empty() and CN.live_apcs(w, t).is_empty():
			dead.append(int(tid))
		else:
			live.append(int(tid))
	return live + dead


# ---------------------------------------------------------------- operations panel rows
## One summary per team: status, location, breaches, stock, drone, calls, level, deployment.
static func team_row(w: SimWorld, tid: int) -> Dictionary:
	var t = CN.team(w, tid)
	if t == null:
		return {}
	var mem: Array = CN.live_members(w, t)
	var apcs: Array = CN.live_apcs(w, t)
	var at = CnOps7.anchor(w, t)
	var breaches := 0
	var exp_max := 0.0
	var wounded := 0
	for id in mem:
		var e = CN.find(w, int(id))
		if e == null:
			continue
		if bool(e.get("wpunct", false)) and bool(e.get("suit", false)):
			breaches += 1
		exp_max = maxf(exp_max, float(e.get("cn_exp", 0.0)))
		if hp_frac(w, e) < 0.6:
			wounded += 1
	var apc_hp := 0.0
	for id in apcs:
		var a = CN.find(w, int(id))
		if a != null:
			apc_hp += hp_frac(w, a)
	apc_hp = apc_hp / float(apcs.size()) if not apcs.is_empty() else 0.0
	var stock := {}
	var lo: Dictionary = CN.loadout(w, tid)
	for aid in lo:
		for k in lo[aid]:
			stock[String(k)] = int(stock.get(String(k), 0)) + 1
	var did := CnOps7.drone_of(w, tid)
	var drone := {"id": did, "state": "NONE", "hp": 0.0}
	if did > 0:
		var de = w.entities.get(did)
		drone.state = "LOST" if de == null else "ALOFT"
		drone.hp = 0.0 if de == null else hp_frac(w, de)
	var ft: Dictionary = CnOps7.fac_team(w, tid)
	var dead: bool = bool(t.get("dead", false)) or (mem.is_empty() and apcs.is_empty())
	var dep: Dictionary = deployment(w, tid) if t.get("dep") != null else {}
	var status := "READY"
	if dead:
		status = "LOST"
	elif not dep.is_empty():
		status = String(dep.phase_name)
	elif t.get("eng") != null:
		status = "ENGAGED"
	elif not ft.is_empty() and String(ft.get("phase", "out")) != "out":
		status = String(FAC_PHASE.get(String(ft.phase), String(ft.phase).to_upper()))
	elif _moving(w, t):
		status = "EN ROUTE"
	elif not ft.is_empty():
		status = "IN FIELD"
	var lead = CN.find(w, int(t.leader)) if int(t.leader) >= 0 else null
	var tr: Dictionary = CnProgress7.team_rec(w, tid)
	return {"id": tid, "name": String(tr.get("name", "Team " + String(t.name))), "kind": String(t.kind),
		"kind_label": "STRIKE TEAM" if String(t.kind) == "strike" else "TACTICAL SQUAD",
		"pos": at if at != null else Vector2(-1, -1), "has_pos": at != null, "grid": grid_ref(w, at) if at != null else "--",
		"status": status, "dead": dead, "members": mem.size(), "members_total": (t.members as Array).size(),
		"apcs": apcs.size(), "apcs_total": (t.apcs as Array).size(), "apc_hp": apc_hp, "breaches": breaches,
		"exposure": exp_max, "wounded": wounded, "stock": stock, "drone": drone, "calls": CnOps7.calls_left(w, tid),
		"level": int(tr.get("lvl", 0)), "leader_cs": String(lead.get("call_sign", "")) if lead != null else "",
		"dep": dep, "engaged": t.get("eng") != null, "ids": mem + apcs}


static func _moving(w: SimWorld, t: Dictionary) -> bool:
	for id in t.apcs:
		var a = w.entities.get(int(id))
		if a != null and bool(a.get("moving", false)):
			return true
	return false


## Route of a team (anchor -> its destination) for maps and the advisor; [] when it is not travelling.
static func route(w: SimWorld, tid: int) -> Array:
	var t = CN.team(w, tid)
	if t == null:
		return []
	var at = CnOps7.anchor(w, t)
	if at == null:
		return []
	var dest = null
	if t.get("dep") != null and not bool(t.dep.get("dis", false)):
		dest = Vector2(t.dep.site)
	if dest == null:
		for id in t.apcs:
			var a = w.entities.get(int(id))
			if a == null:
				continue
			var o = a.get("order")
			if o is Dictionary and (o as Dictionary).has("target") and (o.target is Vector2):
				dest = Vector2(o.target)
				break
	if dest == null or Vector2(at).distance_to(Vector2(dest)) < 2.0:
		return []
	return [Vector2(at), Vector2(dest)]


## Facility stock of package kinds for side fid ({kind: n}) and the lab tier.
static func facility_stock(w: SimWorld, fid: int) -> Dictionary:
	var out := {}
	for id in CnFacility.facilities(w, fid):
		var F: Dictionary = CnFacility.fac(w, id)
		var st: Dictionary = F.get("stock", {})
		for k in st:
			out[String(k)] = int(out.get(String(k), 0)) + int(st[k])
	return out


## Dropships of side fid: [{id, def, name, phase, hp, cargo}].
static func dropships(w: SimWorld, fid: int) -> Array:
	var out := []
	var fl: Dictionary = Air.flights(w)
	var ks: Array = w.entities.keys()
	ks.sort()
	for id in ks:
		var e: Dictionary = w.entities[id]
		if String(e.kind) != "unit" or int(e.owner) != fid:
			continue
		var d := String(e.def)
		var hit := false
		for k in DROPSHIP_DEFS:
			if d.ends_with(k):
				hit = true
		if not hit:
			continue
		var ph := "ON PAD"
		if fl.has(int(id)):
			ph = String(fl[int(id)].get("phase", "flying")).to_upper().replace("_", " ")
		elif fl.has(str(id)):
			ph = String(fl[str(id)].get("phase", "flying")).to_upper().replace("_", " ")
		out.append({"id": int(id), "def": d, "name": "STEALTH DROPSHIP" if d.contains("stealth") else "VTOL DROPSHIP",
			"phase": ph, "hp": hp_frac(w, e), "cargo": (e.get("cargo", []) as Array).size(), "pos": Vector2(e.pos),
			"grid": grid_ref(w, Vector2(e.pos))})
	return out


# ---------------------------------------------------------------- deployment tracker
## Live deployment of team tid: {} when it is not deploying.
static func deployment(w: SimWorld, tid: int) -> Dictionary:
	var t = CN.team(w, tid)
	if t == null or t.get("dep") == null:
		return {}
	var d: Dictionary = t.dep
	var ph := String(d.get("phase", "scan"))
	var dis := bool(d.get("dis", false))
	var site := Vector2(d.site)
	var rate := float(SimWorld.TICK_RATE)
	var need_now := 1
	var prog := 0
	var left_ticks := 0
	var done_ticks := 0
	var total_ticks := 0
	if ph == "hero":
		left_ticks = maxi(int(d.get("hero_at", w.tick)) - w.tick, 0)
		total_ticks = 1
		done_ticks = 1
	else:
		var ix := PHASES.find(ph)
		for i in PHASES.size():
			var n: int = CN.need_ticks(w, t, String(PHASES[i]))
			total_ticks += n
			if i < ix:
				done_ticks += n
			elif i == ix:
				need_now = maxi(n, 1)
				prog = int(d.get("prog", 0)) if dis else 0
				done_ticks += prog
				left_ticks += n - prog
			else:
				left_ticks += n
	var dome := dome_state(w, t, site)
	var inc := incoming(w, int(t.fid), site)
	var shown := "park" if not dis and ph != "hero" else ph
	return {"team": tid, "site": site, "grid": grid_ref(w, site), "phase": ph, "phase_name": String(PHASE_NAME.get(shown, ph.to_upper())),
		"package": String(d.get("kind", "purge")), "phase_frac": clampf(float(prog) / float(need_now), 0.0, 1.0),
		"arm_frac": clampf(float(done_ticks) / maxf(float(total_ticks), 1.0), 0.0, 1.0) if ph != "hero" else 1.0,
		"time_left_s": float(left_ticks) / rate, "stalled": String(d.get("stalled", "")),
		"stall_text": String(STALL_TEXT.get(String(d.get("stalled", "")), String(d.get("stalled", "")))),
		"dismounted": dis, "dome": dome, "incoming": inc, "found": int(d.get("found", 0))}


## Best dome among the team's APCs near the site: {charge (0..1), on, broken, recharge_s}.
static func dome_state(w: SimWorld, t: Dictionary, site: Vector2) -> Dictionary:
	var best := {"charge": 0.0, "on": false, "broken": false, "recharge_s": 0.0, "has": false}
	for id in t.apcs:
		var a = w.entities.get(int(id))
		if a == null or not a.has("a7"):
			continue
		var cfg: Dictionary = Apc7.cfg_of(String(a.def))
		var full := float(cfg.get("dome", {}).get("charge", 1000.0)) if cfg.has("dome") else 1000.0
		var c := clampf(float(a.a7.get("dome", 0.0)) / maxf(full, 1.0), 0.0, 1.0)
		var near: bool = Vector2(a.pos).distance_to(site) <= 9.0
		var cd := maxi(int(a.a7.get("dome_cd", 0)) - w.tick, 0)
		var cand := {"charge": c, "on": bool(a.a7.get("dome_on", false)), "broken": c <= 0.0 and cd > 0,
			"recharge_s": float(cd) / float(SimWorld.TICK_RATE), "has": true}
		if not bool(best.has) or (near and (bool(cand.on) and not bool(best.on) or c > float(best.charge))):
			best = cand
	return best


## Hostile units side fid can see within INCOMING_R of p: {n, nearest, eta_s, kinds [[name, n]...], ids}.
static func incoming(w: SimWorld, fid: int, p: Vector2, r: float = INCOMING_R) -> Dictionary:
	var n := 0
	var nearest := INF
	var kinds := {}
	var ids := []
	var ks: Array = w.entities.keys()
	ks.sort()
	for id in ks:
		var e: Dictionary = w.entities[id]
		if String(e.kind) != "unit" or not w.is_enemy(fid, int(e.owner)):
			continue
		var dd := Vector2(e.pos).distance_to(p)
		if dd > r or not Fog.entity_visible(w, fid, e):
			continue
		n += 1
		ids.append(int(id))
		nearest = minf(nearest, dd)
		var nm := pretty(String(e.def))
		kinds[nm] = int(kinds.get(nm, 0)) + 1
	var kl := []
	for k in kinds:
		kl.append([k, kinds[k]])
	kl.sort_custom(func(a, b): return int(a[1]) > int(b[1]) or (int(a[1]) == int(b[1]) and String(a[0]) < String(b[0])))
	var spd := 1.6   # tiles/s: a typical Machine ground unit (display estimate only)
	return {"n": n, "nearest": nearest if n > 0 else -1.0, "eta_s": maxf(nearest - 4.0, 0.0) / spd if n > 0 else -1.0,
		"kinds": kl.slice(0, 4), "ids": ids}


# ---------------------------------------------------------------- Last Protocol countdown
## Countdown text with the projected real minutes (cd_left protocol-seconds / cd_rate = sim seconds at 1x speed).
static func lp_countdown(d: Dictionary) -> Dictionary:
	if d.is_empty():
		return {}
	var rate := maxf(float(d.get("cd_rate", 1.0)), 0.001)
	var real_s := float(d.get("cd_left", 0.0)) / rate
	return {"protocol": fmt_s(float(d.get("cd_left", 0.0))), "rate": rate, "real_s": real_s, "real_min": real_s / 60.0,
		"text": "PROTOCOL %s  x%.2f  =  ~%d real min" % [fmt_s(float(d.get("cd_left", 0.0))), rate, int(ceil(real_s / 60.0))]}
