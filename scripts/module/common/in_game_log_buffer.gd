# 游戏内日志缓冲区：实现 Godot 的 Logger 接口，把最近 500 条日志留在内存里给作弊面板看
# 由 launcher 创建实例、赋值给 instance 并 OS.add_logger() 注册；跨线程写入，所以带互斥锁
class_name InGameLogBuffer
extends Logger

# 日志级别，数值越大越严重，用于「最近有没有报错」的标记
enum Level { INFO, WARN, ERROR }

static var instance: InGameLogBuffer = null # 全局唯一实例，作弊面板靠它取日志

const MAX_ENTRIES: int = 500 # 环形缓冲上限，超了就丢最旧的一条

var _entries: Array[Dictionary] = [] # 每条形如 {"time_ms", "level", "text"}
var _highest_level: int = Level.INFO # 自上次 clear 以来出现过的最高级别
var _mutex := Mutex.new() # 保护上面两个字段：Logger 回调可能来自别的线程


# 取一份日志快照（拷贝，外部随便改不影响缓冲）
func get_entries() -> Array[Dictionary]:
	_mutex.lock()
	var out: Array[Dictionary] = _entries.duplicate()
	_mutex.unlock()
	return out


# 当前缓冲条数
func get_entry_count() -> int:
	_mutex.lock()
	var c: int = _entries.size()
	_mutex.unlock()
	return c


# 清空缓冲并重置级别标记（作弊面板的「清空」按钮）
func clear_entries() -> void:
	_mutex.lock()
	_entries.clear()
	_highest_level = Level.INFO
	_mutex.unlock()


# 最高日志级别：作弊面板据此决定是否高亮报警
func get_highest_level() -> int:
	_mutex.lock()
	var lv: int = _highest_level
	_mutex.unlock()
	return lv


# 追加一条；满了就先移除最旧的，再更新最高级别
func _append(level: Level, text: String) -> void:
	_mutex.lock()
	if _entries.size() >= MAX_ENTRIES:
		_entries.remove_at(0)
	_entries.append({"time_ms": Time.get_ticks_msec(), "level": level, "text": text})
	if level > _highest_level:
		_highest_level = level
	_mutex.unlock()


# Logger 回调：普通输出按 error 标志记 INFO 或 ERROR
func _log_message(message: String, error: bool) -> void:
	var level: Level = Level.ERROR if error else Level.INFO
	_append(level, message.strip_edges())


# Logger 回调：错误 / 警告走这里；error_type 用来区分两者
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
	# 正文优先「代码 + 原因」，两者都空时留空
	var msg: String
	if not rationale.is_empty() and not code.is_empty():
		msg = "%s | %s" % [code, rationale]
	elif not rationale.is_empty():
		msg = rationale
	else:
		msg = code
	# 附上第一层调用栈，方便定位
	if not script_backtraces.is_empty():
		msg += " @ " + script_backtraces[0].format()
	_append(level, msg)
