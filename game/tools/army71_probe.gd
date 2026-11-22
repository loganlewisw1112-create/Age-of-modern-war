extends SceneTree
## G7.1 ARMY71 Step 1 probe (D4 discipline "before" / "after" numbers), headless, Last Protocol world.
##   godot --headless --path . -s tools/army71_probe.gd -- [--case=wall|field|both] [--ticks=600] [--every=20] [--seed=7]
## wall:  the LP start base under a Machine wave (Bench.build_lp_peak, 240 machines, no robots); the 6 garrison squads
##        nearest the attack fronts are logged.
## field: the same LP world, one garrison squad's soldier defs re-spawned as a fresh squad 18 tiles outside the east
##        wall, 8 men attack-moving into 12 machines holding 20 tiles further east; its leader is killed at tick --kill
##        (default 100).
## Per logged squad, every --every ticks: drift (mean |member offset from the squad centroid - its offset at the
## start| in tiles, i.e. formation shape error), cover% (Morale.cover_level > 0), threat% (members whose target is the
## highest-threat enemy in their range; threat = the enemy's damage per second against that member, x2 when the member
## is inside the enemy's range), focus% (members on the squad's most-shot target), reload% (shooters in a magazine
## reload at once, e.d71r > 0: max and mean; before D4 there is no magazine model, so 0 = no reload phase at all). Leader loss: ticks for the squad to have a leader again (SquadAI.leader_of) and
## drift / threat% in the 100 ticks before vs after. Prints one "ARMY71_PROBE {json}" line per case.

const Bench = preload("res://tools/scale_bench.gd")
const Combat = preload("res://sim/systems/combat.gd")
const Morale = preload("res://sim/systems/morale.gd")
const SquadAI = preload("res://sim/systems/squad_ai.gd")

var _args := {}


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--") and s.contains("="):
			_args[s.substr(2, s.find("=") - 2)] = s.substr(s.find("=") + 1)
	var case := String(_args.get("case", "both"))
	if case == "wall" or case == "both":
		print("ARMY71_PROBE " + JSON.stringify(run_case("wall", int(_args.get("ticks", 600)), int(_args.get("every", 20)), int(_args.get("seed", 7)), -1)))
	if case == "field" or case == "both":
		print("ARMY71_PROBE " + JSON.stringify(run_case("field", int(_args.get("ticks", 600)), int(_args.get("every", 20)), int(_args.get("seed", 7)), int(_args.get("kill", 100)))))
	quit(0)


static func _squads(w: SimWorld, fid: int) -> Dictionary:
	var out := {}
	var ids: Array = w.entities.keys()
	ids.sort()
	for id in ids:
		var e: Dictionary = w.entities[id]
		if e.kind == "unit" and int(e.owner) == fid and int(e.get("squad", -1)) >= 0 and e.has("morale"):
			var sq := int(e.squad)
			if not out.has(sq):
				out[sq] = []
			out[sq].append(int(id))
	return out


static func _centroid(w: SimWorld, ids: Array) -> Vector2:
	var c := Vector2.ZERO
	var n := 0
	for id in ids:
		if w.entities.has(id):
			c += Vector2(w.entities[id].pos)
			n += 1
	return c / float(maxi(n, 1))


static func _threat(t: Dictionary, e: Dictionary) -> float:
	var ts := Combat.stats(t)
	if String(ts.weapon) == "" or not Combat.can_target(ts, e):
		return 0.0
	var dps := Combat.shot_damage(t, e) / maxf(float(ts.cooldown), 0.05)
	if Combat.dist_to(t.pos, e) <= float(ts.range):
		dps *= 2.0
	return dps


## One case. Returns the metrics dict.
static func run_case(case: String, ticks: int, every: int, seed: int, kill_at: int) -> Dictionary:
	var B: Dictionary = Bench.build_lp_peak(240 if case == "wall" else 0, 0, seed)
	var w: SimWorld = B.w
	var hfid := int(B.hfid)
	var mfid := int(B.mfid)
	var sqs := _squads(w, hfid)
	var logged: Array = []
	var sp := Vector2(w.factions[hfid].spawn) + Vector2(0.5, 0.5)
	if case == "wall":
		var keys: Array = sqs.keys()
		# nearest to the four attack fronts: most northern / eastern / southern / western squads first
		var scored := []
		for sq in keys:
			var c := _centroid(w, sqs[sq])
			scored.append([-(c - sp).length(), int(sq)])
		scored.sort()
		for i in mini(6, scored.size()):
			logged.append(int(scored[i][1]))
	else:
		var src: Array = sqs[sqs.keys().min()]
		var pst: Dictionary = w.sys_state.get("production", {"next_squad": 1})
		var nsq := int(pst.next_squad)
		pst.next_squad = nsq + 1
		w.sys_state["production"] = pst
		var at := sp + Vector2(float(int(_wall_r(w, sp)) + 18), 0)   # east: the LP base sits near the map's top-left corner
		var mem := []
		for k in 8:   # the garrison squad's defs, repeated to 8 men
			var id := w.spawn_unit(String(w.entities[src[k % src.size()]].def), hfid, at + Vector2(float(k % 4) - 1.5, float(k / 4)))
			w.entities[id].squad = nsq
			mem.append(id)
		sqs[nsq] = mem
		logged.append(nsq)
		var mdefs := []
		for role in ["infantry", "infantry", "antitank", "light"]:
			var d := Bench.unit_def("machine", role)
			if d != "":
				mdefs.append(d)
		var mach := []
		for k in 12:
			mach.append(w.spawn_unit(String(mdefs[k % mdefs.size()]), mfid, at + Vector2(20.0 + float(k / 6), float(k % 6) * 1.5 - 3.75)))
		w.submit({"type": "attack_move", "issuer": hfid, "unit_ids": mem, "target": at + Vector2(30, 0)})
		w.submit({"type": "hold", "issuer": mfid, "unit_ids": mach})
	# start offsets
	var off := {}
	for sq in logged:
		var c := _centroid(w, sqs[sq])
		for id in sqs[sq]:
			off[id] = Vector2(w.entities[id].pos) - c
	var acc := {"samples": 0, "drift": 0.0, "cover": 0.0, "cover_n": 0, "thr_ok": 0, "thr_n": 0, "focus_ok": 0, "focus_n": 0,
		"rel_max": 0.0, "rel_sum": 0.0, "rel_n": 0}
	var pre := {"drift": 0.0, "n": 0, "thr_ok": 0, "thr_n": 0}
	var post := {"drift": 0.0, "n": 0, "thr_ok": 0, "thr_n": 0}
	var kill := {"killed": -1, "leaderless_ticks": -1}
	var killed_tick := -1
	for t in ticks:
		if case == "field" and t == kill_at:
			var mem: Array = (sqs[logged[0]] as Array).filter(func(x): return w.entities.has(x))
			if not mem.is_empty():
				var lid := SquadAI.leader_of(w, mem)
				kill.killed = lid
				w.destroy(lid, "probe")
				killed_tick = t
		w.step()
		if killed_tick >= 0 and int(kill.leaderless_ticks) < 0:
			var mem2: Array = (sqs[logged[0]] as Array).filter(func(x): return w.entities.has(x))
			if not mem2.is_empty() and String(w.entities[SquadAI.leader_of(w, mem2)].get("rank_role", "")) != "":
				kill.leaderless_ticks = t + 1 - killed_tick
		if t % every != 0:
			continue
		acc.samples += 1
		for sq in logged:
			var mem: Array = (sqs[sq] as Array).filter(func(x): return w.entities.has(x))
			if mem.size() < 2:
				continue
			var c := _centroid(w, mem)
			var dsum := 0.0
			var tc := {}
			var reloading := 0
			var shooters := 0
			var tok := 0
			var tn := 0
			for id in mem:
				var e: Dictionary = w.entities[id]
				dsum += ((Vector2(e.pos) - c) - Vector2(off[id])).length()
				acc.cover_n += 1
				if Morale.cover_level(w, e) > 0:
					acc.cover += 1
				var tid := int(e.target)
				if tid >= 0 and w.entities.has(tid):
					shooters += 1
					tc[tid] = int(tc.get(tid, 0)) + 1
					if int(e.get("d71r", 0)) > w.tick:
						reloading += 1
					var s := Combat.stats(e)
					var best := -1
					var bsc := -1.0
					for oid in w.entities:   # threat ground truth (probe only: full scan)
						var o: Dictionary = w.entities[oid]
						if o.kind != "unit" or int(o.owner) != mfid or Combat.dist_to(e.pos, o) > float(s.range):
							continue
						var th := _threat(o, e)
						if th > bsc or (th == bsc and int(oid) < best):
							bsc = th
							best = int(oid)
					if best >= 0:
						tn += 1
						if best == tid:
							tok += 1
			var dr := dsum / float(mem.size())
			acc.drift += dr
			acc.thr_ok += tok
			acc.thr_n += tn
			if shooters >= 2:
				var mx := 0
				for k in tc:
					mx = maxi(mx, int(tc[k]))
				acc.focus_ok += mx
				acc.focus_n += shooters
				var rf := float(reloading) / float(shooters)
				acc.rel_max = maxf(acc.rel_max, rf)
				acc.rel_sum += rf
				acc.rel_n += 1
			if case == "field" and kill_at >= 0:
				var bucket = pre if t < kill_at and t >= kill_at - 100 else (post if t >= kill_at and t < kill_at + 100 else null)
				if bucket != null:
					bucket.drift += dr
					bucket.n += 1
					bucket.thr_ok += tok
					bucket.thr_n += tn
	var ns := float(maxi(int(acc.samples) * logged.size(), 1))
	var out := {"case": case, "ticks": ticks, "every": every, "seed": seed, "squads": logged.size(),
		"drift_tiles": snappedf(acc.drift / ns, 0.01),
		"cover_pct": snappedf(100.0 * acc.cover / float(maxi(acc.cover_n, 1)), 0.1),
		"threat_pct": snappedf(100.0 * acc.thr_ok / float(maxi(acc.thr_n, 1)), 0.1), "threat_n": acc.thr_n,
		"focus_pct": snappedf(100.0 * acc.focus_ok / float(maxi(acc.focus_n, 1)), 0.1),
		"reload_max_pct": snappedf(100.0 * acc.rel_max, 0.1),
		"reload_mean_pct": snappedf(100.0 * acc.rel_sum / float(maxi(acc.rel_n, 1)), 0.1),
		"hash": w.state_hash().left(16), "alive_h": _count(w, hfid), "alive_m": _count(w, mfid)}
	if case == "field":
		out["leader_killed"] = kill.killed
		out["leaderless_ticks"] = kill.leaderless_ticks
		out["pre_drift"] = snappedf(pre.drift / float(maxi(pre.n, 1)), 0.01)
		out["post_drift"] = snappedf(post.drift / float(maxi(post.n, 1)), 0.01)
		out["pre_threat_pct"] = snappedf(100.0 * pre.thr_ok / float(maxi(pre.thr_n, 1)), 0.1)
		out["post_threat_pct"] = snappedf(100.0 * post.thr_ok / float(maxi(post.thr_n, 1)), 0.1)
	return out


static func _wall_r(w: SimWorld, sp: Vector2) -> float:
	var L0 = w.map.get("lp", {})
	if L0 is Dictionary and (L0 as Dictionary).has("rings") and not (L0.rings as Array).is_empty():
		return float((L0.rings[0].rect as Rect2i).size.y) * 0.5
	return 40.0


static func _count(w: SimWorld, fid: int) -> int:
	var n := 0
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind == "unit" and int(e.owner) == fid:
			n += 1
	return n
