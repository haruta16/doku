## 统计桥接：把业务事件与公共属性序列化后交给原生分析 SDK。
class_name UniKitAnalyzeModule
extends UniKitModuleBase

signal af_conversion_success(data: Dictionary)

signal af_conversion_fail(error: String)


## 发送统计事件，未指定平台时默认投递到 learnings。
func send_event(
	event_name: String, params: Dictionary = {}, platforms: Array = [], value_to_sum: float = 0.0
) -> void:
	if _host._plugin == null:
		return
	var _platforms: Array = platforms if not platforms.is_empty() else ["learnings"]
	_host._plugin.sendEvent(
		event_name, JSON.stringify(params), JSON.stringify(_platforms), value_to_sum
	)


## 读取原生分析 SDK 分配的用户标识。
func get_learnings_id() -> String:
	if _host._plugin == null:
		return ""
	return _host._plugin.getLearningsId()


## 读取原生统计 UUID；插件缺失时返回空串。
func get_uuid() -> String:
	if _host._plugin == null:
		return ""
	return _host._plugin.getUUID()


## 设置原生统计系统的用户级属性。
func set_user_property(key: String, value: String) -> void:
	if _host._plugin == null:
		return
	_host._plugin.setUserProperty(key, value)


## 设置原生统计系统附加到事件上的公共属性。
func set_event_property(key: String, value: String) -> void:
	if _host._plugin == null:
		return
	_host._plugin.setEventProperty(key, value)
