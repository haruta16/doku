## 交付前最终校验：展开紧凑字段、验证整数边界和矩阵形状，常规题还要通过完整摆猫规则。
class_name FinalLevelValidator
extends RefCounted


## 返回规范化题目及有效性；固定特殊来源使用兼容规则，服务端推荐仍走常规校验。
static func validate(entry: Dictionary, _level_num: int) -> Dictionary:
	entry = BankData.materialize_entry(entry)
	var source: String = str(entry.get("_bank_source_main", entry.get("_bank_source", "")))
	var is_special: bool = source in ["sp", "lk"] and not entry.has("_rec_qid")
	var regions_value: Variant = entry.get("regionMap", [])
	if not regions_value is Array:
		return _rejected(entry, "invalid_region_type")
	var raw_regions: Array = regions_value
	var size_value: Variant = entry.get("size", raw_regions.size())
	if not is_integer_value(size_value):
		return _rejected(entry, "invalid_size")
	var size: int = int(size_value)
	if not is_special:
		if size <= 0:
			return _rejected(entry, "invalid_size")
		if raw_regions.size() != size:
			return _rejected(entry, "invalid_region_rows")

	var int_regions: Array = []
	for row_value: Variant in raw_regions:
		if not row_value is Array:
			return _rejected(entry, "invalid_region_row_type")
		var row: Array = row_value
		if not is_special and row.size() != size:
			return _rejected(entry, "invalid_region_columns")
		var int_row: Array = []
		for region_value: Variant in row:
			if not is_integer_value(region_value):
				return _rejected(entry, "invalid_region_value")
			var region_id: int = int(region_value)
			if not is_special and (region_id < 0 or region_id >= size):
				return _rejected(entry, "invalid_region_value")
			int_row.append(region_id)
		int_regions.append(int_row)
	var normalized: Dictionary = entry.duplicate(true)
	normalized["regionMap"] = int_regions
	normalized["size"] = size

	var numeric_fields: Array[String] = [
		"seed", "steps", "r", "maxR", "r1", "r2", "r3", "r4", "r5", "_bank_rank", "_rec_slot_index"
	]
	for field: String in numeric_fields:
		if not entry.has(field):
			continue
		var number_value: Variant = entry[field]
		if not is_integer_value(number_value):
			return _rejected(entry, "invalid_numeric_metadata")
		normalized[field] = int(number_value)
	if entry.has("_rec_is_explore"):
		var explore_value: Variant = entry["_rec_is_explore"]
		if not explore_value is bool and not is_integer_value(explore_value):
			return _rejected(entry, "invalid_explore_type")
		normalized["_rec_is_explore"] = (
			bool(explore_value) if explore_value is bool else int(explore_value) != 0
		)

	if is_special:
		if entry.has("solution"):
			var special_solution_value: Variant = entry["solution"]
			if not special_solution_value is Array:
				return _rejected(entry, "invalid_solution_type")
			var special_solution: Array = special_solution_value
			for column_value: Variant in special_solution:
				if not is_integer_value(column_value):
					return _rejected(entry, "invalid_solution_column")
		normalized["_delivery_size"] = size
		normalized["_delivery_rank"] = int(normalized.get("_bank_rank", 1))
		return {"valid": true, "entry": normalized, "reason": ""}

	var solution_value: Variant = entry.get("solution", [])
	if not solution_value is Array:
		return _rejected(entry, "invalid_solution_type")
	var raw_solution: Array = solution_value
	if raw_solution.size() != size:
		return _rejected(entry, "invalid_solution_length")
	var int_solution: Array = []
	for column_value: Variant in raw_solution:
		if not is_integer_value(column_value):
			return _rejected(entry, "invalid_solution_column")
		var col: int = int(column_value)
		if col < 0 or col >= size:
			return _rejected(entry, "invalid_solution_column")
		int_solution.append(col)
	normalized["solution"] = int_solution
	if not QueendokuCore.validate_solution_entry(normalized, size):
		return _rejected(entry, "invalid_solution_rules")

	normalized["_delivery_size"] = size
	normalized["_delivery_rank"] = int(normalized.get("_bank_rank", 1))
	return {"valid": true, "entry": normalized, "reason": ""}


## 接受整数、可精确表示为 64 位整数的浮点数及合法整数字符串，排除截断和溢出。
static func is_integer_value(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		var number: float = value
		return (
			is_finite(number)
			and number == floorf(number)
			and number >= -9223372036854775808.0
			and number < 9223372036854775808.0
		)
	if value is String:
		var text: String = value
		if not text.is_valid_int():
			return false

		var negative: bool = text.begins_with("-")
		var digits: String = text.trim_prefix("-").trim_prefix("+")
		while digits.length() > 1 and digits.begins_with("0"):
			digits = digits.substr(1)
		var canonical: String = "-" + digits if negative and digits != "0" else digits
		return str(int(text)) == canonical
	return false


## 统一包装拒绝结果并保留原题目与具体原因。
static func _rejected(entry: Dictionary, reason: String) -> Dictionary:
	return {"valid": false, "entry": entry, "reason": reason}
