## 辅助使用标签：缓存远端用户标签；请求和缓存属于当前存档代次。
class_name HasAssistUserTag
extends RefCounted

const REMOTE_TAG_KEY: String = "has_assist"

static var _cached: int = -1
static var _fetch_in_flight: bool = false
static var _storage_epoch: int = -1
static var _request_sequence: int = 0
static var _ready_callback: Callable = Callable()


static func _sync_storage_epoch() -> void:
	var current: int = GameState.get_storage_epoch()
	if current == _storage_epoch:
		return
	_storage_epoch = current
	_request_sequence += 1
	_cached = -1
	_fetch_in_flight = false
	if _ready_callback.is_valid() and UniKitManager.usertag_ready.is_connected(_ready_callback):
		UniKitManager.usertag_ready.disconnect(_ready_callback)
	_ready_callback = Callable()


static func cached_value() -> int:
	_sync_storage_epoch()
	return _cached


static func refresh_async() -> void:
	_sync_storage_epoch()
	if _storage_epoch < 0 or _fetch_in_flight or _cached != -1:
		return
	if GameState.is_has_assist_confirmed():
		_cached = 1
		return
	if not UniKitManager.is_usertag_inited():
		_ensure_usertag_init_binding()
		return
	_fetch_in_flight = true
	_request_sequence += 1
	_do_refresh(_storage_epoch, _request_sequence)


static func _ensure_usertag_init_binding() -> void:
	if _ready_callback.is_valid() and UniKitManager.usertag_ready.is_connected(_ready_callback):
		return
	_ready_callback = _on_usertag_init_completed.bind(_storage_epoch, _request_sequence)
	UniKitManager.usertag_ready.connect(_ready_callback, CONNECT_ONE_SHOT)


static func _on_usertag_init_completed(_data: Dictionary, expected_epoch: int, sequence: int) -> void:
	if expected_epoch != GameState.get_storage_epoch() or sequence != _request_sequence:
		return
	_ready_callback = Callable()
	refresh_async()


static func _do_refresh(expected_epoch: int, sequence: int) -> void:
	var tags: Dictionary = await UniKitManager.get_remote_tags()
	if expected_epoch != GameState.get_storage_epoch() or sequence != _request_sequence:
		return
	_fetch_in_flight = false
	var raw: Variant = tags.get(REMOTE_TAG_KEY, null)
	_cached = 1 if (raw != null and int(raw) == 1) else 0
	if _cached == 1:
		GameState.mark_has_assist_confirmed()
	print("[has_assist] remote tag resolved: raw=%s cached=%d" % [str(raw), _cached])
