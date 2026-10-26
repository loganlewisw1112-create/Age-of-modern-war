extends RefCounted
## G6.1 radio queue (owner: AUDIO61). One line at a time; highest priority first (officer_down > artillery >
## contact > ... > orders), FIFO within a priority. Per-category cooldown, queue cap, stale lines dropped.
## Pure logic on an explicit clock (seconds): push(...), then poll(now) returns the line to start (or {}).

const MAX_QUEUE := 6
const STALE_S := 10.0         # a queued line older than this is dropped (news is old)
const GAP_S := 0.35           # silence between two transmissions

var _q: Array = []            # [{line, cat, prio, at, seq}]
var _seq := 0
var _busy_until := 0.0
var _last_cat: Dictionary = {}  # cat -> time it last started
var playing: Dictionary = {}
var played: Array = []        # history [{line, cat, at}] (tests / playtest log; capped)
var dropped := 0


func push(line: String, cat: String, prio: int, now: float, cooldown_s: float = 0.0) -> bool:
	if line == "":
		return false
	if _last_cat.has(cat) and now - float(_last_cat[cat]) < cooldown_s:
		dropped += 1
		return false
	for q in _q:
		if String(q.cat) == cat:
			dropped += 1  # one pending line per category is enough
			return false
	_seq += 1
	_q.append({"line": line, "cat": cat, "prio": prio, "at": now, "seq": _seq})
	_q.sort_custom(func(a, b): return int(a.prio) > int(b.prio) or (int(a.prio) == int(b.prio) and int(a.seq) < int(b.seq)))
	while _q.size() > MAX_QUEUE:
		_q.pop_back()
		dropped += 1
	return true


func busy(now: float) -> bool:
	return now < _busy_until


func size() -> int:
	return _q.size()


func peek() -> Dictionary:
	return _q[0] if not _q.is_empty() else {}


## Line to start now ({} = nothing / still transmitting). dur_of: Callable(line) -> seconds.
func poll(now: float, dur_of: Callable) -> Dictionary:
	if busy(now):
		return {}
	playing = {}
	while not _q.is_empty():
		var it: Dictionary = _q.pop_front()
		if now - float(it.at) > STALE_S and int(it.prio) < 100:
			dropped += 1
			continue
		var d: float = float(dur_of.call(String(it.line))) if dur_of.is_valid() else 2.0
		_busy_until = now + d + GAP_S
		_last_cat[String(it.cat)] = now
		playing = it
		played.append({"line": it.line, "cat": it.cat, "at": now})
		if played.size() > 200:
			played.pop_front()
		return it
	return {}


func clear() -> void:
	_q.clear()
	playing = {}
	_busy_until = 0.0
