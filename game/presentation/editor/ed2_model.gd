extends RefCounted
## ED2 scenario model (owner: ED2, CONTRACTS_G4 sections 5 + 9). Pure static helpers used by the
## ED2 editor tabs, the skirmish map browser and tests: content palette per faction, carrier cargo
## rules, placed-entity hit tests and formations, players -> cfg.sides, victory presets <-> the
## scenario victory block, trigger clause building (typed, in spec order), extra validation and
## the Test Play match config. No UI here.

const MapIO = preload("res://sim/map_io.gd")
const Victory = preload("res://sim/systems/victory.gd")
const EXTRA_COLORS := ["#8a63b5", "#3a9fa5", "#c7c7bd", "#d07a9a"]
const TEMP_PATH := "user://maps/_testplay.rtsmap"
const MAX_PLAYERS := 4
const MAX_FORMATION := 64
const CARGO_SIZES := {"foot": 1, "vehicle_light": 4, "vehicle_heavy": 8}

# victory presets (scenario victory block), with their params [key, kind, default]
const PRESETS := ["hq_elimination", "territory", "hold_bridge", "survive", "destroy_target", "reach_stage", "hold_point"]
const PRESET_LABELS := ["HQ elimination", "Territory %", "Hold the bridge", "Survive N seconds", "Destroy target (tag)", "Reach Stage N", "Hold point (region)"]
const PRESET_PARAMS := {
	"hq_elimination": [], "territory": [["percent", "int", 60]], "hold_bridge": [["seconds", "int", 300]],
	"survive": [["seconds", "int", 600]], "destroy_target": [["tag", "str", ""]], "reach_stage": [["stage", "int", 9]],
	"hold_point": [["region", "region", ""], ["seconds", "int", 180]]}

# trigger clauses (sim/systems/triggers.gd), params [key, kind, default]
const WHEN_SPEC := {
	"time_reached": [["t", "float", 60.0]],
	"unit_in_region": [["region", "region", ""], ["owner_slot", "slot_any", -1], ["count", "int", 1]],
	"entity_destroyed": [["tag", "str", ""]],
	"stage_reached": [["slot", "slot", 0], ["stage", "int", 9]],
	"units_below": [["slot", "slot", 0], ["n", "int", 1]],
	# G5 (ED5): triggers.gd G5 conditions (region "" = anywhere)
	"aircraft_landed": [["owner_slot", "slot", 0], ["count", "int", 1], ["region", "region", ""]],
	"unit_evacuated": [["owner_slot", "slot", 0], ["count", "int", 1]],
	"beach_landing": [["owner_slot", "slot", 0], ["count", "int", 1], ["region", "region", ""]],
	"aircraft_airborne": [["owner_slot", "slot", 0], ["count", "int", 1]],
	"owns": [["slot", "slot", 0], ["def", "def", ""], ["count", "int", 1]],
	"stock_at_least": [["slot", "slot", 0], ["res", "res", "credits"], ["amount", "int", 500]],
	"units_loaded": [["slot", "slot", 0], ["count", "int", 1]],
	"auto_resupply": [["slot", "slot", 0]], "auto_evac": [["slot", "slot", 0]],
	"trigger_fired": [["name", "str", ""]]}
const THEN_SPEC := {
	"message": [["text", "str", ""]],
	"spawn": [["slot", "slot", 0], ["def", "def", ""], ["count", "int", 1], ["region", "region", ""]],
	"reveal": [["slot", "slot", 0], ["region", "region", ""]],
	"grant": [["slot", "slot", 0], ["res", "res", "credits"], ["amount", "int", 500]],
	"win": [["slot", "slot", 0]], "lose": [["slot", "slot", 0]],
	"ai_target": [["slot", "slot", 1], ["region", "region", ""]]}
const WHEN_TYPES := ["time_reached", "unit_in_region", "entity_destroyed", "stage_reached", "units_below",
	"aircraft_landed", "unit_evacuated", "beach_landing", "aircraft_airborne", "owns", "stock_at_least",
	"units_loaded", "auto_resupply", "auto_evac", "trigger_fired"]
const THEN_TYPES := ["message", "spawn", "reveal", "grant", "win", "lose", "ai_target"]


# ------------------------------------------------------------------ palette
## Unit and building defs of a faction ("" = every faction), content order (incl. content/g4
## fragments: walls, G4b units, later air/naval). stage < 0 = every stage.
static func palette(faction: String, stage: int = -1) -> Dictionary:
	var out := {"units": [], "buildings": []}
	for kind in ["units", "buildings"]:
		for id in Content.ids(kind):
			var d: Dictionary = Content.table(kind)[id]
			if typeof(d) != TYPE_DICTIONARY or not d.has("faction"):
				continue
			if faction != "" and String(d.faction) != faction:
				continue
			if stage >= 0 and not Content.available(d, stage):
				continue
			out[kind].append(String(id))
	return out


static func def_label(kind: String, id: String) -> String:
	var d: Dictionary = Content.building(id) if kind == "building" else Content.unit(id)
	var tags: Array = []
	if kind == "building":
		tags.append("%dx%d" % [int(d.get("size", 1)), int(d.get("size", 1))])
		for f in ["is_hq", "wall", "gate", "tower"]:
			if bool(d.get(f, false)):
				tags.append(f.trim_prefix("is_").to_upper() if f == "is_hq" else f)
	else:
		tags.append(String(d.get("move_class", "foot")))
		if is_carrier(id):
			tags.append("carries %d" % int(d.cargo_slots))
	if int(d.get("stage_min", 7)) > 7:
		tags.append("St%d+" % int(d.stage_min))
	return "%s  (%s)" % [String(d.get("name", id)), ", ".join(PackedStringArray(tags))]


# ------------------------------------------------------------------ cargo (CONTRACTS_G4 section 7)
static func is_carrier(def: String) -> bool:
	return int(Content.unit(def).get("cargo_slots", 0)) > 0


static func cargo_class(def: String) -> String:
	var d := Content.unit(def)
	if d.has("cargo_class"):
		return String(d.cargo_class)
	return "foot" if String(d.get("move_class", "foot")) == "foot" else "vehicle_light"


static func cargo_size(def: String) -> int:
	var d := Content.unit(def)
	return int(d.get("cargo_size", CARGO_SIZES.get(cargo_class(def), 4)))


## "" when `add` fits into a carrier of `carrier_def` already holding `cargo`, else the reason.
static func cargo_reason(carrier_def: String, cargo: Array, add: String) -> String:
	if not is_carrier(carrier_def):
		return "%s cannot carry troops." % carrier_def
	var cd := Content.unit(carrier_def)
	if Content.unit(add).is_empty():
		return "Unknown unit '%s'." % add
	var accepts: Array = cd.get("cargo_accepts", ["foot"])
	if not accepts.has(cargo_class(add)):
		return "%s does not accept %s." % [String(cd.get("name", carrier_def)), cargo_class(add)]
	var used := 0
	for c in cargo:
		used += cargo_size(String(c))
	if used + cargo_size(add) > int(cd.cargo_slots):
		return "Carrier full (%d of %d slots used)." % [used, int(cd.cargo_slots)]
	return ""


# ------------------------------------------------------------------ placed entities
## G5 (ED5): "" when def may be placed at origin on this map (ground / water units on passable
## cells for their move class, shore and near-water buildings by Naval.shore_error), else the reason.
static func place_reason(map: Dictionary, kind: String, def: String, origin: Vector2i) -> String:
	var w := int(map.get("w", 0))
	var h := int(map.get("h", 0))
	var t = map.get("terrain", PackedByteArray())
	if typeof(t) != TYPE_PACKED_BYTE_ARRAY or (t as PackedByteArray).size() != w * h:
		return ""
	if origin.x < 0 or origin.y < 0 or origin.x >= w or origin.y >= h:
		return "Outside the map."
	if kind == "unit":
		var mc := String(MapIO.Movement.udef(def).mc)
		if not mc.begins_with("air") and not Terrain.passable(t[origin.y * w + origin.x], mc):
			return "%s cannot stand here (%s)." % [String(Content.unit(def).get("name", def)), mc]
		return ""
	var bd := Content.building(def)
	if bool(bd.get("shore", false)) or bd.has("near_water"):
		return MapIO._shore_reason(def, origin, t, w, h)
	return ""


static func make_entity(kind: String, def: String, slot: int, cell: Vector2i, facing: float = 0.0, built: bool = true) -> Dictionary:
	var e := {"kind": kind, "def": def, "owner_slot": slot, "cell": cell, "facing": facing}
	if kind == "building":
		e["built"] = built
	return e


static func ent_cell(e: Dictionary) -> Vector2i:
	if e.has("cell"):
		return MapIO._v2i(e.cell)
	var p := MapIO._v2(e.get("pos", Vector2.ZERO))
	return Vector2i(floori(p.x), floori(p.y))


static func footprint(e: Dictionary) -> Rect2i:
	var s := 1
	if String(e.get("kind", "unit")) == "building":
		s = int(Content.building(String(e.get("def", ""))).get("size", 1))
	return Rect2i(ent_cell(e), Vector2i(s, s))


## Index of the topmost (last placed) entity covering `cell`, or -1.
static func entity_at(ents: Array, cell: Vector2i) -> int:
	for i in range(ents.size() - 1, -1, -1):
		if footprint(ents[i]).has_point(cell):
			return i
	return -1


## Origins for a drag-box formation: a grid over a..b with step = footprint size, capped.
static func formation_cells(a: Vector2i, b: Vector2i, step: int, w: int, h: int) -> Array:
	var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	var hi := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
	var out: Array = []
	var st := maxi(1, step)
	var y := lo.y
	while y + st - 1 <= hi.y or (y == lo.y and out.is_empty()):
		var x := lo.x
		while x + st - 1 <= hi.x or x == lo.x:
			var c := Vector2i(x, y)
			if c.x >= 0 and c.y >= 0 and c.x + st <= w and c.y + st <= h:
				out.append(c)
				if out.size() >= MAX_FORMATION:
					return out
			x += st
		y += st
	return out


## Slot of the player whose start is closest to `cell` (ties: lower slot).
static func nearest_slot(players: Array, cell: Vector2i) -> int:
	var best := -1
	var bd := INF
	for p in players:
		var d := Vector2(MapIO._v2i(p.get("start", Vector2i.ZERO))).distance_squared_to(Vector2(cell))
		if d < bd:
			bd = d
			best = int(p.slot)
	return best


# ------------------------------------------------------------------ players
static func colors() -> Array:
	var out: Array = []
	for c in Content.rules().get("team_colors", []):
		out.append(String(c))
	for c in EXTRA_COLORS:
		if not out.has(c):
			out.append(c)
	return out


static func default_player(slot: int, start: Vector2i) -> Dictionary:
	var facs := Content.faction_ids()
	return {"slot": slot, "faction": String(facs[slot % facs.size()]) if not facs.is_empty() else "human_a", "team": slot,
		"color": String(colors()[slot % colors().size()]), "stage": 8,
		"credits": int(Content.rules().get("defaults", {}).get("starting_credits", 2500)),
		"stock": {}, "ai": slot != 0, "difficulty": "normal", "start": start}


## Start cells for slot 0..3 on a w x h map (corners, opposite pairs first).
static func corner_start(slot: int, w: int, h: int) -> Vector2i:
	var a := Vector2i(clampi(w / 6, 4, w - 5), clampi(h / 6, 4, h - 5))
	var corners := [a, Vector2i(w - 1 - a.x, h - 1 - a.y), Vector2i(w - 1 - a.x, a.y), Vector2i(a.x, h - 1 - a.y)]
	return corners[slot % 4]


static func sides_for(scenario: Dictionary) -> Array:
	return MapIO.sides_from(scenario)
