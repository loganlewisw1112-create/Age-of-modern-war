extends SceneTree
## Builds content/scenarios/tutorial.rtsmap (owner: ED5, PLAN_G5 section 9). The tutorial is an ordinary
## editor scenario: placed entities, regions and chained triggers (each step = one trigger with `step`
## and `prompt`; when = [previous step fired, the step's condition]). Re-run after changing a step:
##   godot --headless --path . -s content/scenarios/make_tutorial.gd
## Prints the MapIO.validate issues (must be none) and exits.

const MapIO = preload("res://sim/map_io.gd")
const OUT := "res://content/scenarios/tutorial.rtsmap"
const MW := 64
const MH := 48

## [name, condition, prompt, done-message, extra actions]
static func steps() -> Array:
	return [
		["move", {"type": "unit_in_region", "region": "flag", "owner_slot": 0, "def": "recon"},
			"MOVE: select your Recon scout (left-click) and right-click inside the yellow flag area.", "Good. Units go where you right-click.", []],
		["gather", {"type": "stock_at_least", "slot": 0, "res": "salvage", "amount": 450},
			"GATHER: select an Engineer and right-click the salvage pile. Bring back 50 salvage.", "Salvage is coming in.", []],
		["build", {"type": "owns", "slot": 0, "def": "barracks", "count": 1},
			"BUILD: select an Engineer, open Build and place a Barracks near your HQ.", "Barracks ready.", []],
		["train", {"type": "owns", "slot": 0, "def": "rifleman", "count": 8},
			"TRAIN: select the Barracks and train a Rifle Squad.", "Squad trained.", []],
		["attack", {"type": "entity_destroyed", "tag": "outpost"},
			"ATTACK: select your riflemen and right-click the enemy militia to the east.", "Outpost cleared. Command sends 800 salvage for the Stage 8 advance.",
			[{"type": "grant", "slot": 0, "res": "salvage", "amount": 800}]],
		["stage", {"type": "stage_reached", "slot": 0, "stage": 8},
			"ADVANCE: your Stage 8 gates are met (research, officers, line units, refined ore, steady power, cost). Press Advance Stage and wait for Stage 8.", "Stage 8: air power unlocked. Command sends 1500 salvage for the air wing.",
			[{"type": "grant", "slot": 0, "res": "salvage", "amount": 1500}, {"type": "grant", "slot": 0, "res": "ore", "amount": 500}]],
		["walls", {"type": "owns", "slot": 0, "def": "a_wall", "count": 1},
			"WALLS: select an Engineer, pick Wall and drag a line.", "Wall up.", []],
		["load", {"type": "units_loaded", "slot": 0, "count": 1},
			"TRANSPORT: select riflemen and right-click the APC to board it.", "Troops aboard.", []],
		["unload", {"type": "unit_in_region", "region": "drop", "owner_slot": 0, "def": "rifleman"},
			"TRANSPORT: drive the APC to the blue drop zone and press Unload.", "Troops delivered.", []],
		["resupply", {"type": "auto_resupply", "slot": 0},
			"SUPPLY: select the Logistics Truck and switch Auto resupply on.", "The truck now refills nearby units.", []],
		["hangar", {"type": "owns", "slot": 0, "def": "a_hangar_light", "count": 1},
			"AIRFIELD: select the Airstrip and buy a Light Hangar. Wait for it to finish.", "Hangar ready.", []],
		["jet", {"type": "owns", "slot": 0, "def": "a_strike_jet", "count": 1},
			"AIRFIELD: train a Strike Jet at the Airstrip (the control tower clears jets to fly). It parks in the hangar.", "Jet on the apron.", []],
		["takeoff", {"type": "aircraft_airborne", "owner_slot": 0, "count": 1},
			"AIR: select the jet and press Take off.", "Wheels up.", []],
		["land", {"type": "aircraft_landed", "owner_slot": 0, "count": 1},
			"AIR: send the jet home (Rebase to the Airstrip) and watch it land.", "Landed and parked.", []],
		["evac_on", {"type": "auto_evac", "slot": 0},
			"MEDICAL: select the Ambulance and switch Auto evac on.", "A soldier is down near the ambulance!",
			[{"type": "spawn", "slot": 0, "def": "rifleman", "count": 1, "region": "aid", "wounded": true}]],
		["evac", {"type": "unit_evacuated", "owner_slot": 0, "count": 1},
			"MEDICAL: the ambulance picks up the wounded soldier and drives him to the Hospital.", "Soldier evacuated.", []],
	]


static func scenario() -> Dictionary:
	var trig := []
	var st := steps()
	for i in st.size():
		var s: Array = st[i]
		var when: Array = [s[1]]
		if i > 0:
			when = [{"type": "trigger_fired", "name": "step_%s" % st[i - 1][0]}, s[1]]
		var then: Array = [{"type": "message", "text": String(s[3]), "slot": 0}]
		then.append_array(s[4])
		trig.append({"id": "step_%s" % s[0], "name": "step_%s" % s[0], "step": i + 1, "prompt": String(s[2]),
			"when": when, "then": then, "once": true})
	trig.append({"id": "finish", "name": "finish", "when": [{"type": "trigger_fired", "name": "step_evac"}, {"type": "time_reached", "t": 0}],
		"then": [{"type": "message", "text": "Tutorial complete. Well done, Commander.", "slot": 0}, {"type": "win", "slot": 0}], "once": true})
	var hq_a := Content.role("human_a", "hq")
	var hq_b := Content.role("human_b", "hq")
	var ents: Array = [
		_b(hq_a, 0, 4, 22), _b("generator", 0, 4, 27), _b("generator", 0, 1, 27), _b("a_hospital", 0, 4, 32), _b("a_airstrip", 0, 14, 4), _b("depot", 0, 8, 30), _b("depot", 0, 10, 30), _b("a_air_tower", 0, 20, 4),
		_b(hq_b, 1, 56, 40),
		_u("engineer", 0, 9, 21), _u("engineer", 0, 9, 22), _u("engineer", 0, 9, 23),
		_u("recon", 0, 10, 26),
		_u("rifleman", 0, 12, 28), _u("rifleman", 0, 13, 28), _u("rifleman", 0, 12, 29), _u("rifleman", 0, 13, 29),
		_u("a_apc", 0, 15, 31), _u("logistics_truck", 0, 12, 34), _u("a_ambulance", 0, 16, 36)]
	for c in [Vector2i(34, 26), Vector2i(34, 27)]:
		var m := _u("b_militia", 1, c.x, c.y)
		m["tag"] = "outpost"
		ents.append(m)
	return {"name": "Tutorial", "author": "RTS: Age of Modern War", "start_packages": false,
		"description": "Learn the basics step by step: move, gather, build, train, attack, advance, walls, transports, supply, air and medical evac.",
		"players": [
			{"slot": 0, "faction": "human_a", "team": 0, "color": "#3d7fd1", "stage": 7, "credits": 20000,
				"stock": {"salvage": 400, "ore": 300}, "ai": false, "difficulty": "normal", "start": Vector2i(10, 24),
				"research": ["integrated_manufacturing", "combined_arms"],
				"stats": {"ore_refined": 600, "officers_trained": 1, "line_trained": 8, "power_ok_ticks": 1200}},
			{"slot": 1, "faction": "human_b", "team": 1, "color": "#c0473b", "stage": 7, "credits": 0, "stock": {},
				"ai": false, "difficulty": "normal", "start": Vector2i(58, 42)}],
		"entities": ents, "victory": {"victory": "hq_elimination"},
		"regions": [{"id": "flag", "name": "Flag", "rect": Rect2i(22, 22, 4, 4)},
			{"id": "drop", "name": "Drop zone", "rect": Rect2i(40, 8, 5, 5)},
			{"id": "aid", "name": "Casualty", "rect": Rect2i(17, 38, 3, 3)}],
		"triggers": trig}


static func map() -> Dictionary:
	var t := PackedByteArray()
	t.resize(MW * MH)
	t.fill(Terrain.GRASS)
	for y in MH:   # a road east from the base, a forest belt to the north-east
		t[y * MW + 30] = Terrain.ROAD if y != 0 else Terrain.GRASS
	for x in range(10, 56):
		t[24 * MW + x] = Terrain.ROAD
	for y in range(30, 36):
		for x in range(44, 52):
			t[y * MW + x] = Terrain.FOREST
	return {"w": MW, "h": MH, "terrain": t, "decor": [], "bridges": [], "hold_bridge": 0,
		"resources": [{"res": "salvage", "amount": 3000, "cell": Vector2i(16, 22)},
			{"res": "salvage", "amount": 3000, "cell": Vector2i(17, 26)}]}


static func _b(def: String, slot: int, x: int, y: int) -> Dictionary:
	return {"kind": "building", "def": def, "owner_slot": slot, "cell": Vector2i(x, y), "facing": 0.0, "built": true}


static func _u(def: String, slot: int, x: int, y: int) -> Dictionary:
	return {"kind": "unit", "def": def, "owner_slot": slot, "cell": Vector2i(x, y), "facing": 0.0}


func _init() -> void:
	Content.load_all()
	var m := map()
	var sc := scenario()
	var issues := MapIO.validate(m, sc)
	for i in issues:
		print("TUTORIAL ISSUE %s %s" % [i.code, i.msg])
	var err := MapIO.save(OUT, m, sc)
	print("TUTORIAL saved=%s issues=%d steps=%d" % [err == "", issues.size(), steps().size()])
	quit(0 if err == "" and issues.is_empty() else 1)
