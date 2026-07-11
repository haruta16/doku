class_name InGameLogBuffer
extends Logger

enum Level { INFO, WARN, ERROR }

static var instance: InGameLogBuffer = null

const MAX_ENTRIES: int = 500

var _entries: Array[Dictionary] = []
var _highest_level: int = Level.INFO
var _mutex := Mutex.new()


func get_entries() -> Array[Dictionary]:
	_mutex.lock()
	var out: Array[Dictionary] = _entries.duplicate()
	_mutex.unlock()
	return out


func get_entry_count() -> int:
	_mutex.lock()
	var c: int = _entries.size()
	_mutex.unlock()
	return c


func clear_entries() -> void:
	_mutex.lock()
	_entries.clear()
	_highest_level = Level.INFO
	_mutex.unlock()


func get_highest_level() -> int:
	_mutex.lock()
	var lv: int = _highest_level
	_mutex.unlock()
	return lv


func _append(level: Level, text: String) -> void:
	_mutex.lock()
	if _entries.size() >= MAX_ENTRIES:
		_entries.remove_at(0)
	_entries.append({"time_ms": Time.get_ticks_msec(), "level": level, "text": text})
	if level > _highest_level:
		_highest_level = level
	_mutex.unlock()


func _log_message(message: String, error: bool) -> void:
	var level: Level = Level.ERROR if error else Level.INFO
	_append(level, message.strip_edges())


func _log_error(
	_function: String,
	_file: String,
	_line: int,
	code: String,
	rationale: String,
	_editor_notify: bool,
	error_type: int,
	script_backtraces: Array[ScriptBacktrace]
) -> void:
	var level: Level = Level.WARN if error_type == Logger.ERROR_TYPE_WARNING else Level.ERROR
	var msg: String
	if not rationale.is_empty() and not code.is_empty():
		msg = "%s | %s" % [code, rationale]
	elif not rationale.is_empty():
		msg = rationale
	else:
		msg = code
	if not script_backtraces.is_empty():
		msg += " @ " + script_backtraces[0].format()
	_append(level, msg)
