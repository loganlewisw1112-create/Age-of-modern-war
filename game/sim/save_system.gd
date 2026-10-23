extends RefCounted
## Save / load for SimWorld (CONTRACTS section 8). No class_name: use
##   const SaveSystem = preload("res://sim/save_system.gd")
##
## File format (binary, one file):
##   line 1 : JSON header {"magic","format","schema_version","tick","date","body_bytes","body_sha256"} + "\n"
##   rest   : var_to_bytes(world.to_dict())   (the body; everything after the first newline)
## Why bytes and not var_to_str (CONTRACTS section 8 said text): var_to_str is LOSSY for
## 64-bit floats (found 2026-10-22: map.river_params, entity facing/progress come back one
## ulp off, which changes state_hash). var_to_bytes round-trips doubles exactly.
## The header is NOT part of the simulation state: the wall-clock "date" lives only
## in the header, so state_hash() and determinism are unaffected.
##
## Saves are atomic: write "<path>.tmp", re-read and fully verify it, move the previous
## file to "<path>.bak", then rename the tmp file over "<path>".
## NOTE: the static func named load() intentionally mirrors the contract. Inside this
## file never call the global load(); use ResourceLoader.load() if ever needed.

const MAGIC := "RTS_AOMW_SAVE"
const FORMAT := 2
const SAVE_DIR := "user://saves"
## Keys from_dict() reads unconditionally; a file missing any of them is rejected up front.
const REQUIRED_KEYS := ["schema_version", "tick", "seed_value", "rng_state", "next_id",
	"next_cmd_id", "map", "factions", "entities", "pending", "cfg", "match_state",
	"fog", "memory", "ai_state", "sys_state"]


static func slot_path(slot: int) -> String:
	return "%s/slot_%d.sav" % [SAVE_DIR, slot]


static func sha(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


## Builds the file bytes from a header dict and a body. Exposed for tests.
static func assemble(header: Dictionary, body: PackedByteArray) -> PackedByteArray:
	var out := JSON.stringify(header).to_utf8_buffer()
	out.append(10)
	out.append_array(body)
	return out


## Serialises a world dict to the on-disk bytes (header + body). Exposed for tests.
static func encode_dict(d: Dictionary, date_text: String = "") -> PackedByteArray:
	var body := var_to_bytes(d)
	var header := {
		"magic": MAGIC,
		"format": FORMAT,
		"schema_version": int(d.get("schema_version", -1)),
		"tick": int(d.get("tick", -1)),
		"date": date_text if date_text != "" else Time.get_datetime_string_from_system(false, true),
		"body_bytes": body.size(),
		"body_sha256": sha(body),
	}
	return assemble(header, body)


## Parses file bytes. Returns {"ok": bool, "reason": String, "header": Dictionary, "dict": Dictionary}.
## Verifies magic, format, size, checksum, schema_version and required keys.
static func decode_bytes(data: PackedByteArray, want_body: bool = true) -> Dictionary:
	var res := {"ok": false, "reason": "", "header": {}, "dict": {}}
	var nl := data.find(10)
	if nl <= 0:
		res.reason = "Save file is empty or has no header."
		return res
	var header_text := data.slice(0, nl).get_string_from_utf8()
	var jp := JSON.new()  # instance parse: no engine error spam on garbage input
	var parsed = jp.data if jp.parse(header_text) == OK else null
	if typeof(parsed) != TYPE_DICTIONARY:
		res.reason = "Save file header is not valid."
		return res
	var header: Dictionary = parsed
	res.header = header
	if header.get("magic", "") != MAGIC:
		res.reason = "Not a save file for this game."
		return res
	if int(header.get("format", -1)) != FORMAT:
		res.reason = "Unsupported save format %s." % str(header.get("format"))
		return res
	if int(header.get("schema_version", -1)) != SimWorld.SCHEMA_VERSION:
		res.reason = "Unsupported save schema_version %s (this build reads %d)." % [str(header.get("schema_version")), SimWorld.SCHEMA_VERSION]
		return res
	if not want_body:
		res.ok = true
		return res
	var body := data.slice(nl + 1)
	if body.size() != int(header.get("body_bytes", -1)):
		res.reason = "Save file is truncated or has been modified (size mismatch)."
		return res
	if sha(body) != String(header.get("body_sha256", "")):
		res.reason = "Save file is corrupt (checksum mismatch)."
		return res
	var d = bytes_to_var(body)  # no objects: a hostile file cannot instantiate anything
	if typeof(d) != TYPE_DICTIONARY:
		res.reason = "Save file body could not be parsed."
		return res
	for k in REQUIRED_KEYS:
		if not d.has(k):
			res.reason = "Save file is missing '%s'." % k
			return res
	if int(d.schema_version) != SimWorld.SCHEMA_VERSION:
		res.reason = "Unsupported save schema_version %s inside the file." % str(d.schema_version)
		return res
	res.dict = d
	res.ok = true
	return res


## Writes w to path atomically. Returns "" on success, else a human-readable reason.
## On any failure the previous save at `path` is left untouched.
static func save(w: SimWorld, path: String) -> String:
	if w == null:
		return "No world to save."
	var data := encode_dict(w.to_dict())
	# Prove the payload parses back before touching the destination.
	var check := decode_bytes(data)
	if not check.ok:
		return "Refusing to save: state does not round-trip (%s)" % check.reason
	var dir_path := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var mk := DirAccess.make_dir_recursive_absolute(dir_path)
		if mk != OK:
			return "Cannot create save folder '%s' (error %d)." % [dir_path, mk]
	var tmp := path + ".tmp"
	var bak := path + ".bak"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return "Cannot write '%s' (error %d)." % [tmp, FileAccess.get_open_error()]
	f.store_buffer(data)
	f.flush()
	f.close()
	# Verify what actually landed on disk.
	var back := decode_bytes(FileAccess.get_file_as_bytes(tmp))
	if not back.ok:
		DirAccess.remove_absolute(tmp)
		return "Verification of the written file failed: %s" % back.reason
	if back.header.get("body_sha256", "") != check.header.get("body_sha256", "x"):
		DirAccess.remove_absolute(tmp)
		return "Verification of the written file failed: checksum differs from the in-memory save."
	var had_old := FileAccess.file_exists(path)
	if had_old:
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		var r1 := DirAccess.rename_absolute(path, bak)
		if r1 != OK:
			DirAccess.remove_absolute(tmp)
			return "Cannot keep the previous save as .bak (error %d); save aborted." % r1
	var r2 := DirAccess.rename_absolute(tmp, path)
	if r2 != OK:
		if had_old:
			DirAccess.rename_absolute(bak, path)  # restore the previous save
		DirAccess.remove_absolute(tmp)
		return "Cannot move the new save into place (error %d)." % r2
	return ""


## Non-erroring loader: returns {"world": SimWorld or null, "reason": String}.
static func try_load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"world": null, "reason": "Save file '%s' does not exist." % path}
	var dec := decode_bytes(FileAccess.get_file_as_bytes(path))
	if not dec.ok:
		return {"world": null, "reason": dec.reason}
	var w := SimWorld.from_dict(dec.dict)
	if w == null:
		return {"world": null, "reason": "The save could not be restored (schema mismatch)."}
	return {"world": w, "reason": ""}


## Loads a save. Returns null and push_error()s on a missing, corrupt or wrong-schema file.
static func load(path: String) -> SimWorld:
	var r := try_load(path)
	if r.world == null:
		push_error("SaveSystem.load('%s'): %s" % [path, r.reason])
	return r.world


## Lists readable save slots (header only; the body is not parsed).
## Each entry: {path, slot (file base name), tick, date, valid}. Sorted by file name.
static func list_slots(dir_path: String = SAVE_DIR) -> Array:
	var out := []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	var names := []
	for fname in d.get_files():
		if fname.ends_with(".sav"):
			names.append(fname)
	names.sort()
	for fname in names:
		var p := dir_path.path_join(fname)
		var fa := FileAccess.open(p, FileAccess.READ)
		var head := PackedByteArray()
		if fa != null:
			head = fa.get_buffer(mini(4096, int(fa.get_length())))  # header is the first line
			fa.close()
		var dec := decode_bytes(head, false)
		if dec.ok:
			out.append({"path": p, "slot": fname.get_basename(), "tick": int(dec.header.tick),
				"date": String(dec.header.get("date", "")), "valid": true})
		else:
			out.append({"path": p, "slot": fname.get_basename(), "tick": -1, "date": "", "valid": false})
	return out
