extends Node

const SESSION_REFRESH_INTERVAL_SEC: int = 30 * 60

const ACTIVE_FLUSH_INTERVAL_SEC: int = 60

signal session_changed(new_session_id: String)

var session_id: String = ""
var session_record: int = 1

var _last_pause_unix: int = 0

var _active_seg_start_ms: int = -1
var _active_flush_timer: Timer = null

var _session_active_sec: int = 0


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


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_last_pause_unix = int(Time.get_unix_time_from_system())

			_flush_active_segment()
			_active_seg_start_ms = -1
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_active_seg_start_ms = Time.get_ticks_msec()
			_on_resume()


func _flush_active_segment() -> void:
	if _active_seg_start_ms < 0:
		return
	var elapsed_sec: int = (Time.get_ticks_msec() - _active_seg_start_ms) / 1000
	if elapsed_sec <= 0:
		return
	GameState.add_today_active_sec(elapsed_sec)
	_session_active_sec += elapsed_sec
	_active_seg_start_ms += elapsed_sec * 1000

	Tracker.try_track_grt_time_window(GameState.get_total_active_sec())


func get_today_active_sec() -> int:
	var base: int = GameState.get_today_active_sec()
	if _active_seg_start_ms < 0:
		return base
	return base + (Time.get_ticks_msec() - _active_seg_start_ms) / 1000


func get_session_active_sec() -> int:
	if _active_seg_start_ms < 0:
		return _session_active_sec
	return _session_active_sec + (Time.get_ticks_msec() - _active_seg_start_ms) / 1000


func _on_resume() -> void:
	if _last_pause_unix == 0:
		return
	var span_sec: int = int(Time.get_unix_time_from_system()) - _last_pause_unix
	if span_sec > SESSION_REFRESH_INTERVAL_SEC:
		_reset_session()
		session_changed.emit(session_id)

		GameState.on_session_started()
	else:
		session_record += 1


func _reset_session() -> void:
	session_id = _generate_session_id()
	session_record = 1
	_last_pause_unix = int(Time.get_unix_time_from_system())
	_session_active_sec = 0


func debug_advance_session() -> void:
	_reset_session()
	session_changed.emit(session_id)
	GameState.on_session_started()


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
