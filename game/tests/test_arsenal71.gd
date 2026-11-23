extends "res://tests/test_base.gd"
## G7.1 J11 arsenal defs + Blackglass-gated research unlocks; save keeps RE + warmind + conduct.

const Research71 = preload("res://sim/systems/research71.gd")
const Re = preload("res://sim/systems/recomplex71.gd")
const Warmind71 = preload("res://sim/systems/warmind71.gd")
const Conduct71 = preload("res://sim/systems/conduct71.gd")
const LastProtocol = preload("res://sim/systems/last_protocol.gd")


func test_j11_defs_exist() -> void:
	for id in ["a_g71_plasma_gunner", "a_g71_coilgunner", "a_g71_dust_operator", "a_g71_light_mech", "a_g71_heavy_mech"]:
		check(not Content.unit(id).is_empty(), "%s unit def" % id)
	check(not Content.building("a_g71_shield_dome").is_empty(), "shield dome building")
	check(not Content.weapon("g71_plasma_rifle").is_empty(), "plasma weapon")


func test_plasma_research_needs_blackglass_proto() -> void:
	var c := LastProtocol.make_config(70, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP"):
		return
	for i in 10:
		w.step()
	# Unlock ammo_he prerequisite chain first.
	for tech in ["ammo_ap", "ammo_he"]:
		w.submit({"type": "research71_start", "issuer": 0, "tech": tech})
		w.step()
		var need := int(ceil(float(Research71.TREE[tech].cost_s) * float(SimWorld.TICK_RATE))) + 3
		for i in need:
			w.step()
	var why := Research71.validate_command(w, {"type": "research71_start", "tech": "plasma_cannon"})
	check(why.find("Blackglass") >= 0 or why.find("prototype") >= 0, "plasma blocked without proto (%s)" % why)
	Re.capture(w, "g71_m_brute", "c0")
	var stages := int(ceil(Re.stage_s() * float(SimWorld.TICK_RATE))) * (Re.STAGES.size() + 1) + 5
	for i in stages:
		w.step()
	check((Re._st(w).prototypes as Dictionary).has("g71_m_brute"), "brute proto ready")
	check_eq(Research71.validate_command(w, {"type": "research71_start", "tech": "plasma_cannon"}), "", "plasma opens after proto")


func test_wave4_state_survives_save() -> void:
	var c := LastProtocol.make_config(71, "industrial_heartland_m")
	var w := SimWorld.new_match(c)
	if not check(w != null, "LP"):
		return
	for i in 8:
		w.step()
	Warmind71.note_feint(w, 4, true)
	Warmind71.note_feint(w, 4, true)
	Conduct71.mark(w, "gas_friendly")
	Re.capture(w, "g71_m_sapper", "cx")
	var loaded := SimWorld.from_dict(w.to_dict().duplicate(true))
	check(Warmind71.fooled(loaded), "warmind fooled survives save")
	check_eq(Warmind71.bias_face(loaded), 4, "bias face saved")
	check(not Conduct71.gold_ok(loaded), "conduct gold block saved")
	check(not Re.cell(loaded, "cx").is_empty(), "RE cell saved")
