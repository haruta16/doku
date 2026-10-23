## 本地实验覆盖存储：仅非 rel 构建可用，写盘成功后才更新内存，读取失败时保留原存档。
extends RefCounted

const _SAVE_DIR: String = "user://save_store/"
const _SAVE_PATH: String = "user://save_store/debug_ab_overrides.cfg"
const _PASSWORD: String = "MeowdokuDebugAbOverrides"

static var _loaded: bool = false

static var _load_failed: bool = false
static var _enabled: bool = false
static var _overrides: Dictionary = {}
static var _storage: SaveStore


static func capture_runtime_state() -> Dictionary:
	if OS.has_feature("rel"):
		return {}
	return {
		"loaded": _loaded,
		"load_failed": _load_failed,
		"enabled": _enabled,
		"overrides": _overrides.duplicate(true),
		"storage": _storage
	}


static func restore_runtime_state(snapshot: Dictionary) -> void:
	if OS.has_feature("rel") or snapshot.is_empty():
		return
	_loaded = snapshot["loaded"]
	_load_failed = snapshot["load_failed"]
	_enabled = snapshot["enabled"]
	_overrides = snapshot["overrides"].duplicate(true)
	_storage = snapshot["storage"]


static func is_enabled() -> bool:
	if OS.has_feature("rel"):
		return false
	_ensure_loaded()
	return _enabled


static func set_enabled(enabled: bool) -> bool:
	if OS.has_feature("rel"):
		return false
	_ensure_loaded(true)
	if _load_failed:
		push_error("[ABTest] 调试覆盖存档未读成功，无法保存开关")
		return false
	if enabled == _enabled:
		return true
	if not _save(enabled, _overrides):
		return false
	_enabled = enabled
	return true


static func get_override(key: String) -> Variant:
	if OS.has_feature("rel"):
		return null
	_ensure_loaded()
	return _overrides.get(key)


## 校验键和值类型，先保存副本再替换内存；覆盖开关关闭时直接返回，不落盘。
static func set_override(key: String, value: Variant) -> bool:
	if OS.has_feature("rel"):
		return false
	_ensure_loaded(true)
	if _load_failed:
		push_error("[ABTest] 调试覆盖存档未读成功，无法保存覆盖")
		return false
	if not _enabled:
		return true
	if key.is_empty() or typeof(value) not in [TYPE_INT, TYPE_STRING]:
		push_error("[ABTest] 无法保存调试覆盖：参数名为空或值类型无效")
		return false
	var updated: Dictionary = _overrides.duplicate()
	updated[key] = value
	if not _save(_enabled, updated):
		return false
	_overrides = updated
	return true


## 从副本删除指定键；保存失败时继续保留原内存状态。
static func clear_override(key: String) -> bool:
	if OS.has_feature("rel"):
		return false
	_ensure_loaded(true)
	if _load_failed:
		push_error("[ABTest] 调试覆盖存档未读成功，无法清除单项覆盖")
		return false
	if not _overrides.has(key):
		return true
	var updated: Dictionary = _overrides.duplicate()
	updated.erase(key)
	if not _save(_enabled, updated):
		return false
	_overrides = updated
	return true


static func reset_all() -> bool:
	if OS.has_feature("rel"):
		return false
	_ensure_loaded()
	if not _load_failed and not _enabled and _overrides.is_empty():
		return true
	if not _save(false, {}):
		return false
	_enabled = false
	_overrides.clear()
	_load_failed = false
	return true


## 延迟读取加密配置；读取失败会阻止后续写入，避免把损坏或暂不可读的存档覆盖掉。
static func _ensure_loaded(retry_failed: bool = false) -> void:
	if OS.has_feature("rel") or (_loaded and not (retry_failed and _load_failed)):
		return
	_loaded = true
	_load_failed = false
	_storage = SaveStore.new(_PASSWORD, _SAVE_DIR, false, _SAVE_PATH)
	if not FileAccess.file_exists(_SAVE_PATH):
		return
	var config: ConfigFile = _storage.load_config()
	if config == null:
		_load_failed = true
		push_error("[ABTest] 调试覆盖存档读取失败，本次使用正常 AB 取值")
		return
	var saved_enabled: Variant = config.get_value("debug_ab", "enabled", false)
	var saved_overrides: Variant = config.get_value("debug_ab", "overrides", {})
	if typeof(saved_enabled) != TYPE_BOOL or typeof(saved_overrides) != TYPE_DICTIONARY:
		_load_failed = true
		push_error("[ABTest] 调试覆盖存档格式无效，本次使用正常 AB 取值")
		return
	_enabled = saved_enabled
	_overrides.clear()
	var saved_keys: Array = saved_overrides.keys()
	for key: Variant in saved_keys:
		var value: Variant = saved_overrides[key]
		if typeof(key) != TYPE_STRING or typeof(value) not in [TYPE_INT, TYPE_STRING]:
			push_error("[ABTest] 忽略类型无效的本地调试覆盖：%s" % str(key))
			continue
		_overrides[key] = value


static func _save(enabled: bool, overrides: Dictionary) -> bool:
	if OS.has_feature("rel"):
		return false
	var config: ConfigFile = ConfigFile.new()
	config.set_value("debug_ab", "enabled", enabled)
	config.set_value("debug_ab", "overrides", overrides)
	if not _storage.save_config(config):
		push_error("[ABTest] 调试覆盖存档写入失败，保留原有设置")
		return false
	return true
