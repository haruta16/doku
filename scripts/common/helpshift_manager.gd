extends Node

signal unread_count_changed(count: int)

const ANDROID_APP_ID: String = "arsenal-support_platform_20260610074440920-419e5d01b34cf98"
const IOS_PLATFORM_ID: String = "arsenal-support_platform_20260610074440901-cc1ce66e7ed9026"
const IOS_API_KEY: String = "f6e712714ec70365ca39e75ec59799f2"
const DOMAIN: String = "arsenal-support.helpshift.com"

const ACTIVE_WINDOW_SEC: int = 2 * 86400

const DOT_HELPSHIFT_UNREAD: String = "helpshift_unread"

var _is_active: bool = false
var _unread_count: int = 0


func _plugin() -> Object:
	if Engine.has_singleton("HelpshiftPlugin"):
		return Engine.get_singleton("HelpshiftPlugin")
	return null


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		request_unread()


func preheat() -> void:
	if _is_active:
		return
	var last: int = GameState.get_help_last_open_time()
	if last <= 0 or (_now() - last) > ACTIVE_WINDOW_SEC:
		return
	_install()
	if _is_active:
		request_unread()


func open_faq() -> void:
	if not _is_active:
		_install()
	var p: Object = _plugin()
	if p == null:
		return
	GameState.set_help_last_open_time(_now())
	p.showFAQs("ALWAYS", _build_metadata(), _build_cifs())

	request_unread()


func request_unread() -> void:
	if not _is_active:
		return
	var p: Object = _plugin()
	if p == null:
		return
	p.requestUnreadMessageCount(true)


func get_unread_count() -> int:
	return _unread_count


func _install() -> void:
	var p: Object = _plugin()
	if p == null:
		return
	if OS.has_feature("ios"):
		pass
	else:
		p.install(ANDROID_APP_ID, DOMAIN, false, false)
	if not p.is_connected("unread_message_count", _on_native_unread):
		p.connect("unread_message_count", _on_native_unread)
	if not p.is_connected("auth_failure", _on_native_auth_failure):
		p.connect("auth_failure", _on_native_auth_failure)
	_is_active = true


func _on_native_unread(count: int) -> void:
	_unread_count = count
	unread_count_changed.emit(count)

	RedDotCenter.set_count(DOT_HELPSHIFT_UNREAD, count)


func _on_native_auth_failure(reason: String) -> void:
	push_warning("[Helpshift] auth failure: %s" % reason)


func _build_metadata() -> Dictionary:
	var inner: Dictionary = UniKitManager.get_inner_tags()
	return {
		"uuid": UniKitManager.get_uuid(),
		"luid": UniKitManager.get_luid(),
		"hit_the_experimental_group": UniKitManager.get_ab_dyeing_tag(),
		"country": UniKitManager.get_ab_country(),
		"number_of_levels": GameState.get_current_level(),
		"living_day": GameState.get_active_days(),
		"locate_count": GameState.get_tool_count("locate"),
		"hint_count": GameState.get_tool_count("hint"),
		"install_version": GameState.get_install_version(),
		"source_of_channels": inner.get("media_source", ""),
		"flow_domain": inner.get("pm_flow_domain", ""),
	}


func _build_cifs() -> Dictionary:
	var inner: Dictionary = UniKitManager.get_inner_tags()
	return {
		"uuid": {"type": "singleline", "value": UniKitManager.get_uuid()},
		"living_day": {"type": "singleline", "value": str(GameState.get_active_days())},
		"number_of_levels": {"type": "singleline", "value": str(GameState.get_current_level())},
		"hit_the_experimental_group":
		{"type": "multiline", "value": UniKitManager.get_ab_dyeing_tag()},
		"source_of_channels": {"type": "singleline", "value": str(inner.get("media_source", ""))},
		"install_version": {"type": "singleline", "value": GameState.get_install_version()},
	}


func _now() -> int:
	return int(Time.get_unix_time_from_system())
