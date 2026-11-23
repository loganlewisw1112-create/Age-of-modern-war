extends RefCounted
## G7.1 wave 2 (ORCH-owned): the one place where wave-2 view layers are attached to MatchView.
## An agent never edits match_view.gd for this: it posts `need change_request.match_view71` with its line for LAYERS.
##
## Each entry: script (a Node2D / Node with `refresh(snap: Dictionary)`, optional `setup(mv)`), at:
##   "under_units"  added right before the entity layer, same z: drawn under units (bodies, ground marks)
##   "over_units"   added right after the entity layer, same z: drawn over units (tags, turret looks)
## Scripts are loaded with load(), not preload(): a layer that fails to parse is skipped with one warning and the
## match view keeps working (a half-written view file broke every windowed run on 2026-11-21).
## Every layer must cost ~nothing when its snapshot provider returns null (off Last Protocol / feature unused).
const LAYERS := [
	{"script": "res://presentation/view/gore71_layer.gd", "at": "under_units", "by": "DAMAGE71"},   # CR seq 1896
	{"script": "res://presentation/ui71/triage_tags.gd", "at": "over_units", "by": "DAMAGE71"},   # CR seq 1896
	{"script": "res://presentation/view/fires71_view.gd", "at": "over_units", "by": "FIRES71"},   # CR seq 2040
	{"script": "res://presentation/ui71/killzone_paint.gd", "at": "over_units", "by": "FIRES71"},   # CR seq 2040: before fire_radial (its Sectors slot finds this node)
	{"script": "res://presentation/ui71/fire_radial.gd", "at": "over_units", "by": "FIRES71"},   # CR seq 2040: hold-key radial (Hotkeys fire_radial71)
	{"script": "res://presentation/view/signals71_layer.gd", "at": "over_units", "by": "ARMY71"},   # CR seq 2063: hand signals; mounts AmmoPanel71 + RadioFeed71 on the HUD in Last Protocol
	{"script": "res://presentation/view/turret71_look.gd", "at": "over_units", "by": "BASTION71"},   # CR seq 2287: turret tracking lines, recoil, heat, disabled sparks
	{"script": "res://presentation/view/gas71_layer.gd", "at": "over_units", "by": "CNOPS71"},   # CR seq 3041: J10 gas cloud + mask glyphs
	{"script": "res://presentation/view/cn71_layer.gd", "at": "over_units", "by": "CNOPS71"},   # CR seq 4443: Vanta 2 trail + bank cue, shield-drone bubble
	{"script": "res://presentation/view/horror71_layer.gd", "at": "over_units", "by": "G71"},   # J7 silence / night eyes / bodies on display
]

## HUD panels (ORCH): scripts with `static func attach(mv) -> Node` (the Roster71 pattern), mounted once after the HUD is
## built. Same rule: loaded with load(), a file that does not parse is skipped with one warning.
const HUD := [
	{"script": "res://presentation/ui71/hospital_card.gd", "by": "CNOPS71"},   # hospital wards / quarantine / medevac card (handoff CNOPS71-6)
]


static func attach_hud(mv: Node) -> void:
	for H in HUD:
		var sc = load(String(H.script)) if ResourceLoader.exists(String(H.script)) else null
		if sc == null or not (sc is GDScript) or not (sc as GDScript).can_instantiate():
			push_warning("G71Attach: skipped HUD %s (%s): missing or does not parse" % [H.script, H.by])
			continue
		sc.call("attach", mv)


## Creates and adds the layers of one slot. Returns the nodes (MatchView keeps them and calls refresh_all each frame).
static func attach(mv: Node, at: String, z: int) -> Array:
	var out: Array = []
	for L in LAYERS:
		if String(L.at) != at:
			continue
		var sc = load(String(L.script)) if ResourceLoader.exists(String(L.script)) else null
		if sc == null or not (sc is GDScript) or not (sc as GDScript).can_instantiate():
			push_warning("G71Attach: skipped %s (%s): missing or does not parse" % [L.script, L.by])
			continue
		var n = sc.new()
		if not (n is Node):
			push_warning("G71Attach: skipped %s (%s): not a Node" % [L.script, L.by])
			continue
		if n is CanvasItem:
			(n as CanvasItem).z_index = z
		mv.add_child(n)
		if n.has_method("setup"):
			n.call("setup", mv)
		if n.has_method("refresh"):
			out.append(n)
	return out


static func refresh_all(nodes: Array, snap: Dictionary) -> void:
	for n in nodes:
		n.call("refresh", snap)
