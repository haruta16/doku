## 通关中位用时配置：按棋盘尺寸与层级查秒数，缺失时逐级回退到尺寸或全局默认值。
class_name LevelPassTimeMedian
extends RefCounted

const CONFIG_PATH: String = "res://assets/cfg/level_pass_time_median.json"
const FALLBACK_SEC: int = 117

static var _config: Dictionary = {}
static var _loaded: bool = false


## 优先查具体层级，再查尺寸默认值，最后使用全局默认或 117 秒兜底。
static func median_sec(size: int, rank: int) -> int:
	_ensure_loaded()
	var size_entry: Dictionary = _size_entry(size)
	var ranks: Variant = size_entry.get("ranks", {})
	if ranks is Dictionary and (ranks as Dictionary).has(str(rank)):
		return int((ranks as Dictionary)[str(rank)])
	if size_entry.has("default_sec"):
		return int(size_entry["default_sec"])
	return int(_config.get("default_sec", FALLBACK_SEC))


## 清缓存并重新读取用时配置，供调试或配置更新使用。
static func reload() -> void:
	_loaded = false
	_config = {}
	_ensure_loaded()


## 深拷贝注入配置并标为已加载，后续查询不再读文件。
static func override_config(config: Dictionary) -> void:
	_config = config.duplicate(true)
	_loaded = true


## 从配置中读取指定尺寸字典，缺失或类型错误时返回空字典。
static func _size_entry(size: int) -> Dictionary:
	var sizes: Variant = _config.get("sizes", {})
	if not sizes is Dictionary:
		return {}
	var entry: Variant = (sizes as Dictionary).get(str(size), {})
	return entry if entry is Dictionary else {}


## 只尝试读取一次 JSON 配置，文件或格式错误会报告并保留默认回退。
static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(CONFIG_PATH):
		push_error("LevelPassTimeMedian: config missing %s" % CONFIG_PATH)
		return
	var file: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("LevelPassTimeMedian: open failed %s" % CONFIG_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_error("LevelPassTimeMedian: invalid json %s" % CONFIG_PATH)
		return
	_config = parsed
