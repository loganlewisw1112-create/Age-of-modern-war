extends SceneTree
## DEBUG TOOL (owner: AI7-DOC), never loaded by the game. Owner checkpoint (CONTRACTS_G6 section 16, task 7):
## one AI company (3 platoons + captain) assaults a hill held by an enemy squad, driven by the doctrine only.
##   godot --headless --path . --script res://sim/ai/doctrine/doc_demo.gd
## Writes to .plan/shots/AI7-DOC/: demo_start.save (the start state, SaveSystem format: deterministic, so
## the run replays from it), demo_replay.json (positions every 20 ticks + every AiDecision), demo_replay.html
## (self-contained player: open in a browser) and frame_NN_<tag>.png (top-down frames at each decision;
## blue = base of fire, green = assault, orange = flank, white = captain, red = enemy; brown = hill).

const Doctrine = preload("res://sim/ai/doctrine/doctrine.gd")
const D = preload("res://sim/ai/doctrine/doc_util.gd")
const Companies = preload("res://sim/systems/companies.gd")
const Ops = preload("res://sim/systems/ops.gd")
const Movement = preload("res://sim/systems/movement.gd")
const AiController = preload("res://sim/ai/ai_controller.gd")
const SaveSystem = preload("res://sim/save_system.gd")
const OUT := "res://.plan/shots/AI7-DOC/"
const FID := 1
const PX := 8
const ROLE_COL := [Color(0.25, 0.5, 1.0), Color(0.2, 0.85, 0.3), Color(1.0, 0.6, 0.1), Color(1, 1, 1), Color(0.95, 0.15, 0.15)]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var c := SimWorld.default_config()
	c.sides[1].ai = false
	var w := SimWorld.new_match(c)
	w.ai_state = {}
	var hill := _arena(w)
	var co := _company(w, hill + Vector2(-38.0, 0.0), 3, 4)
	for off in [Vector2(0.5, -1.0), Vector2(0.5, 1.0), Vector2(-0.8, 0.0), Vector2(1.5, 0.0)]:
		w.spawn_unit("rifleman", 0, hill + off)
	print("DEMO save: ", SaveSystem.save(w, ProjectSettings.globalize_path(OUT + "demo_start.save")))
	var st := AiController.new_state(w, FID)
	var d := D.dstate(st)
	d.force_obj = hill
	d.force_attack = true
	var crop := Rect2i(int(hill.x) - 46, int(hill.y) - 16, 58, 32)
	var samples := []
	var decs := []
	var frames := 0
	var end_t := -1
	var role := {}
	while w.tick < 5000 and (end_t < 0 or w.tick < end_t):
		if w.tick % 10 == 0:
			var n0 := w.events.size()
			Doctrine.think(w, FID, st, {"visible": w.visible_enemies(FID), "units": w.units_of(FID), "buildings": w.buildings_of(FID), "arty": [], "army": [], "busy": {}})
			var forms := Doctrine.formations(w, FID, d, Companies.companies_of(w, FID))
			for f in forms:
				for i in (f.elems as Array).size():
					for id in f.elems[i]:
						role[int(id)] = mini(i, 2)
			role[int(co.captain)] = 3
			var fresh := false
			for i in range(n0, w.events.size()):
				var ev: Dictionary = w.events[i]
				if String(ev.type) == "AiDecision":
					decs.append({"t": w.tick, "tag": String(ev.tag), "reason": String(ev.reason), "ids": ev.unit_ids})
					fresh = true
					if String(ev.tag) == "high_ground_taken" and end_t < 0:
						end_t = w.tick + 500
			var fs: Dictionary = d.forms.get("c%d" % int(co.id), {})
			if w.tick % 20 == 0 or fresh:
				samples.append(_sample(w, fs, role))
			if fresh:
				frames += 1
				_frame(w, crop, fs, role, OUT + "frame_%02d_%s.png" % [frames, String(decs[decs.size() - 1].tag)])
		w.step()
	var hgt := []
	for y in range(crop.position.y, crop.end.y):
		var row := ""
		for x in range(crop.position.x, crop.end.x):
			row += str(w.map.height[y * int(w.map.w) + x]) if w.in_bounds(Vector2i(x, y)) else "1"
		hgt.append(row)
	var rep := {"crop": [crop.position.x, crop.position.y, crop.size.x, crop.size.y], "height": hgt, "hill": [hill.x, hill.y],
		"samples": samples, "decisions": decs, "ticks": w.tick, "tags": d.tags}
	var js := JSON.stringify(rep)
	_write(OUT + "demo_replay.json", js)
	var tpl := FileAccess.get_file_as_string("res://sim/ai/doctrine/doc_demo_player.html")
	_write(OUT + "demo_replay.html", tpl.replace("/*REPLAY*/null", js))
	print("DEMO ticks=%d decisions=%d frames=%d tags=%s" % [w.tick, decs.size(), frames, str(d.tags)])
	for dd in decs:
		print("  t=%d %s: %s" % [int(dd.t), String(dd.tag), String(dd.reason)])
	quit()


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _arena(w: SimWorld) -> Vector2:
	var n := int(w.map.w) * int(w.map.h)
	var t: PackedByteArray = w.map.terrain
	for i in n:
		t[i] = Terrain.GRASS
	w.map.terrain = t
	var h := PackedByteArray()
	h.resize(n)
	h.fill(1)
	var r := PackedByteArray()
	r.resize(n)
	r.fill(1)
	var hc := Vector2i(int(w.map.w) / 2 + 10, int(w.map.h) / 2)
	var knoll := hc + Vector2i(-10, 5)
	for y in range(hc.y - 12, hc.y + 13):
		for x in range(hc.x - 26, hc.x + 8):
			if not w.in_bounds(Vector2i(x, y)):
				continue
			var dd := Vector2(x, y).distance_to(Vector2(hc))
			var dk := Vector2(x, y).distance_to(Vector2(knoll))
			if dd <= 6.5:
				h[y * int(w.map.w) + x] = 3 if dd <= 2.5 else 2
			elif dk <= 3.0:
				h[y * int(w.map.w) + x] = 2
	w.map.height = h
	w.map.ramps = r
	Movement.rebuild_nav(w)
	return Vector2(hc) + Vector2(0.5, 0.5)


func _company(w: SimWorld, at: Vector2, plats: int, per: int) -> Dictionary:
	var cst := Companies.state(w)
	var ost := Ops.state(w)
	var cid := int(cst.next_cid)
	cst.next_cid = cid + 1
	var cap := w.spawn_unit("officer", FID, at)
	w.entities[cap].rank_role = "captain"
	SimWorld.Morale.note_rank()  # G6.1 perf: leader cache
	w.entities[cap].company = cid
	var gids := []
	var els := []
	for k in plats:
		var p0 := at + Vector2(-2.0, float(k) * 4.0 - float(plats - 1) * 2.0)
		var lt := w.spawn_unit("officer", FID, p0)
		var gid := int(ost.next_gid)
		ost.next_gid = gid + 1
		w.entities[lt].rank_role = "lieutenant"
		SimWorld.Morale.note_rank()  # G6.1 perf: leader cache
		w.entities[lt].company = cid
		w.entities[lt].platoon = gid
		var mem := []
		for j in per:
			var u := w.spawn_unit("rifleman", FID, p0 + Vector2(-1.0 - float(j / 2), float(j % 2) * 1.5 - 0.75))
			w.entities[u].company = cid
			w.entities[u].platoon = gid
			mem.append(u)
			els.append({"id": els.size() + 1, "item": "rifleman", "units": [u], "platoon": gid})
		ost.groups[gid] = {"id": gid, "owner": FID, "officer": lt, "members": mem, "mission": {}, "phase": "idle",
			"reason": "", "progress": 0.0, "history": [], "phase_tick": w.tick, "last_report": w.tick, "start": 0,
			"losses": 0, "secure_ticks": 0, "resume": "", "result": "", "parent_company": cid}
		gids.append(gid)
	cst.companies[cid] = {"id": cid, "owner": FID, "template": "demo", "name": "Alpha Company", "size": "company",
		"captain": cap, "platoons": gids, "refill": false, "army": -1, "losses": 0, "elements": els,
		"next_eid": els.size() + 1, "confused_until": 0, "hq": -1}
	return cst.companies[cid]


func _sample(w: SimWorld, fs: Dictionary, role: Dictionary) -> Dictionary:
	var us := []
	var ids := w.entities.keys()
	ids.sort()
	for id in ids:
		var e: Dictionary = w.entities[id]
		if e.kind != "unit":
			continue
		var rc := 4 if int(e.owner) != FID else int(role.get(int(id), 1))
		us.append([int(id), rc, roundi(float(e.pos.x) * 10.0), roundi(float(e.pos.y) * 10.0)])
	var lines := []
	for p in fs.get("lines", []):
		lines.append([snappedf(p.x, 0.1), snappedf(p.y, 0.1)])
	return {"t": w.tick, "phase": String(fs.get("phase", "")), "u": us, "lines": lines}


func _frame(w: SimWorld, crop: Rect2i, fs: Dictionary, role: Dictionary, path: String) -> void:
	var img := Image.create(crop.size.x * PX, crop.size.y * PX, false, Image.FORMAT_RGB8)
	var lv := [Color(0.3, 0.42, 0.3), Color(0.42, 0.55, 0.38), Color(0.55, 0.5, 0.3), Color(0.62, 0.42, 0.25)]
	for y in crop.size.y:
		for x in crop.size.x:
			var c := crop.position + Vector2i(x, y)
			var l := int(w.map.height[c.y * int(w.map.w) + c.x]) if w.in_bounds(c) else 1
			img.fill_rect(Rect2i(x * PX, y * PX, PX, PX), lv[l])
	for p in fs.get("lines", []):
		var q := (Vector2(p) - Vector2(crop.position)) * PX
		img.fill_rect(Rect2i(int(q.x) - 1, int(q.y) - 12, 3, 24), Color(1, 0.95, 0.3))
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind != "unit":
			continue
		var rc := 4 if int(e.owner) != FID else int(role.get(int(id), 1))
		var q := ((e.pos as Vector2) - Vector2(crop.position)) * PX
		img.fill_rect(Rect2i(int(q.x) - 3, int(q.y) - 3, 7, 7), Color(0, 0, 0))
		img.fill_rect(Rect2i(int(q.x) - 2, int(q.y) - 2, 5, 5), ROLE_COL[rc])
	img.save_png(ProjectSettings.globalize_path(path))
