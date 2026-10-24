extends RefCounted
## G4b (UI4B) HUD alerts for the G4b mechanics events (sim/systems/g4b_mech.gd), called from
## hud._on_events (after the step join, so reading w is safe). Only what the local side may know:
##   FireStarted / FireSpread / FireOut  where the player (or an ally) sees the cell (throttled)
##   MineLaid       own or allied only (never reveals an enemy mine)
##   MineDetected   our team found an enemy mine / the enemy found one of ours
##   MineTriggered  our mine went off, or a mine went off where we can see it
##   ChargePlanted / ChargeDetonated  ours, or planted on our (or an ally's) building
##   Deployed / Packed  own units only
## Returns true when the event type is a G4b one (handled, even if no alert was shown).

const HT = preload("res://presentation/hud/hud_theme.gd")
const G3 = preload("res://presentation/hud/g3_faction.gd")

const FIRE_THROTTLE := 20 * 12
const MINE_THROTTLE := 20 * 4
const DEPLOY_THROTTLE := 20 * 3


static func on_event(hud, w: SimWorld, pf: int, ev: Dictionary) -> bool:
	var ty := String(ev.get("type", ""))
	match ty:
		"FireStarted", "FireSpread":
			var c := _cell(ev.get("cell"))
			if _sees(hud, c) and not hud._throttled("g4b_fire", FIRE_THROTTLE, w):
				hud._push_alert("Forest fire!" if ty == "FireStarted" else "The fire is spreading.", HT.AMBER, _mid(c))
		"FireOut":
			var c := _cell(ev.get("cell"))
			if _sees(hud, c) and not hud._throttled("g4b_fire_out", FIRE_THROTTLE, w):
				hud._push_alert("A fire burnt out.", HT.YELLOW, _mid(c))
		"MineLaid":
			if _friendly(w, pf, int(ev.get("owner", -1))) and not hud._throttled("g4b_mine_laid", MINE_THROTTLE, w):
				hud._push_alert("Mine laid.", HT.GREEN, _mid(_cell(ev.get("cell"))))
		"MineDetected":
			var tm := int(ev.get("team", -1))
			var c := _cell(ev.get("cell"))
			var mine = w.entities.get(int(ev.get("id", -1)))
			if tm == G3.team_of(w, pf):
				if not hud._throttled("g4b_mine_found", MINE_THROTTLE, w):
					hud._push_alert("Enemy mine detected!", HT.AMBER, _mid(c))
			elif mine != null and _friendly(w, pf, int(mine.owner)):
				if not hud._throttled("g4b_mine_spotted", MINE_THROTTLE, w):
					hud._push_alert("The enemy found one of our mines.", HT.YELLOW, _mid(c))
		"MineTriggered":
			var c := _cell(ev.get("cell"))
			if int(ev.get("owner", -1)) == pf:
				hud._push_alert("Our mine was triggered.", HT.GREEN, _mid(c))
			elif _sees(hud, c) and not hud._throttled("g4b_mine_hit", MINE_THROTTLE, w):
				hud._push_alert("Mine strike!", HT.RED, _mid(c))
		"ChargePlanted", "ChargeDetonated":
			var ow := int(ev.get("owner", -1))
			var t = w.entities.get(int(ev.get("target", -1)))
			var p = ev.get("pos", t.pos if t != null else null)
			if ow == pf:
				hud._push_alert("Demolition charge planted." if ty == "ChargePlanted" else "Demolition charge detonated.", HT.GREEN, p)
			elif t != null and _friendly(w, pf, int(t.owner)):
				var nm := String(Content.building(String(t.get("def", ""))).get("name", t.get("def", "structure")))
				if ty == "ChargePlanted":
					hud._push_alert("Enemy demolition charge on our %s!" % nm, HT.RED, t.pos)
				else:
					hud._push_alert("Demolition charge hit our %s!" % nm, HT.RED, t.pos)
		"Deployed", "Packed":
			if int(ev.get("owner", -1)) == pf and not hud._throttled("g4b_" + ty, DEPLOY_THROTTLE, w):
				var u = w.entities.get(int(ev.get("id", -1)))
				var nm := String(Content.unit(String(u.def)).get("name", "Unit")) if u != null else "Unit"
				hud._push_alert("%s %s." % [nm, "deployed" if ty == "Deployed" else "packed up"], HT.GREEN)
		_:
			return false
	return true


static func _friendly(w: SimWorld, pf: int, fid: int) -> bool:
	return fid == pf or G3.is_ally(w, pf, fid)


static func _cell(v) -> Vector2i:
	if v is Vector2i:
		return v
	if v is Vector2:
		return Vector2i(floori(v.x), floori(v.y))
	if v is Array and (v as Array).size() >= 2:
		return Vector2i(int(v[0]), int(v[1]))
	return Vector2i(-1, -1)


static func _mid(c: Vector2i) -> Variant:
	return Vector2(c) + Vector2(0.5, 0.5) if c.x >= 0 else null


static func _sees(hud, c: Vector2i) -> bool:
	if c.x < 0 or hud.mv == null:
		return false
	return bool(hud.mv.cell_visible(c))
