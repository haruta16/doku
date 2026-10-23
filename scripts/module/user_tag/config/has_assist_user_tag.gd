## 辅助使用标签：缓存远端用户标签，在原生标签模块初始化后异步刷新。
class_name HasAssistUserTag
extends RefCounted

const REMOTE_TAG_KEY: String = "has_assist"

static var _cached: int = -1
static var _fetch_in_flight: bool = false


static func cached_value() -> int:
	return _cached


static func refresh_async() -> void:
	if _fetch_in_flight or _cached != -1:
		return
	if GameState.is_has_assist_confirmed():
		_cached = 1
		return
	if not UniKitManager.is_usertag_inited():
		_ensure_usertag_init_binding()
		return
	_fetch_in_flight = true
	_do_refresh()


static func _ensure_usertag_init_binding() -> void:
	var callback: Callable = _on_usertag_init_completed
	if not UniKitManager.usertag_init_completed.is_connected(callback):
		UniKitManager.usertag_init_completed.connect(callback, CONNECT_ONE_SHOT)


static func _on_usertag_init_completed() -> void:
	refresh_async()


static func _do_refresh() -> void:
	var tags: Dictionary = await UniKitManager.get_remote_tags()
	_fetch_in_flight = false
	var raw: Variant = tags.get(REMOTE_TAG_KEY, null)
	_cached = 1 if (raw != null and int(raw) == 1) else 0
	if _cached == 1:
		GameState.mark_has_assist_confirmed()
	print("[has_assist] remote tag resolved: raw=%s cached=%d" % [str(raw), _cached])
