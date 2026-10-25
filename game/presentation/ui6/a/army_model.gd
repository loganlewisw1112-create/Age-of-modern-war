extends RefCounted
## UI6a (G6): Army Builder model + per-profile template store (CONTRACTS_G6 sections 3.5, 4, 8).
## Custom company templates are edited here as {name, faction, slots: [{def: production item, count}]}
## (exact counts, ARMY6's custom shape) and validated with Companies.validate_template, the same rule
## the sim applies to train_company. They are saved per player profile, outside the match state:
##   user://profiles/<profile>/company_templates.json = {ver: 1, templates: {faction: {name: template}}}
## Training a saved custom sends the template dict itself (train_company template: {..}); the sim then
## records it under w.sys_state.companies.custom (saved with the match), so a profile template never
## changes a match it was not used in.

const Companies = preload("res://sim/systems/companies.gd")

const VER := 1
const NAME_MAX := 24
const DEFAULT_PROFILE := "default"

static var profile := DEFAULT_PROFILE


# ------------------------------------------------------------------ store (per profile)
static func path(prof: String = "") -> String:
	var p := prof if prof != "" else profile
	return "user://profiles/%s/company_templates.json" % p.validate_filename()


static func load_all(prof: String = "") -> Dictionary:
	var f := FileAccess.open(path(prof), FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY or typeof(d.get("templates")) != TYPE_DICTIONARY:
		return {}
	return d.templates


static func names(faction: String, prof: String = "") -> Array:
	var out: Array = (load_all(prof).get(faction, {}) as Dictionary).keys()
	out.sort()
	return out


static func get_template(faction: String, tname: String, prof: String = "") -> Dictionary:
	var t = load_all(prof).get(faction, {}).get(tname)
	return normalize(t, faction) if typeof(t) == TYPE_DICTIONARY else {}


## "" or why the name cannot be used.
static func name_reason(tname: String) -> String:
	var n := tname.strip_edges()
	if n == "":
		return "Name the template first."
	if n.length() > NAME_MAX:
		return "Template names are at most %d characters." % NAME_MAX
	if n.contains(":") or n.contains("/") or n.contains("\\"):
		return "Template names cannot contain : / or \\."
	return ""


## Saves (or replaces) a template in the profile. Returns "" or the reason it was not saved.
static func save_template(faction: String, t: Dictionary, prof: String = "") -> String:
	var tname := String(t.get("name", "")).strip_edges()
	var r := name_reason(tname)
	if r != "":
		return r
	var all := load_all(prof)
	if not all.has(faction):
		all[faction] = {}
	all[faction][tname] = normalize(t, faction)
	return _write(all, prof)


static func remove_template(faction: String, tname: String, prof: String = "") -> String:
	var all := load_all(prof)
	if not all.get(faction, {}).has(tname):
		return "No saved template named %s." % tname
	(all[faction] as Dictionary).erase(tname)
	return _write(all, prof)


static func _write(all: Dictionary, prof: String) -> String:
	var p := path(prof)
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		return "Could not write %s." % p
	f.store_string(JSON.stringify({"ver": VER, "templates": all}, " "))
	return ""


# ------------------------------------------------------------------ editing (pure)
## A clean copy: {name, faction, slots: [{def, count:int}]} (JSON numbers come back as floats).
static func normalize(t, faction: String) -> Dictionary:
	var out := {"name": String(t.get("name", "")), "faction": faction, "slots": []}
	for s in t.get("slots", []):
		if typeof(s) == TYPE_DICTIONARY and String(s.get("def", "")) != "":
			out.slots.append({"def": String(s.def), "count": int(s.get("count", 1))})
	return out


static func new_template(tname: String, faction: String) -> Dictionary:
	return {"name": tname, "faction": faction, "slots": []}


## Adds n of item (merging into an existing slot of the same item).
static func add_slot(t: Dictionary, item: String, n: int = 1) -> void:
	for s in t.slots:
		if String(s.def) == item:
			s.count = int(s.count) + n
			return
	t.slots.append({"def": item, "count": n})


static func set_count(t: Dictionary, i: int, n: int) -> void:
	if i >= 0 and i < t.slots.size():
		t.slots[i].count = maxi(1, n)


static func remove_slot(t: Dictionary, i: int) -> void:
	if i >= 0 and i < t.slots.size():
		t.slots.remove_at(i)


static func elements(t: Dictionary) -> int:
	var n := 0
	for s in t.get("slots", []):
		n += int(s.get("count", 0))
	return n


## A preset loaded into the editor at a size: its slots with counts x size_mult (exact counts), each
## slot resolved to the item the side would field now (def, else alt).
static func from_preset(w: SimWorld, fid: int, tid: String, size: String) -> Dictionary:
	var src := Companies.template(w, fid, tid)
	var faction := Companies.faction_of(w, fid)
	var t := new_template(String(src.get("name", tid)), faction)
	var mult := int(Companies.rules().get("size_mult", {}).get(size, 1))
	for s in src.get("slots", []):
		var item := Companies._slot_item(w, fid, s)
		add_slot(t, item, int(s.get("count", 1)) * mult)
	return t


## Production items a side may put in a company slot (ascending id): its faction's (or shared)
## items that pass Companies.validate_template as a one-slot template (stage gates ignored, so the
## player can plan ahead; the summary shows the gate).
static func candidates(faction: String) -> Array:
	var out := []
	for id in Content.ids("production"):
		var p := Content.production(String(id))
		var pf := String(p.get("faction", ""))
		if pf != faction and pf != "shared":
			continue
		if Companies.validate_template(faction, {"faction": faction, "slots": [{"def": String(id), "count": 1}]}) == "":
			out.append(String(id))
	out.sort()
	return out


## {elements, cap, platoons, cost, pop, time, reason}: the sim's plan + validation for side fid.
static func summary(w: SimWorld, fid: int, t: Dictionary) -> Dictionary:
	var reason := Companies.validate_template(fid, t, w)
	var cap := int(Companies.rules().get("element_cap", 45))
	var out := {"elements": elements(t), "cap": cap, "platoons": 0, "cost": {}, "pop": 0, "time": 0.0, "reason": reason}
	if not (t.get("slots", []) as Array).is_empty():
		var pl := Companies.plan(w, fid, t, "company", false)
		out.platoons = int(pl.platoons)
		out.cost = pl.cost
		out.pop = int(pl.pop)
		out.time = float(pl.time)
	return out


static func train_cmd(fid: int, hq_id: int, template, size: String) -> Dictionary:
	return {"type": "train_company", "issuer": fid, "building_id": hq_id,
		"template": (template as Dictionary).duplicate(true) if typeof(template) == TYPE_DICTIONARY else String(template), "size": size}
