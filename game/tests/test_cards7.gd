extends "res://tests/test_base.gd"
## G7 CARDSEL7 acceptance (docs/G7_REFERENCE.md 13.9c-37): the DRONE BAY card shows only while the player has the drone bay
## (the workshop's 2nd storey) selected, the BARRACKS RESERVE card only while the Sentinel Barracks is selected; no
## selection hides both; deselecting hides again; the buttons still issue their commands while shown.

const LR = preload("res://sim/systems/lp_reserve7.gd")
const DroneBay7 = preload("res://sim/systems/drone_bay7.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")
const DroneCard = preload("res://presentation/ui7/dronebay_card.gd")
const ResCard = preload("res://presentation/ui7/lpreserve_card.gd")
const MAP := "industrial_heartland_m"


## Minimal MatchView stand-in: the same selection / part API the cards read, plus issue().
class StubMv extends RefCounted:
	signal selection_changed
	signal world_events(evs)
	var selection: Array[int] = []
	var sel_part := ""
	var world = null
	var player_fid := 0
	var issued: Array = []

	func select_ids(ids: Array, part: String = "") -> void:
		sel_part = part
		var out: Array[int] = []
		for i in ids:
			out.append(int(i))
		selection = out
		selection_changed.emit()

	func part_selected(fac: int, part: String) -> bool:
		return sel_part == part and selection.has(fac)

	func issue(cmd: Dictionary) -> void:
		issued.append(cmd)


func _ensure_g7() -> void:
	if Content.unit("g7_sent_warden").is_empty() or Content.building("a_cn_facility").is_empty():
		Content._merge_fragment_dir("res://content/g7")
		Content._link_fragment_production()


func test_cards_follow_selection() -> void:
	_ensure_g7()
	var w := SimWorld.new_match(LastProtocol.make_config(4242, MAP))
	if not check(w != null, "Last Protocol world"):
		return
	w.run_ticks(25)
	w.ai_state = {}
	var fid := int(w.sys_state.lp.fid)
	var res := LR.reserves_of(w, fid)
	var bays := DroneBay7.bays_of(w, fid)
	if not (check(not res.is_empty(), "a barracks reserve exists") and check(not bays.is_empty(), "a drone bay exists")):
		return
	var fac := int(bays[0])
	var bar := int(LR.rec(w, int(res[0])).bar)
	var mv := StubMv.new()
	mv.world = w
	mv.player_fid = fid
	var dc = DroneCard.new()
	var rc = ResCard.new()
	for c in [dc, rc]:
		c.mv = mv
		c._ready()
	mv.selection_changed.connect(dc._on_selection_changed)
	mv.selection_changed.connect(rc._on_selection_changed)
	dc.refresh()
	rc.refresh()
	check(not dc.visible and not rc.visible, "no selection: both cards hidden")

	mv.select_ids([bar])
	check(rc.visible and not dc.visible, "barracks selected: only the reserve card")
	mv.select_ids([bar, fac + 100000])   # unknown ids are the caller's business; barracks still in selection
	check(rc.visible and not dc.visible, "a selection containing the barracks keeps the reserve card")
	mv.select_ids([])
	check(not rc.visible and not dc.visible, "deselected: reserve card hides")

	mv.select_ids([fac], "drone_bay")
	check(dc.visible and not rc.visible, "drone bay selected: only the drone card")
	mv.select_ids([fac])
	check(not dc.visible and not rc.visible, "facility core selected without the bay part: both hidden")
	mv.select_ids([fac], "drone_bay")
	mv.select_ids([])
	check(not dc.visible, "deselected: drone card hides")

	# buttons keep working while shown
	mv.select_ids([bar])
	rc._on_auto()
	check(not mv.issued.is_empty() and String(mv.issued[-1].get("type", "")).begins_with("lpres"), "reserve card button issues a command")
	mv.select_ids([fac], "drone_bay")
	dc._on_launch()
	check(String(mv.issued[-1].get("type", "")) == "dronebay_launch", "drone card LAUNCH issues dronebay_launch")

	# fit screens / tests may force the cards visible
	mv.select_ids([])
	dc.force_show = true
	rc.force_show = true
	dc.refresh()
	rc.refresh()
	check(dc.visible and rc.visible, "force_show keeps both cards testable without a selection")
	dc.free()
	rc.free()
