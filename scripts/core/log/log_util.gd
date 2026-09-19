# 引擎日志出口：把 Godot 的报错转成 UniKit(Crashlytics) 异常上报，带 5 秒去重与调用栈整理
class_name LogUtil
extends Logger


# ================= 静态快捷方法（业务代码直接调用） =================
# 报错：同时进引擎错误系统（push_error）和 stderr（printerr）；注册到 OS 后会被下面的 _log_error 接住
static func error(msg: String) -> void:
	push_error(msg)
	printerr(msg)


# 警告：走 push_warning 并给 stderr 加 [WARN] 前缀；不上报 UniKit（_log_error 会滤掉非 error 类型）
static func warn(msg: String) -> void:
	push_warning(msg)
	printerr("[WARN] " + msg)


# ---- 去重与栈格式常量 ----
# 去重窗口（毫秒）：同一处错误 5000 毫秒（5 秒）内只上报一次，防止刷屏打爆 Crashlytics
const _DEDUP_WINDOW_MS: int = 5000

# 用来识别并跳过调用栈里属于本文件的那一帧
const _LOG_UTIL_FILE: String = "log_util.gd"

# 每条 backtrace 前的标题行，沿用 Godot 原生格式（最近调用在前）
const _BACKTRACE_HEADER: String = "GDScript backtrace (most recent call first):"

# ---- 去重状态（多线程安全） ----
# 保护 _recent 的互斥锁：日志回调可能来自非主线程
var _mutex := Mutex.new()

# 已上报记录表：key = hash(消息 + 首条 backtrace) → 上次上报时的毫秒时间戳
var _recent: Dictionary = {}


# ================= 引擎 Logger 回调 =================
# Godot 报错回调：过滤噪声 → 组装消息 → 去重 → 拼调用栈 → 转交 UniKitManager 上报
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
	# 拿不到调用栈（多是引擎内部错误）就放弃，这种上报没有定位价值
	if script_backtraces.is_empty():
		return

	# 只看 error 与 script 两类；warning、shader 等直接丢弃
	if error_type != Logger.ERROR_TYPE_ERROR and error_type != Logger.ERROR_TYPE_SCRIPT:
		return

	# 拼可读消息：优先「code | rationale」，只有一边就单独使用
	var msg: String
	if not rationale.is_empty() and not code.is_empty():
		msg = "%s | %s" % [code, rationale]
	elif not rationale.is_empty():
		msg = rationale
	else:
		msg = code

	# 已知引擎噪声：iOS 上的 invalid utf16 surrogate 会反复刷屏
	if "invalid utf16 surrogate" in msg:
		return

	# 另一条已知噪声（按钮事件相关），同样丢弃
	if "button == MouseButton::NONE" in msg:
		return

	# 以下要读改写 _recent，先加锁
	_mutex.lock()
	var now_ms: int = Time.get_ticks_msec()

	# key 把消息和首条栈一起哈希：消息相同但出错位置不同仍算两条
	var key: int = hash(msg + script_backtraces[0].format())
	var last: int = _recent.get(key, -_DEDUP_WINDOW_MS - 1)
	# 距上次同 key 上报还在窗口期内，静默丢弃
	if now_ms - last < _DEDUP_WINDOW_MS:
		_mutex.unlock()
		return
	_recent[key] = now_ms

	# 安全阀：记录表超过 200 条整体清空，避免长跑进程内存膨胀
	if _recent.size() > 200:
		_recent.clear()
	_mutex.unlock()

	# 逐条 backtrace 拼成多行文本，行号用重排后的连续序号
	var stack_lines: PackedStringArray = []
	for bt in script_backtraces:
	# 每条栈前面都补一行标题
		stack_lines.append(_BACKTRACE_HEADER)
		var idx: int = 0
		for i in range(bt.get_frame_count()):
			var frame_file: String = bt.get_frame_file(i)

	# 跳过栈顶属于本文件的那一帧，让第 0 帧就是真正的出错位置
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

	# UniKitManager 尚未就绪（autoload 没加载或已释放）就不上报
	if not is_instance_valid(UniKitManager):
		return

	# 交给 UniKitManager：Crashlytics 未初始化时会先存进它的缓存队列
	UniKitManager.log_exception(msg, stack)
