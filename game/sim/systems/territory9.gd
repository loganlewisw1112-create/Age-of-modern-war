extends RefCounted
## Town-cell control and civilian support consequences.

const KEY := "territory9"


static func _st(w: SimWorld) -> Dictionary:
	if not w.sys_state.has(KEY):
		var support := {}
		for fid in w.factions:
			support[str(fid)] = 100
		w.sys_state[KEY] = {"cells": {}, "support": support, "civ_harm": {}}
	return w.sys_state[KEY]


static func hold_cell(w: SimWorld, fid: int, cell: Vector2i, town: String = "town") -> void:
	_st(w).cells["%d,%d" % [cell.x, cell.y]] = {"fid": fid, "town": town}
	w.emit("Territory9Held", {"fid": fid, "cell": [cell.x, cell.y], "town": town})


static func territory_score(w: SimWorld, fid: int) -> int:
	var n := 0
	for rec in (_st(w).cells as Dictionary).values():
		if int(rec.get("fid", -1)) == fid:
			n += 1
	return n


static func civilian_harm(w: SimWorld, fid: int, amount: int = 1) -> void:
	var s := _st(w)
	var key := str(fid)
	var loss := maxi(amount, 1) * 5
	s.support[key] = maxi(0, int(s.support.get(key, 100)) - loss)
	s.civ_harm[key] = int(s.civ_harm.get(key, 0)) + maxi(amount, 1)
	w.emit("CivilianHarm", {"fid": fid, "amount": amount, "support": int(s.support[key])})


static func support(w: SimWorld, fid: int) -> int:
	return int(_st(w).support.get(str(fid), 100))


static func tick(_w: SimWorld) -> void:
	pass
