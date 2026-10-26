extends RefCounted
## G6.1 voice limiter + variant rotation (owner: AUDIO61). Pure logic on an explicit clock (seconds), so tests can
## drive it headless: request(id, cat, now, dur) -> true when a voice may start (and reserves it until now + dur).
## Limits: per category (MAX), per sound id per frame (PER_ID_FRAME, avoids phasing stacks), plus a global cap.

const MAX := {"gun": 10, "impact": 6, "explosion": 6, "engine": 4, "ui": 4, "alert": 2, "radio": 1}
const GLOBAL_MAX := 28
const PER_ID_FRAME := 3

var _active: Dictionary = {}      # cat -> Array of end times
var _frame_t := -1.0
var _frame_ids: Dictionary = {}   # sound id -> starts this frame
var _rot: Dictionary = {}         # sound id -> last variant index
var started := 0
var refused := 0
var peak: Dictionary = {}         # cat -> highest concurrent count seen
var _pruned_t := -1.0
var _total := 0


func _prune(now: float) -> void:
	if now == _pruned_t:
		return
	_pruned_t = now
	_total = 0
	for c in _active:
		var arr: Array = _active[c]
		var keep: Array = []
		for t in arr:
			if float(t) > now:
				keep.append(t)
		_active[c] = keep
		_total += keep.size()


func active(cat: String, now: float) -> int:
	_prune(now)
	return (_active.get(cat, []) as Array).size()


func total(now: float) -> int:
	_prune(now)
	return _total


## Cheap pre-check (no reservation): would request(id, cat, now, ..) be accepted? Callers skip the expensive part
## (distance, variant pick) when the category is already full, which keeps a 2k-unit firefight cheap.
func would_accept(id: String, cat: String, now: float) -> bool:
	_prune(now)
	if (_active.get(cat, []) as Array).size() >= cap(cat) or _total >= GLOBAL_MAX:
		return false
	return now != _frame_t or int(_frame_ids.get(id, 0)) < PER_ID_FRAME


func cap(cat: String) -> int:
	return int(MAX.get(cat, 4))


func request(id: String, cat: String, now: float, dur: float) -> bool:
	if now != _frame_t:
		_frame_t = now
		_frame_ids.clear()
	_prune(now)
	var arr: Array = _active.get(cat, [])
	if arr.size() >= cap(cat) or total(now) >= GLOBAL_MAX or int(_frame_ids.get(id, 0)) >= PER_ID_FRAME:
		refused += 1
		return false
	arr.append(now + maxf(0.05, dur))
	_active[cat] = arr
	_total += 1
	_frame_ids[id] = int(_frame_ids.get(id, 0)) + 1
	started += 1
	peak[cat] = maxi(int(peak.get(cat, 0)), arr.size())
	return true


## Next variant index of n for a sound id: round robin from a per-id start, never the same twice in a row.
func next_variant(id: String, n: int) -> int:
	if n <= 1:
		return 0
	var last := int(_rot.get(id, (id.hash() & 0xffff) % n - 1))
	var v := posmod(last + 1, n)
	_rot[id] = v
	return v


func release_all() -> void:
	_active.clear()
	_total = 0
