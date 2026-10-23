## 引擎日志适配器：将错误转入运行时间线，并对需要上报的异常做线程安全去重。
class_name LogUtil
extends Logger

# ---- 去重与栈格式常量 ----
## 去重窗口（毫秒）：同一处错误 5000 毫秒（5 秒）内只上报一次，防止刷屏打爆 Crashlytics
const _DEDUP_WINDOW_MS: int = 5000

const _PRINT_MAX_LEN: int = 500

## 每条 backtrace 前的标题行，沿用 Godot 原生格式（最近调用在前）
const _BACKTRACE_HEADER: String = "GDScript backtrace (most recent call first):"

const _ENGINE_FRAME_PREFIX: String = "res://__engine__/"

const _IGNORED_MSG_SUBSTRINGS: PackedStringArray = [
	"invalid utf16 surrogate",
	"button == MouseButton::NONE",
	"Connection to remote host failed",
	"TLS handshake error",
]

# ---- 去重状态（多线程安全） ----
## 保护 _recent 的互斥锁：日志回调可能来自非主线程
var _mutex := Mutex.new()

## 已上报记录表：key = hash(消息 + 首条 backtrace) → 上次上报时的毫秒时间戳
var _recent: Dictionary = {}

var _recent_timeline: Dictionary = {}


## 接收引擎错误回调；先写时间线，再筛选脚本错误并去重上报 Crashlytics。
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
	_forward_to_timeline(function, file, line, code, rationale, error_type, script_backtraces)

	if OS.has_feature("dev"):
		return

	if script_backtraces.is_empty():
		return

	if error_type != Logger.ERROR_TYPE_ERROR and error_type != Logger.ERROR_TYPE_SCRIPT:
		return

	var msg: String = _build_msg(code, rationale)

	for ignored in _IGNORED_MSG_SUBSTRINGS:
		if ignored in msg:
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
	var emitted_frames: int = 0
	for bt in script_backtraces:
		stack_lines.append(_BACKTRACE_HEADER)
		var frame_count: int = bt.get_frame_count()
		for i in range(frame_count):
			stack_lines.append(
				(
					"    [%d] %s (%s:%d)"
					% [i, bt.get_frame_function(i), bt.get_frame_file(i), bt.get_frame_line(i)]
				)
			)
		emitted_frames += frame_count

	if emitted_frames == 0:
		stack_lines = PackedStringArray(
			[_BACKTRACE_HEADER, _synth_engine_frame(function, file, line)]
		)
	var stack: String = "\n".join(stack_lines)

	if not is_instance_valid(UniKitManager):
		return

	UniKitManager.log_exception(msg, stack)


## 筛选警告与错误并去重，用延迟调用把事件派发切回主线程。
func _forward_to_timeline(
	function: String,
	file: String,
	line: int,
	code: String,
	rationale: String,
	error_type: int,
	script_backtraces: Array[ScriptBacktrace]
) -> void:
	var event_name: String = ""
	match error_type:
		Logger.ERROR_TYPE_ERROR, Logger.ERROR_TYPE_SCRIPT:
			event_name = EventName.LOG_ERROR
		Logger.ERROR_TYPE_WARNING:
			event_name = EventName.LOG_WARNING
		_:
			return
	var msg: String = _build_msg(code, rationale)

	if msg.begins_with("RuntimeTimelineLog:"):
		return

	for ignored in _IGNORED_MSG_SUBSTRINGS:
		if ignored in msg:
			return

	_mutex.lock()
	var now_ms: int = Time.get_ticks_msec()
	var bt_key: String = script_backtraces[0].format() if not script_backtraces.is_empty() else ""
	var key: int = hash(msg + bt_key)
	var last: int = _recent_timeline.get(key, -_DEDUP_WINDOW_MS - 1)
	if now_ms - last < _DEDUP_WINDOW_MS:
		_mutex.unlock()
		return
	_recent_timeline[key] = now_ms
	if _recent_timeline.size() > 200:
		_recent_timeline.clear()
	_mutex.unlock()
	var where: Array = _timeline_where(file, line, function, script_backtraces)
	call_deferred("_emit_timeline_log", event_name, msg, where[0], where[1])


## 向 EventBus 发出日志事件，保留消息、位置和函数名。
func _emit_timeline_log(event_name: String, msg: String, at: String, fn: String) -> void:
	if not is_instance_valid(EventBus):
		return
	EventBus.emit_event(event_name, {"msg": msg, "at": at, "fn": fn})


## 优先采用脚本栈第一帧定位，没有脚本帧时回退到引擎提供的位置。
func _timeline_where(
	file: String, line: int, function: String, script_backtraces: Array[ScriptBacktrace]
) -> Array:
	for bt in script_backtraces:
		if bt.get_frame_count() > 0:
			return [
				"%s:%d" % [bt.get_frame_file(0), bt.get_frame_line(0)], bt.get_frame_function(0)
			]
	return ["%s:%d" % [file, line], function]


## 合并引擎错误码文字与原因，避免其中一项为空时留下多余分隔符。
func _build_msg(code: String, rationale: String) -> String:
	if not rationale.is_empty() and not code.is_empty():
		return "%s | %s" % [code, rationale]
	if not rationale.is_empty():
		return rationale
	return code


## 接收普通打印，截断过长消息并去重，避免时间线自己记录自己。
func _log_message(message: String, error: bool) -> void:
	if error:
		return
	var msg: String = message.strip_edges()
	if msg.is_empty():
		return

	if msg.begins_with("RuntimeTimelineLog:"):
		return

	if msg.length() > _PRINT_MAX_LEN:
		msg = msg.substr(0, _PRINT_MAX_LEN) + "…(截断)"

	_mutex.lock()
	var now_ms: int = Time.get_ticks_msec()
	var key: int = hash(msg)
	var last: int = _recent_timeline.get(key, -_DEDUP_WINDOW_MS - 1)
	if now_ms - last < _DEDUP_WINDOW_MS:
		_mutex.unlock()
		return
	_recent_timeline[key] = now_ms
	if _recent_timeline.size() > 200:
		_recent_timeline.clear()
	_mutex.unlock()
	call_deferred("_emit_timeline_print", msg)


## 把普通打印发布为时间线事件；事件总线尚不可用时跳过。
func _emit_timeline_print(msg: String) -> void:
	if not is_instance_valid(EventBus):
		return
	EventBus.emit_event(EventName.LOG_PRINT, {"msg": msg})


## 在脚本栈为空时构造可读的引擎位置，保留排查入口。
func _synth_engine_frame(function: String, file: String, line: int) -> String:
	var safe_func: String = function if not function.is_empty() else "unknown"
	var safe_file: String = file.replace(":", "_")
	if safe_file.is_empty():
		safe_file = "unknown"
	return "    [0] %s (%s%s:%d)" % [safe_func, _ENGINE_FRAME_PREFIX, safe_file, maxi(line, 0)]
