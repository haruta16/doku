## 恢复工具共用的数据核查；调用发布包中的编解码器，不另造关卡格式。
extends RefCounted

const BINARY_FORMAT = preload("res://scripts/module/bank/model/bank_binary_format.gd")
const LEVEL_CODEC = preload("res://scripts/module/bank/model/bank_level_codec.gd")
const CORE = preload("res://scripts/module/gameplay/core/queendoku_core.gd")
const BANK_DATA = preload("res://scripts/module/bank/model/bank_data.gd")
const KEY := "meowdoku-2026-bank-secret"


static func read_runtime(path: String) -> Variant:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	for index in bytes.size():
		bytes[index] ^= KEY.unicode_at(index % KEY.length())
	if path.ends_with(".bin"):
		var decoded: Dictionary = BINARY_FORMAT.decode(bytes)
		if not decoded["ok"]:
			push_error("Cannot decode %s: %s" % [path, decoded["error"]])
			return null
		return decoded["data"]
	return JSON.parse_string(bytes.get_string_from_utf8())


## PackedByteArray 的 regionMap 必须展开成二维数组后才能写成可编辑 JSON。
static func materialize(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = LEVEL_CODEC.materialize_entry(value, false)
		for key in result:
			result[key] = materialize(result[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(materialize(item))
		return result
	return value


static func statistics(data: Variant) -> Dictionary:
	var solution_counts := _solution_counts(data)
	return {
		"records": _record_count(data),
		"solution_entries": solution_counts.x,
		"runtime_rejected_solutions": solution_counts.y,
	}


## Godot 的 JSON 数值解析在极小浮点数上偶有末位舍入；记录差异而不抹成“逐字一致”。
## 相对误差超过 1e-15、结构变化或非数值变化都视为失败。
static func compare_data(left: Variant, right: Variant) -> Dictionary:
	var result := {"equal": true, "float_rounding_count": 0, "max_float_delta": 0.0}
	_compare(left, right, result)
	return result


static func _compare(left: Variant, right: Variant, result: Dictionary) -> void:
	if left == right:
		return
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size():
			result["equal"] = false
			return
		for key in left:
			if not right.has(key):
				result["equal"] = false
				return
			_compare(left[key], right[key], result)
	elif left is Array and right is Array:
		if left.size() != right.size():
			result["equal"] = false
			return
		for index in left.size():
			_compare(left[index], right[index], result)
	elif left is float and right is float:
		var delta := absf(float(left) - float(right))
		if not is_finite(delta) or delta > maxf(absf(float(left)), absf(float(right))) * 1e-15:
			result["equal"] = false
		else:
			result["float_rounding_count"] += 1
			result["max_float_delta"] = maxf(result["max_float_delta"], delta)
	else:
		result["equal"] = false


static func _record_count(value: Variant) -> int:
	if value is Array:
		return value.size()
	if not value is Dictionary:
		return 0
	if value.get("levels") is Array:
		return value["levels"].size()
	var total := 0
	for child in value.values():
		if child is Array:
			total += child.size()
	return total


static func _solution_counts(value: Variant) -> Vector2i:
	var result := Vector2i.ZERO
	if value is Array:
		for child in value:
			result += _solution_counts(child)
	elif value is Dictionary:
		if value.has("solution") and value.has("regionMap"):
			result.x += 1
			var size: int = value["regionMap"].size()
			var rectangular := size > 0
			for row in value["regionMap"]:
				rectangular = rectangular and row is Array and row.size() == size
			if not rectangular or not CORE.validate_solution_entry(value, size):
				result.y += 1
		for child in value.values():
			if child is Array or child is Dictionary:
				result += _solution_counts(child)
	return result


## 通过真正业务入口读取各题库族，覆盖二进制恢复之外的文件名和缓存接线。
static func bank_api_snapshot() -> Dictionary:
	var result: Dictionary = {}
	var bank_api: Object = BANK_DATA
	for prefix in ["", "lk_style_", "gc_", "onefish_"]:
		var sizes: Array = bank_api.call("get_" + prefix + "sizes")
		var counts: Dictionary = {}
		for size in sizes:
			var ranks: Array = bank_api.call("get_" + prefix + "ranks", size)
			for rank in ranks:
				counts["%d/%d" % [size, rank]] = bank_api.call(
					"get_" + prefix + "level_count", size, rank
				)
		result["regular" if prefix.is_empty() else prefix.trim_suffix("_")] = {
			"sizes": sizes, "counts": counts
		}
	for method in [
		"get_sp_levels", "get_lk_levels", "get_lk_modified_levels", "get_hard_r4_levels",
		"get_digit_sp_levels", "get_all_super_hard_levels", "get_all_super_hard_r4_levels",
		"get_sp_tt_levels", "get_single_region_levels", "get_climax_filter_levels",
		"get_all_color_challenge_levels"
	]:
		var levels: Array = bank_api.call(method)
		result[method] = levels.size()
	return result
