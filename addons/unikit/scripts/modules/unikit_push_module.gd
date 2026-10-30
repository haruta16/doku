## 通知桥接：统一平台权限流程、通知内容校验与本地提醒排程。
class_name UniKitPushModule
extends UniKitModuleBase

const PUSH_PERMISSION_TYPE_SYSTEM: int = 1
const PUSH_PERMISSION_TYPE_SYSTEM_AND_SETTING: int = 2
const PUSH_PERMISSION_TYPE_SETTING: int = 3

const PUSH_AUTH_STATUS_NOT_DETERMINED: int = 0
const PUSH_AUTH_STATUS_DENIED: int = 1
const PUSH_AUTH_STATUS_AUTHORIZED: int = 2
const PUSH_AUTH_STATUS_PROVISIONAL: int = 3

const _CONTENT_FIELDS: Dictionary = {
	"title": {"ios": true, "type": TYPE_STRING},
	"content": {"ios": true, "type": TYPE_STRING},
	"large_icon": {"ios": true, "type": TYPE_STRING},
	"content_image": {"ios": true, "type": TYPE_STRING},
	"sound": {"ios": true, "type": TYPE_STRING},
	"bg_color": {"ios": false, "type": TYPE_STRING},
	"btn_bg_color": {"ios": false, "type": TYPE_STRING},
	"btn_content": {"ios": false, "type": TYPE_STRING},
	"bg_image": {"ios": false, "type": TYPE_STRING},
	"vibrate": {"ios": false, "type": TYPE_BOOL},
	"icon_align_right": {"ios": false, "type": TYPE_BOOL},
	"title_night": {"ios": false, "type": TYPE_STRING},
	"content_night": {"ios": false, "type": TYPE_STRING},
	"large_icon_night": {"ios": false, "type": TYPE_STRING},
}

signal push_permission_done
signal push_cmd_received(cmd_json: String)

signal push_authorization_status(status: int)

var _push_permission_pending: bool = false


## 以应用启动场景申请系统通知权限。
func request_push_permission() -> void:
	request_notification_permission(PUSH_PERMISSION_TYPE_SYSTEM, "app_start")


## 检查平台能力后发起权限流程，无法申请时也延迟发完成信号。
func request_notification_permission(
	type: int = PUSH_PERMISSION_TYPE_SYSTEM_AND_SETTING, position: String = "default"
) -> void:
	if _host._plugin == null:
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
	_host._plugin.requestPushPermission(type, position)


## 从系统版本判断是否支持 Android 13 起的通知运行时权限。
static func _is_android_13_or_above() -> bool:
	if not OS.has_feature("android"):
		return false
	var v: String = OS.get_version()
	if v.is_empty():
		return false
	return v.split(".")[0].to_int() >= 13


## 根据当前授权状态决定能否弹系统申请或引导设置页。
static func _can_request_for_status(status: int, type: int) -> bool:
	match status:
		PUSH_AUTH_STATUS_NOT_DETERMINED:
			return type != PUSH_PERMISSION_TYPE_SETTING
		PUSH_AUTH_STATUS_DENIED:
			return type != PUSH_PERMISSION_TYPE_SYSTEM
		PUSH_AUTH_STATUS_AUTHORIZED:
			return false
		PUSH_AUTH_STATUS_PROVISIONAL:
			return type != PUSH_PERMISSION_TYPE_SETTING
	return false


## 请求原生授权状态并等待回执；桥接信号缺失时返回 -1。
func _await_authorization_status() -> int:
	if not _host._plugin.has_signal("push_authorization_status"):
		push_error(
			"[UniKit] plugin 未声明信号 'push_authorization_status'——原生 bridge 版本过旧,权限查询将返回保守值,请重新同步 addon"
		)
		return -1
	_host._plugin.getPushAuthorizationStatus()

	return await push_authorization_status


## 按 Android 版本或 iOS 授权状态判断当前申请入口是否可用。
func can_request_permission(type: int = PUSH_PERMISSION_TYPE_SYSTEM_AND_SETTING) -> bool:
	if _host._plugin == null:
		return false
	if OS.has_feature("android"):
		if type == PUSH_PERMISSION_TYPE_SETTING:
			return _host._plugin.isGotoSettingEnabled()

		if type == PUSH_PERMISSION_TYPE_SYSTEM and not _is_android_13_or_above():
			return false
		return not _host._plugin.isNotificationPermissionEnabled()
	var status: int = await _await_authorization_status()
	if status < 0:
		return false
	return _can_request_for_status(status, type)


## 把本地小时数转换为下一次提醒日期，并建立 24 小时重复通知。
func add_daily_push(
	push_id: String, hour_local: float, contents: Array[Dictionary], disturb_type: int = 1
) -> void:
	if _host._plugin == null:
		return
	var target_hour: int = int(hour_local)
	var target_minute: int = int(round((hour_local - float(target_hour)) * 60.0))

	var local: Dictionary = Time.get_datetime_dict_from_system()

	var advance_one_day: bool = (
		local["hour"] > target_hour
		or (local["hour"] == target_hour and local["minute"] >= target_minute)
	)
	if advance_one_day:
		local = Time.get_datetime_dict_from_unix_time(
			Time.get_unix_time_from_datetime_dict(local) + 86400
		)
	var content_map: Dictionary = {}
	for i: int in range(contents.size()):
		content_map["%s_c%d" % [push_id, i]] = contents[i]
	var data := UniKitNotificationData.new(push_id, 0, true, 86400000, content_map)
	data.set_alarm_local_time(
		local["year"], local["month"], local["day"], target_hour, target_minute
	)
	add_local_push(data.set_disturb_type(disturb_type))


## 筛选平台支持的通知字段并校验时间，再序列化交给原生保存。
func add_local_push(data: UniKitNotificationData) -> void:
	if _host._plugin == null:
		return
	var cids: Array[String] = []
	var raw: Array[Dictionary] = []
	for cid: Variant in data.content_map:
		if data.content_map[cid] is Dictionary:
			cids.append(str(cid))
			raw.append(data.content_map[cid])
		else:
			push_warning('[UniKit] push content "%s" 不是 Dictionary,已剔除' % [cid])
	var kept: Array[int] = []
	var normalized: Array[Dictionary] = _normalize_contents(raw, OS.has_feature("ios"), kept)
	var contents_dict: Dictionary = {}
	for i: int in range(normalized.size()):
		contents_dict[cids[kept[i]]] = normalized[i]
	var err: String = ""
	if data.id.is_empty():
		err = "id 为空"
	elif data.local_time.is_empty() and data.alarm_time <= 0:
		err = "未设置触发时间(alarm_time 或 set_alarm_local_time)"
	elif data.is_repeat and data.repeat_interval <= 0:
		err = "is_repeat=true 时 repeat_interval 必须 > 0"
	elif contents_dict.is_empty():
		err = "规范化后没有可下发的 content"
	if not err.is_empty():
		push_error('[UniKit] add_local_push("%s") 未下发:%s' % [data.id, err])
		return
	var push_data: Dictionary = {
		"push_id": data.id,
		"push_time_ms": data.alarm_time if data.local_time.is_empty() else 0,
		"repeat_interval_ms": data.repeat_interval if data.is_repeat else 0,
		"is_infinite_repeat": data.is_repeat,
		"disturb_type": data.disturb_type,
		"contents": contents_dict
	}
	for k: String in data.local_time:
		push_data["local_" + k] = data.local_time[k]
	_host._plugin.saveLocalPush(JSON.stringify(push_data))


## 取消原生层保存的指定通知。
func remove_push(push_id: String) -> void:
	if _host._plugin == null:
		return
	_host._plugin.removeLocalPush(push_id)


## 清除原生层保存的全部本地通知。
func remove_all_pushes() -> void:
	if _host._plugin == null:
		return
	_host._plugin.removeAllLocalPush()


## 设置 SDK 的通知总开关，独立于系统授权状态。
func set_push_enabled(enabled: bool) -> void:
	if _host._plugin == null:
		return
	_host._plugin.enablePush(enabled)


## 查询 SDK 的通知总开关。
func is_push_enabled() -> bool:
	if _host._plugin == null:
		return false
	return _host._plugin.isEnablePush()


## 读取系统通知许可，iOS 临时授权也视为可通知。
func is_notification_permission_enabled() -> bool:
	if _host._plugin == null:
		return false
	if OS.has_feature("android"):
		return _host._plugin.isNotificationPermissionEnabled()
	var status: int = await _await_authorization_status()
	return status == PUSH_AUTH_STATUS_AUTHORIZED or status == PUSH_AUTH_STATUS_PROVISIONAL


## 查询原生层是否允许引导用户前往通知设置。
func is_goto_setting_enabled() -> bool:
	if _host._plugin == null:
		return false
	return _host._plugin.isGotoSettingEnabled()


## 先移除同名通知，再建立 5 秒后触发的单次测试提醒。
func trigger_test_push(
	push_id: String, title: String, content: String, extra: Dictionary = {}
) -> void:
	if _host._plugin == null:
		return
	_host._plugin.removeLocalPush(push_id)
	var now_ms: int = int(Time.get_unix_time_from_system() * 1000)

	var content_dict: Dictionary = extra.duplicate()
	content_dict["title"] = title
	content_dict["content"] = content
	add_local_push(
		UniKitNotificationData.new(push_id, now_ms + 5000, false, 0, {"c0": content_dict})
	)


## 注册原生命令回调，使通知携带的命令进入模块信号。
func register_cmd_callback() -> void:
	if _host._plugin == null:
		return
	_host._plugin.registerCmdCallback()


## 清理待完成标志并通知权限流程结束，不等同于已授权。
func _resolve_permission() -> void:
	_push_permission_pending = false
	push_permission_done.emit()


## 从系统设置回到前台时结束仍在等待的权限流程。
func _on_focus_in() -> void:
	if not _push_permission_pending:
		return
	_push_permission_pending = false
	push_permission_done.emit()


## 按字段白名单、平台和类型过滤通知内容，并记录保留项原下标。
func _normalize_contents(
	contents: Array[Dictionary], is_ios: bool, kept_indices: Array[int] = []
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rejected: Dictionary = {}
	var platform_dropped: Dictionary = {}
	for idx: int in range(contents.size()):
		var raw: Dictionary = contents[idx]
		var item: Dictionary = {}
		for k: Variant in raw:
			var key: String = str(k)
			if not _CONTENT_FIELDS.has(key):
				rejected[key] = "未知字段"
				continue
			var field: Dictionary = _CONTENT_FIELDS[key]
			if is_ios and not field["ios"]:
				platform_dropped[key] = true
				continue
			if typeof(raw[k]) != field["type"]:
				rejected[key] = (
					"类型应为 %s,实际 %s" % [type_string(field["type"]), type_string(typeof(raw[k]))]
				)
				continue

			if field["type"] == TYPE_STRING and String(raw[k]).is_empty():
				continue
			item[key] = raw[k]

		if item.is_empty():
			continue
		out.append(item)
		kept_indices.append(idx)
	if not rejected.is_empty():
		push_warning("[UniKit] push content 字段被剔除:%s" % [rejected])
	if not platform_dropped.is_empty() and OS.is_debug_build():
		print("[UniKit] push content 字段 %s 仅 Android 支持,iOS 已剔除" % [platform_dropped.keys()])
	return out
