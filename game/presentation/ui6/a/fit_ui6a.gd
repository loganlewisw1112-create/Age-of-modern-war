extends RefCounted
## UI6a (G6): fixtures for the G6 panels: the fit test's screens (tools/ui_fit_test.gd via
## presentation/ui5/kit/fit_screens.gd) and tests/test_ui6a.gd share one world builder.
## g6_world(): a default 2-side match where side 0 has a built Company HQ, supply for two companies,
## two trained Rifle Companies (platoon size), a Commander, an army of both companies and an AI
## Commander in slot C1, all through the real commands (train_company, train_commander, form_army,
## set_ai_commander). Training time is skipped by finishing the queue entries (fixture only).

const Companies = preload("res://sim/systems/companies.gd")
const ScaledLayer = preload("res://presentation/hud/scaled_layer.gd")
const HT = preload("res://presentation/hud/hud_theme.gd")
const MatchViewScript = preload("res://presentation/match_view.gd")
const HudScript = preload("res://presentation/hud/hud.gd")
const MainMenuScript = preload("res://presentation/menu/main_menu.gd")

const NAMES := ["ui6a_market", "ui6a_army", "ui6a_forces", "ui6a_commanders", "ui6a_hud_company", "ui6a_hud_company_hq",
	"ui6a_menu_survival"]
const PANEL_OF := {"ui6a_market": "market", "ui6a_army": "army", "ui6a_forces": "forces", "ui6a_commanders": "commanders"}

static var _w: SimWorld = null


static func _submit(w: SimWorld, cmd: Dictionary) -> String:
	var r := w.submit(cmd)
	w.step()
	return "" if bool(r.get("ok", false)) else String(r.get("reason", "rejected"))


## Finishes every queued company / commander entry (one per HQ per tick, so a few ticks).
static func finish_training(w: SimWorld) -> void:
	for i in 12:
		var st: Dictionary = w.sys_state.get("companies", {})
		if (st.get("training", []) as Array).is_empty():
			return
		for t in st.training:
			t.progress = 1.0
		w.step()


static func add_supply(w: SimWorld, fid: int, need: int) -> void:
	var best := ""
	var bc := 0
	var fac := Companies.faction_of(w, fid)
	for id in Content.ids("buildings"):
		var d := Content.building(String(id))
		if String(d.get("faction", "")) == fac and int(d.get("pop_cap", 0)) > bc and int(d.get("size", 1)) <= 2:
			best = String(id)
			bc = int(d.pop_cap)
	if best == "":
		return
	var hq: Dictionary = w.buildings_of(fid, Content.role(fac, "hq"))[0] if not w.buildings_of(fid, Content.role(fac, "hq")).is_empty() else {}
	var base: Vector2i = hq.get("cell", Vector2i(10, 10))
	var n := mini(12, int(ceil(float(need) / float(bc))))
	for i in n:
		w.spawn_building(best, fid, base + Vector2i(-8 + (i % 6) * 3, 7 + (i / 6) * 3), true)
	w.step()


static func g6_world() -> SimWorld:
	if _w != null:
		return _w
	var cfg := SimWorld.default_config()
	cfg.sides[1].ai = false
	var w := SimWorld.new_match(cfg)
	var fid := 0
	var fac := Companies.faction_of(w, fid)
	var hqdef := String(Companies.leaders(fac).get("hq", ""))
	var hq: Dictionary = w.buildings_of(fid, Content.role(fac, "hq"))[0]
	w.spawn_building(hqdef, fid, hq.cell + Vector2i(6, -6), true)
	w.factions[fid].credits = int(w.factions[fid].credits) + 150000
	for k in ["salvage", "ore", "fuel", "ammo"]:
		w.factions[fid].stock[k] = int(w.factions[fid].stock.get(k, 0)) + 20000
	add_supply(w, fid, 200)
	var chq := Companies.hq_of(w, fid)
	var tid: String = Companies.templates_for(fid, w)[0]
	for i in 2:
		_submit(w, {"type": "train_company", "issuer": fid, "building_id": int(chq.id), "template": tid, "size": "platoon"})
	_submit(w, {"type": "train_commander", "issuer": fid, "building_id": int(chq.id)})
	finish_training(w)
	var cids: Array = []
	for c in Companies.companies_of(w, fid):
		cids.append(int(c.id))
	var cmds := Companies.commanders_of(w, fid)
	if cids.size() >= 2 and not cmds.is_empty():
		_submit(w, {"type": "form_army", "issuer": fid, "commander_id": int(cmds[0]), "company_ids": cids.slice(0, 2)})
	if not cids.is_empty():
		_submit(w, {"type": "set_ai_commander", "issuer": fid, "slot": 0, "target": {"formation": "co:%d" % int(cids[0])},
			"playstyle": "aggressive", "stance": "balanced", "objective": {"type": "hold"}})
	_w = w
	return w


static func _hud(vp: Node, sc: float, w: SimWorld) -> Array:
	var mv = MatchViewScript.new()
	mv.world = w
	mv.paused = true
	vp.add_child(mv)
	var hud = HudScript.new()
	vp.add_child(hud)
	hud.setup(mv, sc)
	return [mv, hud]


## Async: builds one ui6a_* screen inside vp (same layers as presentation/main.gd).
static func build(nm: String, vp: SubViewport, sc: float, tree: SceneTree) -> bool:
	if nm == "ui6a_menu_survival":
		var l = ScaledLayer.new()
		l.layer = 20
		vp.add_child(l)
		l.root.theme = HT.make_theme()
		l.set_ui_scale(sc)
		var m = MainMenuScript.new()
		l.root.add_child(m)
		m.set_save_system_available(true)
		m.set_scale_index(sc)
		m.victory.select_mode("repel_waves")
		m._on_changed_num(0)
		return true
	if not NAMES.has(nm):
		return false
	var w := g6_world()
	var pair := _hud(vp, sc, w)
	var mv = pair[0]
	var hud = pair[1]
	await tree.process_frame
	if PANEL_OF.has(nm):
		hud.ui6a.open(String(PANEL_OF[nm]))
	elif nm == "ui6a_hud_company":
		var cs := Companies.companies_of(w, 0)
		if not cs.is_empty():
			mv.select_ids(Companies.units_of(w, cs[0]))
	elif nm == "ui6a_hud_company_hq":
		var chq := Companies.hq_of(w, 0)
		if not chq.is_empty():
			mv.select_ids([int(chq.id)])
	await tree.process_frame
	hud._refresh()
	await tree.process_frame
	hud.ui6a.update(w, 0)
	return true
