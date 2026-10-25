extends "res://tests/test_base.gd"
## G6 acceptance (owner: AI7-CMD). CONTRACTS_G6 section 15, 16, section 17: the survival Wave AI.

const Waves = preload("res://sim/systems/waves.gd")
const WaveAI = preload("res://sim/ai/wave_ai.gd")
const U = preload("res://sim/ai/ai_util.gd")


## repel_waves survival on the default map: you (fid 0) defend, side 1 (AI) attacks with waves.
## defender_ai: the defender is an AI side too (it fights back, so the match lasts to later waves).
func _world(count: int, defender_ai: bool = false) -> SimWorld:
	var c := Waves.survival_config(SimWorld.default_config(), "repel_waves", count, 1)
	c.sides[0].ai = defender_ai
	return make_world(c)


func _wave(w: SimWorld, idx: int) -> Dictionary:
	for wv in w.sys_state.get("waves", {}).get("waves", []):
		if int(wv.index) == idx:
			return wv
	return {}


func _centroid(w: SimWorld, ids: Array) -> Vector2:
	var s := Vector2.ZERO
	var n := 0
	for id in ids:
		if w.entities.has(int(id)):
			s += Vector2(w.entities[int(id)].pos)
			n += 1
	return s / float(maxi(n, 1))


## Steps until wave idx has spawned (max_ticks cap); records each wave group's playstyle in seen.
func _until_wave(w: SimWorld, idx: int, max_ticks: int, seen: Dictionary, evs: Array) -> Dictionary:
	for i in max_ticks:
		w.step()
		evs.append_array(w.events)
		var st: Dictionary = w.ai_state.get(1, {}).get("waves", {})
		for k in st.get("groups", {}):
			if not seen.has(int(k)):
				seen[int(k)] = String(st.groups[k].playstyle)
		if not _wave(w, idx).is_empty() and seen.has(idx):
			return _wave(w, idx)
	return _wave(w, idx)


func test_waves_attack_defender() -> void:
	var w := _world(3)
	if not check(w.sys_state.has("waves") or Waves.active(w), "survival is active"):
		return
	var seen := {}
	var evs := []
	var wv := _until_wave(w, 1, 6000, seen, evs)
	if not check(not wv.is_empty(), "wave 1 spawned"):
		return
	var ids: Array = (wv.units as Array).duplicate()
	check(not ids.is_empty(), "wave 1 has units")
	var badged := 0
	for id in ids:
		if w.entities.has(int(id)) and String(w.entities[int(id)].get("ai_cmd", "")) == "wave":
			badged += 1
	check_eq(badged, ids.size(), "every wave unit is under the Wave AI (e.ai_cmd = wave)")
	var home := U.base_pos(w, 0)
	var d0 := _centroid(w, ids).distance_to(home)
	var evs2 := []
	for i in 600:
		w.step()
		evs2.append_array(w.events)
	var alive := []
	for id in ids:
		if w.entities.has(int(id)):
			alive.append(id)
	var d1 := _centroid(w, alive).distance_to(home) if not alive.is_empty() else 0.0
	if not check(alive.is_empty() or d1 < d0 - 5.0, "wave 1 closes on the defender (%.1f -> %.1f tiles)" % [d0, d1]):
		var g: Dictionary = w.ai_state.get(1, {}).get("waves", {}).get("groups", {}).get(1, {})
		print("  wave diag group mode=%s phase=%s obj=%s sent=%d units=%d" % [str(g.get("mode")), str((g.get("doc", {}) as Dictionary).get("phase")),
			str(g.get("objective")), (g.get("sent", {}) as Dictionary).size(), (g.get("units", []) as Array).size()])
		for id in alive.slice(0, 3):
			var e: Dictionary = w.entities[int(id)]
			print("  wave diag %d %s pos=%s order=%s moving=%s" % [int(id), String(e.def), str(e.pos), str(e.order), str(e.get("moving"))])
		var rj := 0
		for ev in evs2:
			if String(ev.type) == "CommandRejected" and int(ev.issuer) == 1:
				rj += 1
				if rj <= 3:
					print("  wave diag rejected %s: %s" % [String(ev.get("type")), String(ev.reason)])
		print("  wave diag rejected=%d home=%s doctrine=%s" % [rj, str(home), str(w.ai_state.get(1, {}).has("doctrine"))])
	var tags := {}
	for ev in evs + evs2:
		if String(ev.type) == "AiDecision" and int(ev.fid) == 1:
			tags[String(ev.tag)] = int(tags.get(String(ev.tag), 0)) + 1
	check(tags.has("reserve_commit"), "the Wave AI logs the wave's commitment: %s" % str(tags))
	check(tags.size() >= 2, "the wave fights with doctrine (several decision tags): %s" % str(tags))


func test_waves_escalate_with_company_templates() -> void:
	check_eq(WaveAI.tier_for(1), "aggressive", "waves 1-2: aggressive")
	check_eq(WaveAI.tier_for(3), "combined", "waves 3-5: combined arms")
	check_eq(WaveAI.tier_for(6), "raid", "wave 6+: combined arms + raid")
	var w := _world(3, true)
	var seen := {}
	var evs := []
	var w1 := _until_wave(w, 1, 6000, seen, evs)
	if not check(not w1.is_empty(), "wave 1 spawned"):
		return
	check(not (w1.get("companies", []) as Array).is_empty(), "wave 1 is built from company templates")
	var co := 0
	for id in w1.units:
		if w.entities.has(int(id)) and w.entities[int(id)].has("company"):
			co += 1
	check(co > 0, "wave units belong to companies")
	var n1 := int(w1.get("size", (w1.units as Array).size()))
	var w3 := _until_wave(w, 3, 6000, seen, evs)
	if not check(not w3.is_empty(), "wave 3 spawned (tick %d, match ended: %s)" % [w.tick, str(w.match_state.ended)]):
		return
	check(int(w3.get("size", (w3.units as Array).size())) >= n1, "wave 3 is at least as big as wave 1 (%d vs %d)" % [
		int(w3.get("size", 0)), n1])
	check_eq(String(seen.get(1, "")), "aggressive", "wave 1 commanded with the aggressive doctrine")
	check_eq(String(seen.get(3, "")), "combined", "wave 3 commanded with combined arms (escalated)")
