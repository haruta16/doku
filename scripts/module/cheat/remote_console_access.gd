## 远程控制台访问入口：非发布构建按需加载桥接脚本，再转发启停与状态查询。
extends RefCounted

static var _bridge: GDScript = null


## 发布构建禁用；其他构建首次使用时加载并验证桥接脚本，成功后缓存。
static func _get_bridge() -> GDScript:
	if OS.has_feature("rel"):
		return null
	if _bridge == null:
		var bridge_script: GDScript = (
			load("res://scripts/module/cheat/remote/remote_console_bridge.gd") as GDScript
		)
		if bridge_script == null or not bridge_script.can_instantiate():
			push_error("远程控制台：无法加载桥接脚本")
			return null
		_bridge = bridge_script
	return _bridge


static func start() -> bool:
	var bridge: GDScript = _get_bridge()
	if bridge == null:
		return false
	return bool(bridge.call(&"start"))


static func stop() -> void:
	var bridge: GDScript = _get_bridge()
	if bridge != null:
		bridge.call(&"stop")


static func status_text() -> String:
	var bridge: GDScript = _get_bridge()
	if bridge == null:
		return "远程控制台：不可用"
	return str(bridge.call(&"status_text"))
