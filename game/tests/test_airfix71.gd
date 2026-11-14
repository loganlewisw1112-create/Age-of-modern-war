extends "res://tests/test_base.gd"
## G7.1 AIRFIX71 (docs/G71_SCOPE.md A1, Done-when 2): aircraft come home to their own pad ("titanium cement").
## Matrix: 4 craft types (helicopter, regular VTOL dropship, CN stealth dropship, CN Vanta) x {own pad free, taken,
## destroyed, none}: each ends landed centred on a correct pad, holding beside its pad with an alert, or landed on open
## ground beside its base with an alert; never hovering over a building centre. Plus every return trigger (low fuel,
## dry / mission done, the player's return) on a free pad, the Last Protocol map, and determinism + save/load.
## AIRFIX71_REPRO=1 (=lp for the LP map too) prints the full per-case flight logs (step 1 repro harness).

const P = preload("res://tools/airfix71_probe.gd")
const Air = preload("res://sim/systems/air.gd")
const Pads71 = preload("res://sim/systems/pads71.gd")

const TRIGGERS := ["low_fuel", "dry", "manual"]
const STATES := ["free", "taken", "destroyed", "none"]
const OK_BY_STATE := {"free": ["pad"], "taken": ["hold_alert"], "destroyed": ["pad_alt", "ground_alert"], "none": ["ground_alert"]}

static var _sk: Dictionary = {}


## Outcome class of one run: pad (landed centred on its home pad), pad_alt (centred on another pad of its kind, alerted),
## ground_alert (landed on open ground, AirNoPad), hold_alert (holding beside its pad, AirPadBusy), else a failure:
## landed_off, hover_bld (hovering over / at a building centre), hover, dead.
static func classify(r: Dictionary) -> String:
	var e: Dictionary = r.end
	if bool(e.get("dead", false)):
		return "dead"
	if int(e.get("hover_bld", 0)) > 0:
		return "hover_bld"
	var al: Array = r.alerts
	if bool(e.landed):
		if String(e.pad71) != "":
			if float(e.d_home) <= 0.75:
				return "pad"
			return "pad_alt" if al.has("AirPadLost") else "landed_off"
		return "ground_alert" if al.has("AirNoPad") and not bool(e.in_bld) else "landed_off"
	if bool(e.in_bld) or float(e.bld_d) <= 1.5:
		return "hover_bld"
	return "hold_alert" if bool(e.get("hold", false)) and al.has("AirPadBusy") else "hover"


func _base() -> Dictionary:
	if _sk.is_empty():
		_sk = P.setup_skirmish()
	return _sk


func _run(s: Dictionary, ty: String, st: String, tr: String, ticks: int, tag: String) -> String:
	if OS.get_environment("AIRFIX71_ONLY") != "" and OS.get_environment("AIRFIX71_ONLY") != "%s_%s_%s" % [tag, ty, st]:
		return (OK_BY_STATE[st] as Array)[0]
	var w := P.clone(s.w)
	var id := int(s.ids[ty])
	P.apply_state(w, id, st)
	var r := P.run_case(w, id, tr, ticks)
	var c := classify(r)
	print("  airfix71 %s %-5s pad=%-9s %-8s => %-12s pad71=%s d_home=%.2f bld_d=%.2f alerts=%s" % [tag, ty, st, tr, c,
		String(r.end.get("pad71", "")), float(r.end.get("d_home", -1.0)), float(r.end.get("bld_d", -1.0)), str(r.alerts)])
	if OS.get_environment("AIRFIX71_REPRO") != "" or not (OK_BY_STATE[st] as Array).has(c):
		for ln in r.log:
			print("    ", ln)
	return c


func test_airfix71_setup_has_all_four() -> void:
	var s := _base()
	for ty in P.TYPES:
		check((s.ids as Dictionary).has(ty) and (s.w as SimWorld).entities.has(int(s.ids[ty])), "skirmish setup has a %s" % ty)


func test_airfix71_matrix_skirmish() -> void:
	var s := _base()
	var bad := 0
	for ty in P.TYPES:
		for st in STATES:
			var c := _run(s, ty, st, "low_fuel", 1800, "skirmish")
			if not check((OK_BY_STATE[st] as Array).has(c), "%s with its own pad %s: %s (want %s)" % [ty, st, c, str(OK_BY_STATE[st])]):
				bad += 1
	check_eq(bad, 0, "AIRFIX matrix: 16 cases, 0 failures")


func test_airfix71_every_trigger_lands_home() -> void:
	var s := _base()
	for ty in P.TYPES:
		for tr in ["dry", "manual"]:
			var c := _run(s, ty, "free", tr, 1800, "skirmish")
			check_eq(c, "pad", "%s %s: lands centred on its own pad" % [ty, tr])


func test_airfix71_registry_and_save_load() -> void:
	var s := _base()
	var w := P.clone(s.w)
	Air.sync71(w)
	for k in ["helipad", "vtol_pad", "cn_helipad", "roof_pad"]:
		var n := 0
		for key in Pads71.pads(w):
			if String(Pads71.pads(w)[key].k) == k:
				n += 1
		check(n >= 1, "registry holds a %s pad" % k)
	var id := int(s.ids.cn)
	P.run_case(w, id, "low_fuel", 60)
	var a := P.clone(w)
	var b := P.clone(w)
	a.run_ticks(600)
	b.run_ticks(600)
	check_eq(a.state_hash(), b.state_hash(), "save/load mid-return: same future")
	check(Air.phase(a, id) == "landed" or Air.phase(a, id) == "parked", "the reloaded dropship still lands")


func test_airfix71_same_seed_same_hash() -> void:
	var h := []
	for i in 2:
		var s := P.setup_skirmish()
		var w: SimWorld = s.w
		P.apply_state(w, int(s.ids.vanta), "taken")
		for ty in P.TYPES:
			P.run_case(w, int(s.ids[ty]), "low_fuel", 1, Vector2(10, -8))
		w.run_ticks(900)
		h.append(w.state_hash())
	check_eq(h[0], h[1], "two identical runs: same hash")


func test_airfix71_lp_map() -> void:
	if OS.get_environment("AIRFIX71_ONLY") != "" and not OS.get_environment("AIRFIX71_ONLY").begins_with("lp"):
		return
	if not preload("res://sim/map_gen.gd").has_map("last_protocol"):
		check(true, "no LP map")
		return
	var s := P.setup_lp()
	for ty in P.TYPES:
		if not check((s.ids as Dictionary).has(ty), "LP has a %s" % ty):
			continue
		check_eq(_run(s, ty, "free", "low_fuel", 900, "lp"), "pad", "LP %s low fuel: lands centred on its own pad" % ty)
	if (s.ids as Dictionary).has("cn"):
		check(OK_BY_STATE.taken.has(_run(s, "cn", "taken", "manual", 900, "lp")), "LP stealth dropship, helipad taken: holds with an alert")
