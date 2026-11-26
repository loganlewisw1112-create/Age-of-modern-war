class_name GhostConductor10
extends RefCounted
## G10 AI Conductor — Need → intel → workshop/suits/cohesion → template/package → lifecycle → echo.
## Player surface is intent-thin (mission card + ROE). Tick is public; ORCH wires world.gd later.

const Coalition10 = preload("res://sim/systems/coalition10.gd")
const GhostMission10 = preload("res://sim/systems/ghost_mission10.gd")
const GhostExo10 = preload("res://sim/systems/ghost_exo10.gd")

const KEY := "ghost_conductor10"
const VER := 1
const TEMPLATES := ["QuietDecap", "SensorBlind", "WorkshopStrike", "FeintStorm"]
const ROES := ["stealth", "standard", "aggressive"]


static func _rules() -> Dictionary:
	return Content.rules().get("g10_ghost", {})


static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		w.sys_state[KEY] = {
			"ver": VER,
			"factions": {},
			"active": [],
			"echoes": [],
			"conductor_hp": 100.0,
			"conductor_degraded": false,
		}
	return w.sys_state[KEY]


static func _side(w: SimWorld, fid: int) -> Dictionary:
	var st := _st(w)
	var k := str(fid)
	if not st.factions.has(k):
		st.factions[k] = {
			"intel_grade": "rumour",
			"workshop_ok": true,
			"suits_ready": 4,
			"cohesion": 70.0,
			"adaptations": [],
			"stance": "ghost",
			"abort_threshold": 0.4,
			"legend_pin": "",
			"learned": [],
		}
	return st.factions[k]


static func set_intel(w: SimWorld, fid: int, grade: String) -> void:
	var grades: Array = _rules().get("intel_grades", [])
	if not grades.has(grade):
		return
	_side(w, fid).intel_grade = grade
	if Coalition10.active(w, fid):
		var cs := Coalition10._side(w, fid)
		if not cs.is_empty():
			cs.intel_grade = grade


static func set_workshop(w: SimWorld, fid: int, ok: bool, suits: int = 4) -> void:
	var s := _side(w, fid)
	s.workshop_ok = ok
	s.suits_ready = maxi(suits, 0)


static func validate_command(w: SimWorld, cmd: Dictionary) -> String:
	var fid := int(cmd.get("issuer", -1))
	if not Coalition10.active(w, fid) or int(w.factions.get(fid, {}).get("stage", 0)) < 8:
		return "Ghost Command requires a Stage 8 Coalition side."
	if String(cmd.get("template", "")) not in TEMPLATES or String(cmd.get("roe", "")) not in ROES:
		return "Choose a valid mission card and rules of engagement."
	var st: Dictionary = w.sys_state.get(KEY, {})
	var side: Dictionary = st.get("factions", {}).get(str(fid), {})
	if int(side.get("last_mission", -1)) in st.get("active", []):
		return "A Ghost mission is already active."
	if not w.buildings_of(fid, "x_ghost_complex").any(func(site): return bool(site.get("built", false))):
		return "Build the Ghost Complex before launching a mission."
	if _ready_suits(w, fid).size() < 4:
		return "Field four healthy Ghost operators before launching a mission."
	if _field_contact(w, fid).is_empty() or _field_intel(w, fid, side) == "rumour":
		return "Scout an enemy structure to establish pattern intel."
	return ""


static func apply_command(w: SimWorld, cmd: Dictionary) -> void:
	var fid := int(cmd.issuer)
	var side := _side(w, fid)
	var suits := _ready_suits(w, fid)
	var contact := _field_contact(w, fid)
	set_workshop(w, fid, true, suits.size())
	set_intel(w, fid, _field_intel(w, fid, side))
	var base: Dictionary = w.buildings_of(fid, "x_ghost_complex").filter(func(site): return bool(site.get("built", false)))[0]
	contact["home"] = base.pos
	contact["unit_ids"] = suits.slice(0, 4)
	var result := submit_card(w, fid, {"template": String(cmd.template), "roe": String(cmd.roe),
		"target": String(cmd.get("target", "structure")), "field": contact})
	side.last_mission = int(result.get("mission_id", -1))


static func latest_player_mission(w: SimWorld, fid: int) -> Dictionary:
	var side: Dictionary = w.sys_state.get(KEY, {}).get("factions", {}).get(str(fid), {})
	var id := int(side.get("last_mission", -1))
	return GhostMission10.mission(w, id) if id >= 0 else {}


static func _ready_suits(w: SimWorld, fid: int) -> Array:
	var ids := []
	for e in w.units_of(fid):
		if GhostExo10.is_ghost_suit_def(String(e.def)) and not bool(e.get("wounded", false)) and float(e.hp) > float(e.max_hp) * 0.5:
			ids.append(int(e.id))
	ids.sort()
	return ids


static func _field_contact(w: SimWorld, fid: int) -> Dictionary:
	var home := Vector2(w.factions.get(fid, {}).get("spawn", Vector2.ZERO))
	var memory: Dictionary = w.memory.get(fid, {})
	var ids := memory.keys()
	ids.sort()
	var best := {}
	var distance := INF
	for id in ids:
		var e: Dictionary = memory[id]
		if not w.is_enemy(fid, int(e.get("owner", SimWorld.NEUTRAL))):
			continue
		var position := Vector2(e.get("pos", Vector2.ZERO))
		var d := position.distance_squared_to(home)
		if d < distance:
			distance = d
			best = {"id": int(id), "position": position, "name": String(Content.building(String(e.get("def", ""))).get("name", "enemy structure"))}
	return best


static func _field_intel(w: SimWorld, fid: int, side: Dictionary) -> String:
	var grade := String(side.get("intel_grade", "rumour"))
	if grade != "rumour":
		return grade
	for record in (w.memory.get(fid, {}) as Dictionary).values():
		if w.is_enemy(fid, int(record.get("owner", SimWorld.NEUTRAL))):
			return "pattern"
	return "rumour"


## Card → mission. Returns {ok, mission_id, reason, phase}.
static func submit_card(w: SimWorld, fid: int, card: Dictionary) -> Dictionary:
	if not Coalition10.active(w, fid):
		return {"ok": false, "reason": "Ghost Conductor is Coalition-only.", "mission_id": -1}
	var tmpl := String(card.get("template", "QuietDecap"))
	if not TEMPLATES.has(tmpl):
		return {"ok": false, "reason": "Unknown template %s (G10: QuietDecap/SensorBlind/WorkshopStrike/FeintStorm)." % tmpl, "mission_id": -1}
	var roe := String(card.get("roe", "stealth"))
	if not ROES.has(roe):
		return {"ok": false, "reason": "Unknown ROE.", "mission_id": -1}
	var side := _side(w, fid)
	var grade := String(card.get("intel_grade", side.get("intel_grade", "rumour")))
	var full := {
		"template": tmpl,
		"target": String(card.get("target", "officer")),
		"roe": roe,
		"intel_grade": grade,
		"workshop_ok": bool(side.get("workshop_ok", true)),
		"suits_ready": int(side.get("suits_ready", 4)),
		"cohesion": float(side.get("cohesion", 70.0)),
		"max_suit_loss": int(card.get("max_suit_loss", _rules().get("max_suit_loss", 2))),
		"risk_budget": int(card.get("risk_budget", _rules().get("risk_budget", 3))),
		"stance": String(card.get("stance", side.get("stance", "ghost"))),
	}
	if card.has("field"):
		full.field = (card.field as Dictionary).duplicate(true)
	var mid := GhostMission10.create(w, fid, full)
	var st := _st(w)
	var active: Array = st.get("active", [])
	active.append(mid)
	st.active = active
	# Run tasking immediately so callers see intel_gate next.
	GhostMission10.advance(w, mid)
	var m := GhostMission10.mission(w, mid)
	return {
		"ok": true,
		"mission_id": mid,
		"reason": "",
		"phase": String(m.get("phase", "tasking")),
	}


static func plan_package(w: SimWorld, mission_id: int) -> Dictionary:
	var m := GhostMission10.mission(w, mission_id)
	if m.is_empty():
		return {"ok": false, "reason": "Unknown mission."}
	# Ensure we reach / complete package phase.
	var guard := 0
	while String(m.get("phase", "")) != "package" and not bool(m.get("refused", false)) and guard < 20:
		GhostMission10.advance(w, mission_id)
		m = GhostMission10.mission(w, mission_id)
		guard += 1
	if bool(m.get("refused", false)):
		return {"ok": false, "reason": String(m.get("refuse_reason", "refused")), "refused": true}
	if String(m.get("phase", "")) == "package":
		GhostMission10.advance(w, mission_id)
		m = GhostMission10.mission(w, mission_id)
	var pkg: Dictionary = m.get("package", {})
	if pkg.is_empty():
		return {"ok": false, "reason": "Package not built."}
	return {"ok": true, "package": pkg.duplicate(true), "phase": String(m.get("phase", "")), "audit": String(pkg.get("audit", ""))}


static func mission(w: SimWorld, mission_id: int) -> Dictionary:
	return GhostMission10.mission(w, mission_id)


## Advance all active missions one step. GhostExo10.tick is owned by Exo.ghost_tick (avoid double drain).
static func tick(w: SimWorld) -> void:
	if not w.sys_state.has(KEY):
		return
	var st := _st(w)
	var still: Array = []
	for mid in st.get("active", []):
		var id := int(mid)
		var m := GhostMission10.mission(w, id)
		if m.is_empty() or bool(m.get("refused", false)) or bool(m.get("done", false)):
			if not m.is_empty() and bool(m.get("done", false)):
				var echoes: Array = st.get("echoes", [])
				echoes.append(m.get("echo", {}))
				st.echoes = echoes
			continue
		GhostMission10.advance(w, id)
		m = GhostMission10.mission(w, id)
		if bool(m.get("done", false)):
			var echoes2: Array = st.get("echoes", [])
			echoes2.append(m.get("echo", {}))
			st.echoes = echoes2
		elif not bool(m.get("refused", false)):
			still.append(id)
	st.active = still


## Run mission to echo (or refuse). Returns final mission snapshot.
static func run_to_echo(w: SimWorld, mission_id: int, max_steps: int = 64) -> Dictionary:
	var m := GhostMission10.mission(w, mission_id)
	var n := 0
	while n < max_steps:
		m = GhostMission10.mission(w, mission_id)
		if m.is_empty() or bool(m.get("refused", false)) or bool(m.get("done", false)):
			break
		if String(m.get("phase", "")) == "echo" and bool(m.get("done", false)):
			break
		GhostMission10.advance(w, mission_id)
		n += 1
	m = GhostMission10.mission(w, mission_id)
	# Final echo phase may need one more advance to mark done.
	if not m.is_empty() and String(m.get("phase", "")) == "echo" and not bool(m.get("done", false)):
		GhostMission10.advance(w, mission_id)
		m = GhostMission10.mission(w, mission_id)
	return m


## Staged Conductor takedown (ID 7): detected → EMP → breach → execute. Never zeros veteran doctrine.
static func disrupt_conductor(w: SimWorld, stage: String) -> Dictionary:
	var st := _st(w)
	match stage:
		"detect":
			return {"ok": true, "stage": "detect", "next": "emp"}
		"emp":
			st.conductor_hp = maxf(0.0, float(st.get("conductor_hp", 100.0)) - 35.0)
			st.conductor_degraded = true
			return {"ok": true, "stage": "emp", "hp": float(st.conductor_hp), "next": "breach"}
		"breach":
			st.conductor_hp = maxf(0.0, float(st.get("conductor_hp", 100.0)) - 35.0)
			return {"ok": true, "stage": "breach", "hp": float(st.conductor_hp), "next": "execute"}
		"execute":
			st.conductor_hp = 0.0
			st.conductor_degraded = true
			return {
				"ok": true,
				"stage": "execute",
				"hp": 0.0,
				"effect": "local_doctrine",
				"note": "Veterans keep local squad doctrine; package coordination degrades.",
			}
	return {"ok": false, "reason": "Unknown disrupt stage."}


static func board(w: SimWorld, fid: int) -> Dictionary:
	if not Coalition10.active(w, fid):
		return {}
	var st: Dictionary = w.sys_state.get(KEY, {})
	var s: Dictionary = st.get("factions", {}).get(str(fid), {})
	return {
		"intel_grade": String(s.get("intel_grade", "rumour")),
		"workshop_ok": bool(s.get("workshop_ok", true)),
		"suits_ready": int(s.get("suits_ready", 0)),
		"cohesion": float(s.get("cohesion", 0.0)),
		"stance": String(s.get("stance", "ghost")),
		"abort_threshold": float(s.get("abort_threshold", 0.4)),
		"legend_pin": String(s.get("legend_pin", "")),
		"learned": (s.get("learned", []) as Array).duplicate(),
		"conductor_degraded": bool(st.get("conductor_degraded", false)),
	}
