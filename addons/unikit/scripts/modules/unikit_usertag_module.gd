## 用户标签缓存：保存原生标签快照，并分别通知全量订阅者与指定键的订阅者。
class_name UniKitUserTagModule
extends UniKitModuleBase

signal luid_ready(luid: String)

signal af_data_result(af_data: Dictionary)

signal deep_link_data_result(data: Dictionary)

signal usertag_ready(data: Dictionary)

signal usertag_data_updated(json: String)

var _usertag_cache: Dictionary = {}
var _is_usertag_data_ready: bool = false
var _last_flat_tags: Dictionary = {}

var _usertag_update_listeners: Array[Callable] = []

var _usertag_key_listeners: Dictionary = {}


## 读取缓存中的 SDK 内部标签，不触发新的原生查询。
func get_inner_tags() -> Dictionary:
	return _usertag_cache.get("inner_tag_data", {})


## 读取缓存中的本地单值标签。
func get_local_tags() -> Dictionary:
	return _usertag_cache.get("local_tag_data", {})


## 读取缓存中的远端单值标签。
func get_remote_tags() -> Dictionary:
	return _usertag_cache.get("remote_tag_data", {})


## 读取缓存中的本地列表标签。
func get_local_list_tags() -> Dictionary:
	return _usertag_cache.get("local_list_tag_data", {})


## 读取缓存中的远端列表标签。
func get_remote_list_tags() -> Dictionary:
	return _usertag_cache.get("remote_list_tag_data", {})


## 向原生标签系统写入一个本地单值标签。
func add_local_tag(key: String, value: String) -> void:
	if _host._plugin == null:
		return
	_host._plugin.addLocalTag(key, value)


## 把列表序列化为 JSON 后写入原生本地标签。
func add_local_list_tag(key: String, values: Array) -> void:
	if _host._plugin == null:
		return
	_host._plugin.addLocalListTag(key, JSON.stringify(values))


## 请求原生移除指定本地标签。
func remove_local_tag(key: String) -> void:
	if _host._plugin == null:
		return
	_host._plugin.removeLocalTag(key)


## 读取原生用户标识；尚无插件时返回空串。
func get_luid() -> String:
	if _host._plugin == null:
		return ""
	return _host._plugin.getLuid()


## 注册原生用户标识就绪监听，结果由宿主转发。
func set_luid_listener() -> void:
	if _host._plugin == null:
		return
	_host._plugin.setLuidListener()


## 注册归因数据监听，让原生归因结果进入脚本信号。
func set_af_data_listener() -> void:
	if _host._plugin == null:
		return
	_host._plugin.setAfDataListener()


## 注册深度链接数据监听，供业务响应外部入口。
func set_deep_link_listener() -> void:
	if _host._plugin == null:
		return
	_host._plugin.setDeepLinkListener()


## 登记全量标签订阅者；已有快照时立即补发一次当前数据。
func add_usertag_update_listener(callback: Callable) -> void:
	if callback not in _usertag_update_listeners:
		_usertag_update_listeners.append(callback)
		if _is_usertag_data_ready:
			callback.call(_usertag_cache)


## 取消全量标签订阅，避免失效回调继续收到更新。
func remove_usertag_update_listener(callback: Callable) -> void:
	_usertag_update_listeners.erase(callback)


## 登记指定标签订阅；已就绪且存在该键时立即补发当前快照。
func add_usertag_key_listener(tag_key: String, callback: Callable) -> void:
	if tag_key not in _usertag_key_listeners:
		_usertag_key_listeners[tag_key] = []
	var list: Array = _usertag_key_listeners[tag_key]
	if callback not in list:
		list.append(callback)
		if _is_usertag_data_ready and tag_key in _last_flat_tags:
			callback.call(_usertag_cache)


## 从指定键的订阅列表中移除回调。
func remove_usertag_key_listener(tag_key: String, callback: Callable) -> void:
	if tag_key in _usertag_key_listeners:
		_usertag_key_listeners[tag_key].erase(callback)


## 接收完整快照，首次触发就绪事件，并比较前后扁平标签通知变化。
func _on_usertag_data_updated(json: String) -> void:
	var parsed: Variant = JSON.parse_string(json)
	if not parsed is Dictionary:
		return
	_usertag_cache = parsed
	emit_signal("usertag_data_updated", json)
	var new_flat := _flatten_tags(parsed)
	if not _is_usertag_data_ready:
		_is_usertag_data_ready = true
		set_luid_listener()
		emit_signal("usertag_ready", _usertag_cache)
		_notify_update_listeners(parsed)
		_notify_key_listeners(new_flat)
	else:
		_notify_key_listeners(new_flat)
		_notify_update_listeners(parsed)
	_last_flat_tags = new_flat


## 将本次完整标签快照分发给全量订阅者。
func _notify_update_listeners(data: Dictionary) -> void:
	for cb in _usertag_update_listeners:
		cb.call(data)


## 仅在指定键的扁平值变化时通知对应订阅者，回调参数仍是完整缓存。
func _notify_key_listeners(new_flat: Dictionary) -> void:
	for tag_key in _usertag_key_listeners:
		var new_val: Variant = new_flat.get(tag_key)
		var old_val: Variant = _last_flat_tags.get(tag_key)
		if new_val != old_val:
			for cb in _usertag_key_listeners[tag_key]:
				cb.call(_usertag_cache)


## 按既定覆盖顺序展开内部、本地、远端标签，列表转 JSON 便于比较变化。
func _flatten_tags(data: Dictionary) -> Dictionary:
	var flat := {}
	var inner: Variant = data.get("inner_tag_data", {})
	if inner is Dictionary:
		var comp_keys := [
			"ad_value_data", "device_resolution_data", "device_category_data", "fold_status_data"
		]
		for comp_key in comp_keys:
			var comp: Variant = inner.get(comp_key)
			if comp is Dictionary:
				flat[comp_key] = comp.get("name", "")

		for k in inner:
			if not inner[k] is Dictionary:
				flat[k] = inner[k]

		var map_keys := [
			"mo_flow_domain_data",
			"pm_flow_domain_data",
			"ua_ad_tag_data",
			"af_push_api_ua_ad_tag_data",
			"af_push_api_data"
		]
		for map_key in map_keys:
			var map_val: Variant = inner.get(map_key, {})
			if map_val is Dictionary:
				flat.merge(map_val, true)

	var local: Variant = data.get("local_tag_data", {})
	if local is Dictionary:
		flat.merge(local, true)
	var local_list: Variant = data.get("local_list_tag_data", {})
	if local_list is Dictionary:
		for k in local_list:
			flat[k] = JSON.stringify(local_list[k])
	var remote: Variant = data.get("remote_tag_data", {})
	if remote is Dictionary:
		flat.merge(remote, true)
	var remote_list: Variant = data.get("remote_list_tag_data", {})
	if remote_list is Dictionary:
		for k in remote_list:
			flat[k] = JSON.stringify(remote_list[k])
	return flat
