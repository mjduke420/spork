extends RefCounted

## Persists game state to user://spork_save.json as plain JSON. All reads are treated
## as untrusted: callers validate/clamp the returned dictionary before applying it.

const PATH := "user://spork_save.json"

static func save(state: Dictionary) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_error("Spork save failed (open): %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(state))
	f.close()

static func load_state() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("Spork save failed (read): %s" % error_string(FileAccess.get_open_error()))
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Spork save file was corrupt; starting fresh.")
		return {}
	return parsed

static func clear() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("spork_save.json")
