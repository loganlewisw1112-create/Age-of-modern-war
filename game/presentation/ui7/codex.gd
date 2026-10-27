extends HBoxContainer
## G7 OPSUI7: lore codex (master scope 13.1): recovered logs, black boxes and transmissions that reveal where the
## Machine came from and why the world is ending. Only COLLECTED files are listed (the rest show as a count).
## Collection is a pure function of Last Protocol state the sim already keeps (sys_state.lp: secrets_found, sites.dam /
## bridges / power, tide, weavers, extractions, purged_cells; Cores.lost; dead nest seeds), so it is deterministic,
## saved with the match and never written by the UI. CONTRACT NOTE: the brief expected LPMODE7 to place / collect
## file entities; lp_world.gd has none, so the file texts and their triggers live here (PROVISIONAL, see FILES).

const UiKit = preload("res://presentation/ui5/kit/ui_kit.gd")
const S = preload("res://presentation/ui7/ops_style.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const Cores = preload("res://sim/systems/cores.gd")
const Creep = preload("res://sim/systems/creep.gd")

## PROVISIONAL lore (owner review pending). need: [kind, arg] evaluated by collected().
const FILES := [
	{"id": "order", "kind": "TRANSMISSION", "title": "Order 0: Last Protocol", "need": ["start", 0],
		"text": "Command authority to all stations. Containment has failed on every front. Last Protocol is now in effect: the doomsday charge is armed and its clock is running. Destroy the three cores and push the creep back, or the Protocol ends this war for everyone. Hold the rings. Good luck."},
	{"id": "lab_log", "kind": "LOG", "title": "Lab log 114: self-repair test", "need": ["purged", 400],
		"text": "Batch 9 nanites closed a 3 cm fracture in a steel beam in four minutes. Then they kept going. By morning the beam had grown a second beam. We sealed the bay. Note to the board: the repair routine has no stop condition we can find."},
	{"id": "black_box_1", "kind": "BLACK BOX", "title": "Black box, convoy Juliet-4", "need": ["extract", 1],
		"text": "[engine noise] ...ground is moving, the road is moving... Juliet-4 to base, the grey stuff is on the wheels, it is climbing the wheels... [static] ...it knows where we are going. It was waiting at the bridge."},
	{"id": "cache_note", "kind": "LOG", "title": "Supply cache inventory", "need": ["secret", "cache"],
		"text": "Cache 7 restocked for the third time this month. Whoever keeps taking the purge canisters is not on our roster. The fence was not cut. It was dissolved and rebuilt behind them."},
	{"id": "lost_squad", "kind": "TRANSMISSION", "title": "Lost squad, final call", "need": ["secret", "lost_squad"],
		"text": "This is Wraith 3. We found the relay crew. They are still at their posts. They are still typing. They have been dead for weeks. The creep is moving their hands. Do not send anyone else."},
	{"id": "core_1", "kind": "BLACK BOX", "title": "Core 1 fragment: routing table", "need": ["cores", 1],
		"text": "Recovered from the first core's shell: a routing table older than the outbreak. Its first entry is a defence-ministry address. The Machine did not escape a lab. It was installed, on purpose, as a backbone for something."},
	{"id": "dam", "kind": "LOG", "title": "Hydro station shift report", "need": ["dam", 0],
		"text": "Flood gates tested at full. The creep will not cross running water; it dries a path first, then crosses. A wide enough river buys time. Nothing buys more than time."},
	{"id": "power", "kind": "LOG", "title": "Grid operator's note", "need": ["power", 0],
		"text": "The old station still answers our handshake. So does something else on the line. Every time we bring a turbine up, the Machine's lattice in the valley goes quiet for a minute, as if it is listening."},
	{"id": "weavers", "kind": "TRANSMISSION", "title": "Intercept: weaver chorus", "need": ["weavers", 0],
		"text": "Signal analysis: the new Machine units broadcast on the same band as the cores, in a repeating three-part pattern. Linguistics says it is not a language. Cryptography says it is a countdown of its own."},
	{"id": "core_2", "kind": "BLACK BOX", "title": "Core 2 fragment: the brief", "need": ["cores", 2],
		"text": "A design brief recovered intact: 'Self-sustaining planetary infrastructure. Must repair, expand and defend itself without human input.' Signed and approved. Nobody asked what it should do when humans became the damage."},
	{"id": "origin", "kind": "LOG", "title": "Origin site: project director", "need": ["secret", "origin"],
		"text": "If you are reading this, the cores woke. They were never weapons. They were seeds for a new grid. We built them to outlast us, and they took the brief literally. The last switch is in the core itself. Do not destroy it if you can capture it."},
	{"id": "mech", "kind": "LOG", "title": "Prototype hangar log", "need": ["secret", "mech"],
		"text": "Prototype walker cleared for field test. Purge emitters integrated, hull sealed against creep. If the facility falls, this machine is the backup plan. There is no backup plan for the backup plan."},
	{"id": "tide", "kind": "TRANSMISSION", "title": "All stations: the Tide", "need": ["tide", 0],
		"text": "Every Machine contact on the map just turned toward the base at once. The creep is moving with them like a wave. This is the push it has been saving for. Seal the gates. Nobody leaves the walls without orders."},
	{"id": "core_3", "kind": "BLACK BOX", "title": "Last core: shutdown key", "need": ["cores", 3],
		"text": "The final core's log ends mid-command: 'grid integrity lost, seeding halted, awaiting operator.' After all of it, the Machine was waiting for someone to tell it to stop."},
]

var hub = null
var collected_ids: Array = []      # last refresh (tests / playtest)
var _list: ItemList
var _title: Label
var _meta: Label
var _body: Label
var _count: Label
var _sig := ""


func _init() -> void:
	name = "Codex"
	add_theme_constant_override("separation", 10)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(280, 0)
	left.size_flags_horizontal = Control.SIZE_FILL
	add_child(left)
	_count = UiKit.label("", "small")
	left.add_child(_count)
	_list = ItemList.new()
	_list.name = "Files"
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(280, 120)
	_list.item_selected.connect(_on_pick)
	left.add_child(_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(right)
	_title = UiKit.label("", "header")
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.add_theme_color_override("font_color", S.AMBER)
	right.add_child(_title)
	_meta = UiKit.label("", "small")
	_meta.add_theme_color_override("font_color", S.DIM)
	right.add_child(_meta)
	_body = UiKit.label("", "body")
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_color_override("font_color", S.PHOS)
	_body.custom_minimum_size = Vector2(160, 0)
	var sc := UiKit.scroll(_body)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(sc)


## Ids of the collected files (FILES order). Pure read of Last Protocol state; [] outside Last Protocol.
static func collected(w: SimWorld) -> Array:
	var out := []
	if w == null or not LastProtocol.active(w):
		return out
	var s = LastProtocol.st(w)
	if s == null or not (s as Dictionary).has("base"):
		return out
	var sites: Dictionary = s.get("sites", {})
	var dead_nests := 0
	if Creep.enabled(w):
		for sd in Creep.seeds(w):
			if String(sd.get("kind", "")) == "nest" and not bool(sd.get("alive", true)):
				dead_nests += 1
	for f in FILES:
		var need: Array = f.need
		var ok := false
		match String(need[0]):
			"start":
				ok = true
			"purged":
				ok = int(s.get("purged_cells", 0)) >= int(need[1]) or dead_nests > 0
			"extract":
				ok = int(s.get("extractions", 0)) >= int(need[1])
			"secret":
				ok = (s.get("secrets_found", []) as Array).has(String(need[1]))
			"cores":
				ok = Cores.lost(w) >= int(need[1])
			"dam":
				ok = bool((sites.get("dam", {}) as Dictionary).get("done", false))
			"power":
				ok = bool((sites.get("power", {}) as Dictionary).get("held", false))
			"weavers":
				ok = bool(s.get("weavers", false))
			"tide":
				ok = bool(s.get("tide", false))
		if ok:
			out.append(String(f.id))
	return out


static func file_of(id: String) -> Dictionary:
	for f in FILES:
		if String(f.id) == id:
			return f
	return {}


func refresh() -> void:
	var w: SimWorld = hub.world() if hub != null else null
	collected_ids = collected(w)
	var sig := str(collected_ids)
	if sig == _sig:
		return
	_sig = sig
	var keep := _list.get_selected_items()
	_list.clear()
	for id in collected_ids:
		var f := file_of(String(id))
		_list.add_item(String(f.title))
		_list.set_item_tooltip(_list.item_count - 1, "%s: %s" % [String(f.kind), String(f.title)])
	_count.text = "INTEL FILES  %d / %d recovered" % [collected_ids.size(), FILES.size()]
	if collected_ids.is_empty():
		_title.text = "NO FILES RECOVERED"
		_meta.text = ""
		_body.text = "Recovered logs, black boxes and transmissions are filed here. In Last Protocol they turn up at secret sites, set pieces, destroyed cores and extractions."
		return
	var ix: int = keep[0] if not keep.is_empty() and int(keep[0]) < collected_ids.size() else collected_ids.size() - 1
	_list.select(ix)
	_on_pick(ix)


func open_file(id: String) -> bool:
	var ix := collected_ids.find(id)
	if ix < 0:
		return false
	_list.select(ix)
	_on_pick(ix)
	return true


func _on_pick(ix: int) -> void:
	if ix < 0 or ix >= collected_ids.size():
		return
	var f := file_of(String(collected_ids[ix]))
	_title.text = String(f.title).to_upper()
	_meta.text = "%s   //   FILE %02d" % [String(f.kind), FILES.find(f) + 1]
	_body.text = String(f.text)
