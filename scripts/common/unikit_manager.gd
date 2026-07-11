extends Node

signal push_permission_done
signal luid_ready(luid: String)
signal ad_closed(placement_id: String)
signal ad_rewarded(placement_id: String)

signal ad_shown(placement_id: String)
signal ad_error_occurred(placement_id: String, msg: String)
signal ad_impression_received(data: Dictionary)
signal push_cmd_received(cmd_json: String)

signal analyze_init_completed
signal ad_init_completed

signal abtest_ready(user_info: Dictionary)
signal abtest_params_updated(update_type: String, user_info: Dictionary)
signal abtest_remote_config_ready
signal abtest_locsrv_fetched(success: bool, error: String)

signal cmp_completed

signal att_status_changed(status: int)

signal att_dismissed

const ATT_STATUS_NOT_DETERMINED: int = 0
const ATT_STATUS_AUTHORIZED: int = 1
const ATT_STATUS_SYSTEM_DENIED: int = 2
const ATT_STATUS_APP_DENIED: int = 3

const PUSH_PERMISSION_TYPE_SYSTEM: int = 1
const PUSH_PERMISSION_TYPE_SYSTEM_AND_SETTING: int = 2
const PUSH_PERMISSION_TYPE_SETTING: int = 3

var _plugin: Object = null

static var debug_force_editor_test: bool = false

var _last_interstitial_close_unix: int = 0

var _pending_ad_positions: Dictionary = {}

var _debug_ad_enabled: bool = true

var cheat_show_interstitial: bool = not OS.has_feature("editor")
var cheat_show_reward: bool = not OS.has_feature("editor")
var cheat_show_banner: bool = not OS.has_feature("editor")

var _debug_reward_miss: bool = false

var _push_permission_pending: bool = false

const _CRASHLYTICS_LOG_CACHE_MAX: int = 20
var _crashlytics_log_cache: Array[Dictionary] = []
var _is_analyze_inited: bool = false
var _is_ad_inited: bool = false

const _REWARD_GRANT_TIMEOUT_SEC: float = 30.0

var _reward_active_show_id: String = ""

var _reward_active_position: String = ""

var _reward_received: bool = false

var _reward_shown: bool = false

var _pending_watchdogs: Dictionary = {}


func _ready() -> void:
	if Engine.has_singleton("UniKitPlugin"):
		_plugin = Engine.get_singleton("UniKitPlugin")

		_plugin.analyze_init_success.connect(_on_analyze_init_success)
		_plugin.ad_init_success.connect(_on_ad_init_success)
		_plugin.ad_init_error.connect(_on_ad_init_error)
		_plugin.grt_init_success.connect(_on_grt_init_success)
		_plugin.push_init_success.connect(_on_push_init_success)
		_plugin.usertag_init_success.connect(_on_usertag_init_success)
		_plugin.purchase_init_success.connect(_on_purchase_init_success)
		_plugin.purchase_init_fail.connect(_on_purchase_init_fail)
		_plugin.abtest_init.connect(_on_abtest_init)
		_plugin.abtest_updated.connect(_on_abtest_updated)
		_plugin.abtest_remote_config_ready.connect(_on_abtest_remote_config_ready)
		_plugin.abtest_locsrv_result.connect(_on_abtest_locsrv_result)
		_plugin.af_callback_success.connect(_on_af_callback_success)
		_plugin.af_callback_fail.connect(_on_af_callback_fail)
		_plugin.luid_ready.connect(_on_luid_ready)
		_plugin.ad_closed.connect(_on_ad_closed)
		_plugin.ad_rewarded.connect(_on_ad_rewarded)

		if _plugin.has_signal("ad_shown"):
			_plugin.ad_shown.connect(_on_ad_shown)
		_plugin.ad_error.connect(_on_ad_error)
		_plugin.ad_impression.connect(_on_ad_impression)
		_plugin.push_permission_result.connect(_on_push_permission_result)
		_plugin.push_cmd_received.connect(_on_push_cmd_received)

		_plugin.cmp_completed.connect(_on_cmp_completed)

		if OS.has_feature("ios"):
			_plugin.att_status_changed.connect(_on_att_status_changed)
			_plugin.att_dismissed.connect(_on_att_dismissed)
	else:
		print("UniKitPlugin not available; offline adapter active")

	GameState.ensure_first_open_time(get_first_open_time_ms())
	GameState.ensure_install_version(get_version_name())


func is_available() -> bool:
	return _plugin != null


func is_online() -> bool:
	if _plugin == null:
		return true
	return _plugin.isOnline()


func check_privacy_required() -> bool:
	if _plugin == null:
		return false
	return _plugin.checkPrivacyUiRequired()


func agree_privacy() -> void:
	if _plugin == null:
		return
	_plugin.agreePrivacyPolicy()


func is_privacy_agreed() -> bool:
	if _plugin == null:
		return false
	return _plugin.isPrivacyPolicyAgreed()


func check_cmp(on_done: Callable = Callable()) -> void:
	if on_done.is_valid():
		cmp_completed.connect(on_done, CONNECT_ONE_SHOT)
	if _plugin == null:
		cmp_completed.emit.call_deferred()
		return
	_plugin.checkCMP()


func check_cmp_required() -> bool:
	if _plugin == null:
		return false
	return _plugin.checkCMPUiRequired()


func show_cmp_ui() -> void:
	if _plugin == null:
		return
	_plugin.showCMPUi()


func can_show_att() -> bool:
	if OS.has_feature("editor") and debug_force_editor_test:
		return true
	if not OS.has_feature("ios"):
		return false
	if _plugin == null:
		return false
	return _plugin.canShowATT()


func init_att() -> void:
	if _plugin == null:
		return
	if not OS.has_feature("ios"):
		return
	_plugin.initATT()


func show_att_alert(source: String) -> void:
	if OS.has_feature("editor") and debug_force_editor_test:
		print("[UniKit] (editor mock) showATTAlert source=%s,2 秒后模拟用户授权 + dismissed" % source)
		var timer: SceneTreeTimer = Engine.get_main_loop().create_timer(2.0)
		timer.timeout.connect(
			func() -> void:
				att_status_changed.emit(ATT_STATUS_AUTHORIZED)
				att_dismissed.emit()
		)
		return
	if _plugin == null:
		return
	if not OS.has_feature("ios"):
		return
	_plugin.showATTAlert(source)


func get_att_status() -> int:
	if _plugin == null:
		return ATT_STATUS_NOT_DETERMINED
	if not OS.has_feature("ios"):
		return ATT_STATUS_NOT_DETERMINED
	return _plugin.getATTStatus()


func debug_mock_ad_load_fail() -> void:
	if _plugin == null:
		return
	if not OS.has_feature("ios"):
		return
	_plugin.debugMockAdLoadFail()


func set_account_id(account_id: String) -> void:
	if _plugin == null:
		return
	_plugin.setAccountId(account_id)


func get_localized_privacy_url(url: String) -> String:
	if _plugin == null:
		return url
	return _plugin.getLocalizedPrivacyUrl(url)


func request_push_permission() -> void:
	request_notification_permission(PUSH_PERMISSION_TYPE_SYSTEM, "app_start")


func request_notification_permission(
	type: int = PUSH_PERMISSION_TYPE_SYSTEM_AND_SETTING, position: String = "default"
) -> void:
	if _plugin == null:
		push_permission_done.emit.call_deferred()
		return
	if (
		type == PUSH_PERMISSION_TYPE_SYSTEM
		and OS.has_feature("android")
		and not _is_android_13_or_above()
	):
		push_permission_done.emit.call_deferred()
		return
	_push_permission_pending = true
	_plugin.requestPushPermission(type, position)


static func _is_android_13_or_above() -> bool:
	if not OS.has_feature("android"):
		return false
	var v: String = OS.get_version()
	if v.is_empty():
		return false
	return v.split(".")[0].to_int() >= 13


func add_daily_push(
	push_id: String, hour_local: float, contents: Array[Dictionary], disturb_type: int = 1
) -> void:
	if _plugin == null:
		return
	var target_hour: int = int(hour_local)
	var target_minute: int = int(round((hour_local - float(target_hour)) * 60.0))

	var local: Dictionary = Time.get_datetime_dict_from_system()

	var advance_one_day: bool = (
		local["hour"] > target_hour
		or (local["hour"] == target_hour and local["minute"] >= target_minute)
	)
	var contents_dict: Dictionary = {}
	for i: int in range(contents.size()):
		contents_dict["%s_c%d" % [push_id, i]] = contents[i]
	var push_data: Dictionary = {
		"push_id": push_id,
		"local_year": local["year"],
		"local_month": local["month"],
		"local_day": local["day"],
		"local_hour": target_hour,
		"local_minute": target_minute,
		"advance_one_day": advance_one_day,
		"push_time_ms": 0,
		"repeat_interval_ms": 86400000,
		"is_infinite_repeat": true,
		"disturb_type": disturb_type,
		"contents": contents_dict
	}
	print(
		(
			"[UniKit] add_daily_push: push_id=%s hour=%.1f contents_count=%d disturb=%d"
			% [push_id, hour_local, contents.size(), disturb_type]
		)
	)
	_plugin.saveLocalPush(JSON.stringify(push_data))


func remove_push(push_id: String) -> void:
	if _plugin == null:
		return
	print("[UniKit] remove_push: push_id=%s" % push_id)
	_plugin.removeLocalPush(push_id)


func remove_all_pushes() -> void:
	if _plugin == null:
		return
	print("[UniKit] remove_all_pushes")
	_plugin.removeAllLocalPush()


func set_push_enabled(enabled: bool) -> void:
	if _plugin == null:
		return
	_plugin.enablePush(enabled)


func is_push_enabled() -> bool:
	if _plugin == null:
		return false
	return _plugin.isEnablePush()


func is_notification_permission_enabled() -> bool:
	if _plugin == null:
		return false
	return _plugin.isNotificationPermissionEnabled()


func is_goto_setting_enabled() -> bool:
	if _plugin == null:
		return false
	return _plugin.isGotoSettingEnabled()


func trigger_test_push(push_id: String, title: String, content: String) -> void:
	if _plugin == null:
		return
	_plugin.removeLocalPush(push_id)
	var now_ms: int = int(Time.get_unix_time_from_system() * 1000)
	var push_data: Dictionary = {
		"push_id": push_id,
		"push_time_ms": now_ms + 5000,
		"repeat_interval_ms": 0,
		"is_infinite_repeat": false,
		"disturb_type": 0,
		"contents": {"c0": {"title": title, "content": content}}
	}
	_plugin.saveLocalPush(JSON.stringify(push_data))


func register_cmd_callback() -> void:
	if _plugin == null:
		return
	_plugin.registerCmdCallback()


func get_inner_tags() -> Dictionary:
	if _plugin == null:
		return {}
	return JSON.parse_string(_plugin.getInnerTagJson())


func get_local_tags() -> Dictionary:
	if _plugin == null:
		return {}
	return JSON.parse_string(_plugin.getLocalTagJson())


func get_remote_tags() -> Dictionary:
	if _plugin == null:
		return {}
	return JSON.parse_string(_plugin.getRemoteTagJson())


func add_local_tag(key: String, value: String) -> void:
	if _plugin == null:
		return
	_plugin.addLocalTag(key, value)


func add_local_list_tag(key: String, values: Array) -> void:
	if _plugin == null:
		return
	_plugin.addLocalListTag(key, JSON.stringify(values))


func remove_local_tag(key: String) -> void:
	if _plugin == null:
		return
	_plugin.removeLocalTag(key)


func get_luid() -> String:
	if _plugin == null:
		return ""
	return _plugin.getLuid()


func add_luid_listener() -> void:
	if _plugin == null:
		return
	_plugin.addLuidListener()


func load_ad(placement_id: String) -> void:
	if _plugin == null:
		return
	_plugin.loadAd(placement_id)


func show_interstitial(placement_id: String, position: String) -> void:
	if _plugin == null:
		return
	if not _debug_ad_enabled:
		return
	if GameState.is_first_session():
		return
	var show_id: String = _plugin.createShowId()

	Tracker.track_ad_show_timing(show_id, placement_id, placement_id, position)
	Tracker.remember_ad_show_id(placement_id, show_id)
	_pending_ad_positions[placement_id] = position
	if _plugin.isAdReady(placement_id, position, show_id):
		_plugin.showAd(placement_id, position, show_id)


func try_show_interstitial(placement_id: String, position: String, show_id: String) -> bool:
	if not cheat_show_interstitial:
		return false
	if _is_ad_mock_enabled():
		_mock_show_ad(placement_id, position)
		return true
	if _plugin == null:
		return false
	_plugin.showAd(placement_id, position, show_id)

	return true


func get_interstitial_cd_sec() -> int:
	return ABTestManager.inter_cd_lc.get_cd_sec()


func is_interstitial_in_cd() -> bool:
	var cd_sec: int = get_interstitial_cd_sec()
	var now: int = int(Time.get_unix_time_from_system())
	return now - _last_interstitial_close_unix < cd_sec


func show_reward(placement_id: String, position: String, show_id: String) -> void:
	if not cheat_show_reward:
		_grant_reward_directly(placement_id)
		return
	if _is_ad_mock_enabled():
		_mock_show_ad(placement_id, position)
		return
	if _plugin == null:
		return

	if placement_id == "reward":
		_start_reward_session(show_id, position)
	_plugin.showAd(placement_id, position, show_id)


func gen_show_id() -> String:
	if _plugin == null:
		return ""
	return _plugin.createShowId()


func is_reward_ready(placement_id: String, position: String, show_id: String) -> bool:
	if _is_ad_mock_enabled():
		return true
	if _plugin == null:
		return false

	Tracker.track_ad_show_timing(show_id, placement_id, placement_id, position)
	Tracker.remember_ad_show_id(placement_id, show_id)
	_pending_ad_positions[placement_id] = position
	return _plugin.isAdReady(placement_id, position, show_id)


func is_interstitial_ready(placement_id: String, position: String, show_id: String) -> bool:
	if _is_ad_mock_enabled():
		return true
	if _plugin == null:
		return false
	Tracker.track_ad_show_timing(show_id, placement_id, placement_id, position)
	Tracker.remember_ad_show_id(placement_id, show_id)
	_pending_ad_positions[placement_id] = position
	return _plugin.isAdReady(placement_id, position, show_id)


func is_reward_valid(placement_id: String, position: String) -> bool:
	if _is_ad_mock_enabled():
		return true
	if _plugin == null:
		return false
	return _plugin.isAdValid(placement_id, position)


func is_banner_valid(placement_id: String, position: String) -> bool:
	if _is_ad_mock_enabled():
		return true
	if _plugin == null:
		return false
	return _plugin.isAdValid(placement_id, position)


func is_interstitial_valid(placement_id: String, position: String) -> bool:
	if _is_ad_mock_enabled():
		return true
	if _plugin == null:
		return false
	return _plugin.isAdValid(placement_id, position)


func _is_ad_mock_enabled() -> bool:
	return OS.has_feature("editor")


func _mock_show_ad(placement_id: String, position: String) -> void:
	var show_id: String = "mock_%d" % Time.get_ticks_usec()
	Tracker.track_ad_show_timing(show_id, placement_id, placement_id, position)
	Tracker.remember_ad_show_id(placement_id, show_id)
	_pending_ad_positions[placement_id] = position
	if placement_id == "reward":
		_start_reward_session(show_id, position)

	_on_ad_shown(placement_id)
	_on_ad_impression(JSON.stringify({"placement_id": placement_id, "position": position}))

	var on_close := func() -> void:
		_on_ad_closed(placement_id)
		UIManager.hide_ui(UiName.MOCK_AD)
	var on_reward_close := func() -> void:
		_on_ad_rewarded(placement_id)
		_on_ad_closed(placement_id)
		UIManager.hide_ui(UiName.MOCK_AD)
	(
		UIManager
		. show_ui(
			UiName.MOCK_AD,
			{
				"placement_id": placement_id,
				"position": position,
				"on_close": on_close,
				"on_reward_close": on_reward_close,
			}
		)
	)


func _mock_show_banner(
	placement_id: String, position: String, anchor_bottom: bool, offset_base: int, height_base: int
) -> void:
	(
		UIManager
		. show_ui(
			UiName.MOCK_BANNER,
			{
				"placement_id": placement_id,
				"position": position,
				"anchor_bottom": anchor_bottom,
				"offset_base": offset_base,
				"height_base": height_base,
			}
		)
	)


func _mock_destroy_banner() -> void:
	UIManager.hide_ui(UiName.MOCK_BANNER)


func _grant_reward_directly(placement_id: String) -> void:
	_on_ad_rewarded(placement_id)
	_on_ad_closed(placement_id)


func set_debug_reward_miss(enabled: bool) -> void:
	_debug_reward_miss = enabled


func show_banner(
	placement_id: String,
	position: String,
	anchor_bottom: bool = true,
	offset_base: int = 0,
	height_base: int = 180
) -> void:
	if not cheat_show_banner:
		return
	if _is_ad_mock_enabled():
		_mock_show_banner(placement_id, position, anchor_bottom, offset_base, height_base)
		return
	if _plugin == null:
		return
	var device_w_px: float = float(DisplayServer.window_get_size().x)
	var scale: float = device_w_px / 1080.0
	var offset_px: int = int(round(offset_base * scale))
	var height_px: int = int(round(height_base * scale))
	_plugin.showBanner(placement_id, position, anchor_bottom, offset_px, height_px)


func destroy_ad(placement_id: String) -> void:
	if _is_ad_mock_enabled():
		if placement_id == "banner":
			_mock_destroy_banner()
		return
	if _plugin == null:
		return
	_plugin.destroyAd(placement_id)


func open_ad_debug_view() -> void:
	if _plugin == null:
		return
	_plugin.openAdDebugView()


func send_event(
	event_name: String, params: Dictionary = {}, platforms: Array = [], value_to_sum: float = 0.0
) -> void:
	if _plugin == null:
		return
	var _platforms: Array = platforms if not platforms.is_empty() else ["learnings"]
	_plugin.sendEvent(event_name, JSON.stringify(params), JSON.stringify(_platforms), value_to_sum)


func get_learnings_id() -> String:
	if _plugin == null:
		return ""
	return _plugin.getLearningsId()


func get_uuid() -> String:
	if _plugin == null:
		return ""
	return _plugin.getUUID()


func get_version_name() -> String:
	if _plugin == null:
		return ProjectSettings.get_setting("application/config/version", "") as String
	return _plugin.getVersionName() as String


func get_version_code() -> int:
	if _plugin == null:
		return 0
	return int(_plugin.getVersionCode())


func get_first_open_time_ms() -> int:
	if _plugin == null:
		return 0
	return int(_plugin.getFirstOpenTimeMs())


func set_user_property(key: String, value: String) -> void:
	if _plugin == null:
		return
	_plugin.setUserProperty(key, value)


func set_event_property(key: String, value: String) -> void:
	if _plugin == null:
		return
	_plugin.setEventProperty(key, value)


func set_crashlytics_user_id(user_id: String) -> void:
	if _plugin == null:
		return
	_plugin.setCrashlyticsUserId(user_id)


func log_exception(message: String, stack: String = "") -> void:
	if _plugin == null:
		return

	if stack.is_empty():
		stack = _format_gd_backtraces(Engine.capture_script_backtraces(), 1)
	if _is_analyze_inited:
		_plugin.logCrashlyticsException(message, stack)
		return

	if _crashlytics_log_cache.size() >= _CRASHLYTICS_LOG_CACHE_MAX:
		_crashlytics_log_cache.pop_front()
	_crashlytics_log_cache.append({"message": message, "stack": stack})


func _format_gd_backtraces(backtraces: Array, skip_frames: int) -> String:
	var lines: PackedStringArray = []
	for bt in backtraces:
		var count: int = bt.get_frame_count()
		for i in range(skip_frames, count):
			lines.append(
				(
					"[%d] %s (%s:%d)"
					% [
						lines.size(),
						bt.get_frame_function(i),
						bt.get_frame_file(i),
						bt.get_frame_line(i)
					]
				)
			)
	return "\n".join(lines)


func request_store_review() -> void:
	if _plugin == null:
		return
	_plugin.requestStoreReview()


func is_analyze_inited() -> bool:
	return _is_analyze_inited


func is_ad_inited() -> bool:
	return _is_ad_inited


func _on_analyze_init_success() -> void:
	_is_analyze_inited = true

	for entry in _crashlytics_log_cache:
		_plugin.logCrashlyticsException(entry["message"], entry["stack"])
	_crashlytics_log_cache.clear()
	analyze_init_completed.emit()


func _on_ad_init_success() -> void:
	if _plugin == null:
		push_warning("UniKit AD init_success but plugin is null")
		return
	_plugin.setAdImpressionListener()
	_is_ad_inited = true
	ad_init_completed.emit()

	load_ad("reward")
	await get_tree().create_timer(2.0).timeout
	load_ad("interstitial")
	await get_tree().create_timer(2.0).timeout
	load_ad("banner")


func _on_ad_init_error(error: String) -> void:
	push_warning("UniKit AD init error: %s" % error)


func _on_grt_init_success() -> void:
	pass


func _on_push_init_success() -> void:
	register_cmd_callback()


func _on_usertag_init_success() -> void:
	add_luid_listener()


func _on_purchase_init_success() -> void:
	pass


func _on_purchase_init_fail(error: String) -> void:
	push_warning("UniKit Purchase init fail: %s" % error)


func _on_abtest_init(params_json: String) -> void:
	var d: Variant = JSON.parse_string(params_json)
	abtest_ready.emit(d if d is Dictionary else {})


func _on_abtest_updated(update_type: String, user_info_json: String) -> void:
	var d: Variant = JSON.parse_string(user_info_json)
	abtest_params_updated.emit(update_type, d if d is Dictionary else {})


func _on_abtest_remote_config_ready() -> void:
	abtest_remote_config_ready.emit()


func _on_abtest_locsrv_result(success: bool, error: String) -> void:
	abtest_locsrv_fetched.emit(success, error)


func _on_af_callback_success(data_json: String) -> void:
	print("[UniKit] AF 归因回调成功: ", data_json)


func _on_af_callback_fail(msg: String) -> void:
	push_warning("UniKit AF callback fail: %s" % msg)


func _on_push_permission_result(_status: int) -> void:
	_push_permission_pending = false
	push_permission_done.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and _push_permission_pending:
		_resolve_push_permission_on_focus.call_deferred()


func _resolve_push_permission_on_focus() -> void:
	if not _push_permission_pending:
		return
	_push_permission_pending = false
	push_permission_done.emit()


func _on_push_cmd_received(cmd_json: String) -> void:
	push_cmd_received.emit(cmd_json)


func _on_cmp_completed() -> void:
	cmp_completed.emit()


func _on_att_status_changed(status: int) -> void:
	att_status_changed.emit(status)


func _on_att_dismissed() -> void:
	att_dismissed.emit()


func _on_luid_ready(luid: String) -> void:
	luid_ready.emit(luid)


func _on_ad_closed(placement_id: String) -> void:
	print("[UniKit] ad_closed: placement=%s reward_shown=%s" % [placement_id, _reward_shown])

	_last_interstitial_close_unix = int(Time.get_unix_time_from_system())
	ad_closed.emit(placement_id)

	if placement_id == "reward":
		if _reward_shown:
			GameState.increment_session_reward_view_count()
		_maybe_start_reward_grant_watchdog()


func _on_ad_rewarded(placement_id: String) -> void:
	if _debug_reward_miss and placement_id == "reward":
		print(
			"[UniKit] ad_rewarded SKIPPED by cheat _debug_reward_miss: placement=%s" % placement_id
		)
		return
	print("[UniKit] ad_rewarded: placement=%s" % placement_id)
	ad_rewarded.emit(placement_id)

	if placement_id == "reward":
		_mark_reward_received()

		GameState.record_normal_reward(int(Time.get_unix_time_from_system()))


func _on_ad_shown(placement_id: String) -> void:
	ad_shown.emit(placement_id)
	if placement_id == "reward" and _reward_active_show_id != "":
		_reward_shown = true


func _start_reward_session(show_id: String, position: String) -> void:
	_reward_active_show_id = show_id
	_reward_active_position = position
	_reward_received = false
	_reward_shown = false


func _mark_reward_received() -> void:
	if _reward_active_show_id != "":
		_reward_received = true
		return

	if _pending_watchdogs.is_empty():
		return
	var earliest_key: String = ""
	var earliest_ts: int = 0
	for key in _pending_watchdogs:
		var ts: int = int(_pending_watchdogs[key].get("ts", 0))
		if earliest_key == "" or ts < earliest_ts:
			earliest_key = key
			earliest_ts = ts
	_pending_watchdogs.erase(earliest_key)


func _maybe_start_reward_grant_watchdog() -> void:
	if _reward_active_show_id == "":
		return
	if _reward_received:
		_reset_reward_session()
		return
	if not _reward_shown:
		_reset_reward_session()
		return
	var show_id: String = _reward_active_show_id
	var position: String = _reward_active_position
	_pending_watchdogs[show_id] = {
		"position": position,
		"ts": int(Time.get_unix_time_from_system()),
	}
	get_tree().create_timer(_REWARD_GRANT_TIMEOUT_SEC).timeout.connect(
		func() -> void: _on_reward_grant_timeout(show_id, position), CONNECT_ONE_SHOT
	)

	_reset_reward_session()


func _on_reward_grant_timeout(show_id: String, position: String) -> void:
	if not _pending_watchdogs.has(show_id):
		return
	_pending_watchdogs.erase(show_id)

	if not ABTestManager.common_rewardad_logic.should_grant_reward_restore():
		return

	(
		GameState
		. add_pending_reward(
			{
				"show_id": show_id,
				"source": position,
				"ts": int(Time.get_unix_time_from_system()),
			}
		)
	)


func restore_items_for_position(position: String) -> Array:
	if position == Tracker.AdPos.PROPS_NORMAL_HINT or position == Tracker.AdPos.PROPS_DAILY_HINT:
		return [{"kind": "hint", "count": 1}]
	if (
		position == Tracker.AdPos.PROPS_NORMAL_LOCATE
		or position == Tracker.AdPos.PROPS_DAILY_LOCATE
	):
		return [{"kind": "locate", "count": 1}]

	if position == "props_normal_undo":
		return [{"kind": "undo", "count": 1}]

	if position == Tracker.AdPos.STREAK_X2_REWARD:
		var items: Array = []
		for kind: String in StreakData.REWARD_BASE:
			items.append({"kind": kind, "count": int(StreakData.REWARD_BASE[kind])})
		return items
	return []


func _reset_reward_session() -> void:
	_reward_active_show_id = ""
	_reward_active_position = ""
	_reward_received = false
	_reward_shown = false


func _on_ad_error(placement_id: String, msg: String) -> void:
	push_warning("UniKit AD error: placement=%s, msg=%s" % [placement_id, msg])
	ad_error_occurred.emit(placement_id, msg)


func _on_ad_impression(data_json: String) -> void:
	var data: Dictionary = JSON.parse_string(data_json)
	ad_impression_received.emit(data)

	var placement_id: String = data.get("placement_id", "")
	if placement_id == "":
		push_warning("UniKit AD impression: placement_id 为空, raw=%s" % data_json)
		return
	var ad_show_id: String = Tracker.consume_ad_show_id(placement_id)
	var position: String = _pending_ad_positions.get(placement_id, data.get("position", ""))
	_pending_ad_positions.erase(placement_id)
	if placement_id == "interstitial":
		Tracker.track_interstitial_ad_show(ad_show_id, GameState.get_current_level(), position)
	elif placement_id == "reward":
		Tracker.track_rewarded_ad_show(ad_show_id, GameState.get_current_level(), position)


func set_debug_ad_enabled(enabled: bool) -> void:
	if _debug_ad_enabled == enabled:
		return
	_debug_ad_enabled = enabled
	if not enabled:
		destroy_ad("banner")


func is_debug_ad_enabled() -> bool:
	return _debug_ad_enabled


func get_ab_string(key: String, default_value: String = "") -> String:
	if _plugin == null:
		return default_value
	return _plugin.getAbString(key, default_value)


func get_ab_int(key: String, default_value: int = 0) -> int:
	if _plugin == null:
		return default_value
	return _plugin.getAbInt(key, default_value)


func get_ab_float(key: String, default_value: float = 0.0) -> float:
	if _plugin == null:
		return default_value
	return _plugin.getAbFloat(key, default_value)


func dye_ab(key: String) -> void:
	if _plugin == null:
		return
	_plugin.dyeAbTest(key)


func get_all_ab_experiments() -> Dictionary:
	if _plugin == null:
		return {}
	var d: Variant = JSON.parse_string(_plugin.getAllAbExperimentsJson())
	return d if d is Dictionary else {}


func get_all_publish_ab_experiments() -> Dictionary:
	if _plugin == null:
		return {}
	var d: Variant = JSON.parse_string(_plugin.getAllPublishAbExperimentsJson())
	return d if d is Dictionary else {}


func get_ab_all_tag() -> String:
	if _plugin == null:
		return ""
	return _plugin.getAbAllTag()


func get_ab_dyeing_tag() -> String:
	if _plugin == null:
		return ""
	return _plugin.getAbDyeingTag()


func get_ab_group_id() -> String:
	if _plugin == null:
		return ""
	return _plugin.getAbGroupId()


func get_ab_user_info() -> Dictionary:
	if _plugin == null:
		return {}
	var d: Variant = JSON.parse_string(_plugin.getAbUserInfoJson())
	return d if d is Dictionary else {}


func fetch_remote_ab_result() -> void:
	if _plugin == null:
		return
	_plugin.fetchRemoteAbResult()


func get_ab_locsrv_param(key: String, default_value: String = "") -> String:
	if _plugin == null:
		return default_value
	var v: String = _plugin.getAbLocSrvParam(key)
	return v if v != "" else default_value


func get_all_ab_locsrv_params() -> Dictionary:
	if _plugin == null:
		return {}
	var d: Variant = JSON.parse_string(_plugin.getAllAbLocSrvParamsJson())
	return d if d is Dictionary else {}


func dye_ab_locsrv(key: String) -> void:
	if _plugin == null:
		return
	_plugin.dyeAbLocSrvTest(key)


func set_ab_locsrv_all_tag(tags: Array[String]) -> void:
	if _plugin == null:
		return
	_plugin.setAbLocSrvAllTag(JSON.stringify(tags))


func dye_ab_locsrv_tag(tag: String) -> void:
	if _plugin == null:
		return
	_plugin.dyeAbLocSrvTag(tag)


func get_ab_country() -> String:
	if _plugin == null:
		return ""
	return _plugin.getAbCountry()


func set_ab_group_id(group_id: String) -> void:
	if _plugin == null:
		return
	_plugin.setAbGroupId(group_id)


func set_ab_country(country: String) -> void:
	if _plugin == null:
		return
	_plugin.setAbCountry(country)
