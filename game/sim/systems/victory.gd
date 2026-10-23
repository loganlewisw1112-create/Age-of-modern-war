extends RefCounted
## Victory (owner: agent B / sim-mil). HQ elimination and endless.
## Contract: docs/CONTRACTS.md section 5.
## - A side with no HQ building (built or unfinished; def with is_hq) becomes alive=false and
##   SideEliminated {faction} is emitted once.
## - hq_elimination: when at most one side is alive, match_state = {ended, winner, reason, end_tick}
##   and MatchEnded {winner, reason} is emitted once (w.step() stops ticking after that).
## - endless: sides are still eliminated, the match never ends.

static var _hq_defs: Dictionary = {}


static func _is_hq(def_id: String) -> bool:
	if not _hq_defs.has(def_id):
		_hq_defs[def_id] = bool(Content.building(def_id).get("is_hq", false))
	return _hq_defs[def_id]


static func tick(w: SimWorld) -> void:
	if w.match_state.get("ended", false):
		return
	var has_hq := {}
	for id in w.entities:
		var e: Dictionary = w.entities[id]
		if e.kind == "building" and _is_hq(String(e.def)):
			has_hq[int(e.owner)] = true
	for fid in w.factions:
		var f: Dictionary = w.factions[fid]
		if f.alive and not has_hq.has(int(fid)):
			f.alive = false
			w.emit("SideEliminated", {"faction": int(fid)})
	if String(w.cfg.get("victory", "hq_elimination")) != "hq_elimination":
		return
	var alive := []
	for fid in w.factions:
		if w.factions[fid].alive:
			alive.append(int(fid))
	if alive.size() <= 1:
		var winner: int = alive[0] if alive.size() == 1 else SimWorld.NEUTRAL
		w.match_state.ended = true
		w.match_state.winner = winner
		w.match_state.reason = "hq_elimination"
		w.match_state.end_tick = w.tick
		w.emit("MatchEnded", {"winner": winner, "reason": "hq_elimination"})
