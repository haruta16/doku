## 可同步存档模块的注册表；每个模块必须提供标识、导出数据和合并数据三个接口。
## 同步已发生后才注册的模块还会通知 late handler，补上启动顺序造成的缺口。

class_name DataSyncRegistry
extends RefCounted

static var _savables: Array = []

static var _synced_once: bool = false

static var _late_handler: Callable = Callable()


## 验证可同步对象的三个协议方法并注册；若已完成过同步，立即通知 late handler 补处理该模块。
static func register(savable: Object) -> void:
	assert(savable.has_method("cloud_save_id"), "DataSyncRegistry: 缺 cloud_save_id()")
	assert(savable.has_method("export_cloud_data"), "DataSyncRegistry: 缺 export_cloud_data()")
	assert(savable.has_method("merge_cloud_data"), "DataSyncRegistry: 缺 merge_cloud_data()")
	if savable in _savables:
		return
	_savables.append(savable)
	if _synced_once and _late_handler.is_valid():
		_late_handler.call(savable)


static func all() -> Array:
	return _savables


static func set_late_handler(cb: Callable) -> void:
	_late_handler = cb


## 标记启动后已成功同步，改变后续模块注册时的处理路径。
static func mark_synced() -> void:
	_synced_once = true


static func clear() -> void:
	_savables.clear()
	_synced_once = false
	_late_handler = Callable()
