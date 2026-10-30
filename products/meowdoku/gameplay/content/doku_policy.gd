# Doku 配表入口；默认表随客户端发布，远端只覆盖经过校验的已知字段。
class_name DokuPolicy
extends RefCounted

static var _cached_generation: int = -1
static var _policy: Dictionary = {}
static var _provenance: Dictionary = {"logical_id": "doku/policy", "release": "builtin", "fallback_error": ""}


## 发布校验与运行时使用同一合并规则；不依赖已激活内容或玩家状态。
static func merge_builtin(override: Dictionary = {}) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://products/meowdoku/assets/config/doku_policy.json"))
	var result: Dictionary = parsed if parsed is Dictionary else {}
	for key: String in override:
		if key == "size_cycles":
			result.size_cycles.merge(override.size_cycles, true)
		else:
			result[key] = override[key].duplicate(true) if override[key] is Dictionary or override[key] is Array else override[key]
	return result


static func snapshot() -> Dictionary:
	_refresh()
	return _policy.duplicate(true)


static func provenance() -> Dictionary:
	_refresh()
	return _provenance.duplicate(true)


static func draft_unlock_level() -> int:
	_refresh()
	return int(_policy.get("draft_unlock_level", 21))


static func special_levels() -> Dictionary:
	_refresh()
	var result: Dictionary = {}
	for key: Variant in _policy.get("special_levels", {}):
		result[int(str(key))] = _policy.special_levels[key].duplicate(true)
	return result


static func cycle_size(group: int, level: int) -> int:
	_refresh()
	if level < 1:
		return 0
	var segments: Array = _policy.get("size_cycles", {}).get(("base" if group == -1 else ("j" if group == -2 else str(group))), [])
	for index: int in range(segments.size() - 1, -1, -1):
		var segment: Dictionary = segments[index]
		if level >= int(segment.from):
			var values: Array = segment.sizes
			return int(values[(level - int(segment.from)) % values.size()])
	return 0


static func _refresh() -> void:
	var generation: int = ContentContext.generation()
	if generation == _cached_generation:
		return
	_provenance = {"logical_id": "doku/policy", "release": "builtin", "fallback_error": ""}
	var override: Dictionary = ContentContext.read_json("doku/policy")
	_policy = merge_builtin(override.value if override.get("ok", false) else {})
	if bool(override.get("ok", false)):
		_provenance.release = str(override.release)
	elif override.get("error", "") != "unknown_content":
		# 已声明策略损坏：留下明确错误并阻止新局，不能把它当成“本代没有覆盖”。
		_policy = {}
		_provenance = {"logical_id": "doku/policy", "release": ContentContext.data_release_id(), "fallback_error": str(override.get("error", "content_read"))}
	_cached_generation = generation
