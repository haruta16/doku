class_name LogUtil
extends Logger


static func error(msg: String) -> void:
	push_error(msg)
	printerr(msg)


static func warn(msg: String) -> void:
	push_warning(msg)
	printerr("[WARN] " + msg)


const _DEDUP_WINDOW_MS: int = 5000

const _LOG_UTIL_FILE: String = "log_util.gd"

const _BACKTRACE_HEADER: String = "GDScript backtrace (most recent call first):"

var _mutex := Mutex.new()

var _recent: Dictionary = {}


func _log_error(
	function: String,
	file: String,
	line: int,
	code: String,
	rationale: String,
	editor_notify: bool,
	error_type: int,
	script_backtraces: Array[ScriptBacktrace]
) -> void:
	if script_backtraces.is_empty():
		return

	if error_type != Logger.ERROR_TYPE_ERROR and error_type != Logger.ERROR_TYPE_SCRIPT:
		return

	var msg: String
	if not rationale.is_empty() and not code.is_empty():
		msg = "%s | %s" % [code, rationale]
	elif not rationale.is_empty():
		msg = rationale
	else:
		msg = code

	if "invalid utf16 surrogate" in msg:
		return

	if "button == MouseButton::NONE" in msg:
		return

	_mutex.lock()
	var now_ms: int = Time.get_ticks_msec()

	var key: int = hash(msg + script_backtraces[0].format())
	var last: int = _recent.get(key, -_DEDUP_WINDOW_MS - 1)
	if now_ms - last < _DEDUP_WINDOW_MS:
		_mutex.unlock()
		return
	_recent[key] = now_ms

	if _recent.size() > 200:
		_recent.clear()
	_mutex.unlock()

	var stack_lines: PackedStringArray = []
	for bt in script_backtraces:
		stack_lines.append(_BACKTRACE_HEADER)
		var idx: int = 0
		for i in range(bt.get_frame_count()):
			var frame_file: String = bt.get_frame_file(i)

			if idx == 0 and frame_file.ends_with(_LOG_UTIL_FILE):
				continue
			stack_lines.append(
				(
					"    [%d] %s (%s:%d)"
					% [idx, bt.get_frame_function(i), frame_file, bt.get_frame_line(i)]
				)
			)
			idx += 1
	var stack: String = "\n".join(stack_lines)

	if not is_instance_valid(UniKitManager):
		return

	UniKitManager.log_exception(msg, stack)
