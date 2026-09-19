# 会话管理（autoload）：维护 sessionId 与前台活跃时长，长后台或局内跨天时重开会话，并驱动 GameState 的日切
extends Node

# 后台停留超过 30 分钟就判定为新会话（秒）
const SESSION_REFRESH_INTERVAL_SEC: int = 30 * 60

# 前台活跃秒数定时落盘的间隔（秒）
const ACTIVE_FLUSH_INTERVAL_SEC: int = 60

# 会话重建后发出，携带新的 session_id（Launcher 监听它打日志）
signal session_changed(new_session_id: String)

# ---- 运行时状态 ----
# 当前会话 ID（UUID v4 形式），_reset_session 时重新生成
var session_id: String = ""
# 本会话内的第几次会话记录：短暂切后台再回来会 +1，超时重开会话则归 1
var session_record: int = 1

# 最近一次切后台的 unix 时间戳（秒），0 表示还没进过后台
var _last_pause_unix: int = 0

# 当前这段前台计时的起点（Time.get_ticks_msec），-1 表示不在前台、不计时
var _active_seg_start_ms: int = -1
# 周期性把前台时长结算进 GameState 的 Timer（60 秒一跳）
var _active_flush_timer: Timer = null

# 本会话已结算的前台秒数（不含正在计时、还没落盘的那一段）
var _session_active_sec: int = 0


# 节点就绪：开一个新会话、通知 GameState，并启动活跃时长的定时落盘
func _ready() -> void:
	_reset_session()

	GameState.on_session_started()

	_active_seg_start_ms = Time.get_ticks_msec()
	_active_flush_timer = Timer.new()
	_active_flush_timer.wait_time = ACTIVE_FLUSH_INTERVAL_SEC
	_active_flush_timer.one_shot = false
	_active_flush_timer.timeout.connect(_flush_active_segment)
	add_child(_active_flush_timer)
	_active_flush_timer.start()


# 系统通知：切后台先结算这段前台时间并停止计时；回前台重新计时并决定是否重开会话
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_last_pause_unix = int(Time.get_unix_time_from_system())

			_flush_active_segment()
			_active_seg_start_ms = -1 # -1 = 停止前台计时
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_active_seg_start_ms = Time.get_ticks_msec()
			_on_resume()


# 把当前这段前台时间结算进 GameState（会写盘）并触发时长埋点；不足 1 秒直接忽略
func _flush_active_segment() -> void:
	if _active_seg_start_ms < 0:
		return
	var elapsed_sec: int = (Time.get_ticks_msec() - _active_seg_start_ms) / 1000 # 整数除法，不足 1 秒的部分丢弃
	if elapsed_sec <= 0:
		return
	GameState.add_today_active_sec(elapsed_sec)
	_session_active_sec += elapsed_sec
	_active_seg_start_ms += elapsed_sec * 1000 # 起点只推进已结算的整数秒，余数留到下次

	Tracker.try_track_grt_time_window(GameState.get_total_active_sec())


# 今日前台活跃秒数：已落盘部分 + 当前这段尚未落盘的时长
func get_today_active_sec() -> int:
	var base: int = GameState.get_today_active_sec()
	if _active_seg_start_ms < 0:
		return base
	return base + (Time.get_ticks_msec() - _active_seg_start_ms) / 1000


# 本会话前台活跃秒数：同样把正在计时的那一段也算进去
func get_session_active_sec() -> int:
	if _active_seg_start_ms < 0:
		return _session_active_sec
	return _session_active_sec + (Time.get_ticks_msec() - _active_seg_start_ms) / 1000


# 回前台：间隔超过 30 分钟算新会话（发信号 + 通知 GameState），否则只把 session_record +1
func _on_resume() -> void:
	if _last_pause_unix == 0:
		return
	var span_sec: int = int(Time.get_unix_time_from_system()) - _last_pause_unix
	if span_sec > SESSION_REFRESH_INTERVAL_SEC:
		_reset_session()
		session_changed.emit(session_id)

		GameState.on_session_started()
	else:
		session_record += 1 # 短暂切后台：算同一次会话的下一段


# 重开会话：换新 session_id、记录数归 1，并把时间与活跃基线重置
func _reset_session() -> void:
	session_id = _generate_session_id()
	session_record = 1
	_last_pause_unix = int(Time.get_unix_time_from_system())
	_session_active_sec = 0


# 调试用：立即重开会话（cheat 面板调用），流程与超时重开一致
func debug_advance_session() -> void:
	_reset_session()
	session_changed.emit(session_id)
	GameState.on_session_started()


# 生成 UUID v4 形式的 session_id：16 随机字节 + 版本位/变体位，再格式化成 8-4-4-4-12
func _generate_session_id() -> String:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 15) | 64
	bytes[8] = (bytes[8] & 63) | 128
	var hex: String = bytes.hex_encode()
	return (
		"%s-%s-%s-%s-%s"
		% [
			hex.substr(0, 8),
			hex.substr(8, 4),
			hex.substr(12, 4),
			hex.substr(16, 4),
			hex.substr(20, 12),
		]
	)
