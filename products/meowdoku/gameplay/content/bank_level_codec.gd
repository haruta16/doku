## 题库字段编码：把区域矩阵和解题向量压成紧凑数组，需要交给玩法层时再展开。
extends RefCounted

const VECTOR_FIELDS: Array[String] = ["solution", "stepHist", "stepOrderZ"]


## 遍历支持的题库根结构并原地替换字段；调用方持有的字典和数组会一起改变。
static func compact_bank(data: Variant) -> void:
	if data is Array:
		_compact_entries(data as Array)
	elif data is Dictionary:
		var dictionary: Dictionary = data
		if dictionary.get("levels") is Array:
			_compact_entries(dictionary["levels"] as Array)
		else:
			var keys: Array = dictionary.keys()
			for key: Variant in keys:
				if dictionary[key] is Array:
					_compact_entries(dictionary[key] as Array)


## 复制题目字典并展开区域、答案和步骤向量；deep_copy 决定其他嵌套数据是否深拷贝。
static func materialize_entry(entry: Dictionary, deep_copy: bool = false) -> Dictionary:
	var result: Dictionary = entry.duplicate(deep_copy)
	if result.has("regionMap"):
		result["regionMap"] = _expand_regions(result["regionMap"])
	for field: String in VECTOR_FIELDS:
		if result.has(field):
			result[field] = _expand_vector(result[field])
	return result


## 把紧凑的区域字节展开为二维数组；无法得到数组时返回空数组。
static func get_region_map(entry: Dictionary) -> Array:
	var value: Variant = _expand_regions(entry.get("regionMap", []))
	return value as Array if value is Array else []


## 把答案向量展开为普通数组，兼容原有数组和紧凑整数数组。
static func get_solution(entry: Dictionary) -> Array:
	var value: Variant = _expand_vector(entry.get("solution", []))
	return value as Array if value is Array else []


## 逐题原地压缩区域、答案、步骤直方图和步骤顺序，字段缺失时跳过。
static func _compact_entries(entries: Array) -> void:
	for entry_value: Variant in entries:
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		if entry.has("regionMap"):
			entry["regionMap"] = _compact_regions(entry["regionMap"])
		if entry.has("solution"):
			entry["solution"] = _compact_integers(entry["solution"], true)
		if entry.has("stepHist"):
			entry["stepHist"] = _compact_integers(entry["stepHist"], false)
		if entry.has("stepOrderZ"):
			entry["stepOrderZ"] = _compact_floats(entry["stepOrderZ"])


## 仅把正方形、取值在 0～255 的区域矩阵压平；不符合格式时保留原值。
static func _compact_regions(value: Variant) -> Variant:
	if not value is Array:
		return value
	var regions: Array = value
	var size: int = regions.size()
	var packed: PackedByteArray = PackedByteArray()
	packed.resize(size * size)
	var offset: int = 0
	for row_value: Variant in regions:
		if not row_value is Array:
			return value
		var row: Array = row_value
		if row.size() != size:
			return value
		for cell: Variant in row:
			if not _is_integer_in_range(cell, 0, 255):
				return value
			packed[offset] = int(cell)
			offset += 1
	return packed


## 校验整数范围后选择字节数组或 32 位整数数组，避免转换时截断。
static func _compact_integers(value: Variant, use_bytes: bool) -> Variant:
	if not value is Array:
		return value
	var values: Array = value
	var minimum: int = 0 if use_bytes else -2147483648
	var maximum: int = 255 if use_bytes else 2147483647
	for element: Variant in values:
		if not _is_integer_in_range(element, minimum, maximum):
			return value
	return PackedByteArray(values) if use_bytes else PackedInt32Array(values)


## 确认数值有限且整数转换不丢精度后，压成 64 位浮点数组。
static func _compact_floats(value: Variant) -> Variant:
	if not value is Array:
		return value
	var values: Array = value
	for element: Variant in values:
		if not (element is int or element is float) or not is_finite(float(element)):
			return value
		if element is int and int(float(element)) != element:
			return value
	return PackedFloat64Array(values)


## 排除非数值、无穷值、小数和越界值，保证紧凑整数表示可还原。
static func _is_integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	if not (value is int or value is float):
		return false
	var number: float = float(value)
	if not is_finite(number) or number < minimum or number > maximum:
		return false
	return float(int(value)) == number


## 按字节数量开平方恢复正方形区域矩阵，单元值转成浮点数以兼容原 JSON 数据。
static func _expand_regions(value: Variant) -> Variant:
	if not value is PackedByteArray:
		return value
	var packed: PackedByteArray = value
	var size: int = int(sqrt(float(packed.size())))
	if size * size != packed.size():
		return value
	var regions: Array = []
	regions.resize(size)
	for row_index in size:
		var row: Array = []
		row.resize(size)
		for column_index in size:
			row[column_index] = float(packed[row_index * size + column_index])
		regions[row_index] = row
	return regions


## 把紧凑整数或浮点向量还原为普通数组；其他类型原样返回。
static func _expand_vector(value: Variant) -> Variant:
	if value is PackedByteArray or value is PackedInt32Array:
		var values: Array = []
		values.resize(value.size())
		for index in values.size():
			values[index] = float(value[index])
		return values
	if value is PackedFloat64Array:
		return Array(value)
	return value
