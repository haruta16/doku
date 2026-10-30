## 只改 Android 二进制 XML 中 uses-sdk / android:targetSdkVersion 的四字节整数。
## 通过标准资源 ID 与元素名称定位；不搜索任意数值 35，不重建清单或改动其他属性。
@tool
extends RefCounted

const MIN_SDK := 24
const TARGET_SDK := 36
const MIN_RESOURCE_ID := 0x0101020c
const TARGET_RESOURCE_ID := 0x01010270
const NO_INDEX := 0xffffffff


static func patch(data: PackedByteArray) -> Dictionary:
	if data.size() < 8 or data.decode_u16(0) != 0x0003:
		return _fail("not Android binary XML")
	var root_header: int = data.decode_u16(2)
	if root_header < 8 or root_header > data.size() or data.decode_u32(4) != data.size():
		return _fail("invalid XML header or length")
	var cursor := root_header
	var strings: Array = []
	var resources: Array[int] = []
	var sdk_count := 0
	var min_sdk := -1
	var min_offset := -1
	var target_sdk := -1
	var target_offset := -1
	while cursor < data.size():
		if cursor + 8 > data.size():
			return _fail("truncated chunk header")
		var kind: int = data.decode_u16(cursor)
		var header: int = data.decode_u16(cursor + 2)
		var size: int = data.decode_u32(cursor + 4)
		if header < 8 or size < header or cursor + size > data.size():
			return _fail("invalid chunk bounds")
		if kind == 0x0001:
			if not strings.is_empty():
				return _fail("duplicate string pool")
			var pool := _read_strings(data, cursor, header, size)
			if not pool.ok:
				return pool
			strings = pool.strings
		elif kind == 0x0180:
			if not resources.is_empty() or (size - header) % 4 != 0:
				return _fail("invalid resource map")
			for offset in range(cursor + header, cursor + size, 4):
				resources.append(data.decode_u32(offset))
		elif kind == 0x0102:
			var ext := cursor + header
			if header != 16 or ext + 20 > cursor + size:
				return _fail("invalid start-element header")
			var name_index: int = data.decode_u32(ext + 4)
			if name_index >= strings.size():
				return _fail("element string index out of bounds")
			var start: int = data.decode_u16(ext + 8)
			var stride: int = data.decode_u16(ext + 10)
			var count: int = data.decode_u16(ext + 12)
			if start < 20 or stride != 20 or ext + start + stride * count > cursor + size:
				return _fail("invalid attribute bounds")
			if strings[name_index] == "uses-sdk":
				sdk_count += 1
				for index in count:
					var attr := ext + start + index * stride
					var attr_name: int = data.decode_u32(attr + 4)
					if attr_name >= resources.size():
						return _fail("unmapped uses-sdk attribute")
					var resource: int = resources[attr_name]
					if resource != MIN_RESOURCE_ID and resource != TARGET_RESOURCE_ID:
						continue
					if data.decode_u16(attr + 12) != 8 or data[attr + 14] != 0:
						return _fail("invalid SDK typed value")
					if data[attr + 15] != 0x10 and data[attr + 15] != 0x11:
						return _fail("SDK attribute is not an integer")
					if data.decode_u32(attr + 8) != NO_INDEX:
						return _fail("SDK attribute unexpectedly also has a raw string value")
					var value: int = data.decode_u32(attr + 16)
					if resource == MIN_RESOURCE_ID:
						if min_sdk != -1:
							return _fail("duplicate minSdkVersion")
						min_sdk = value
						min_offset = attr + 16
					else:
						if target_offset != -1:
							return _fail("duplicate targetSdkVersion")
						target_sdk = value
						target_offset = attr + 16
		cursor += size
	if sdk_count != 1 or min_sdk != MIN_SDK or target_offset < 0 or target_sdk < min_sdk:
		return _fail("expected one uses-sdk with minSdkVersion=24 and an integer targetSdkVersion")
	var output := data.duplicate()
	output.encode_u32(target_offset, TARGET_SDK)
	return {
		"ok": true,
		"data": output,
		"min_sdk": min_sdk,
		"old_target_sdk": target_sdk,
		"target_sdk": TARGET_SDK,
		"target_offset": target_offset,
		"min_offset": min_offset
	}


static func _read_strings(data: PackedByteArray, base: int, header: int, size: int) -> Dictionary:
	if header < 28:
		return _fail("invalid string pool header")
	var count: int = data.decode_u32(base + 8)
	var flags: int = data.decode_u32(base + 16)
	var start: int = data.decode_u32(base + 20)
	var styles: int = data.decode_u32(base + 24)
	var end: int = base + (styles if styles > 0 else size)
	if header + count * 4 > start or start > size or end > base + size or end < base + start:
		return _fail("invalid string pool bounds")
	var result: Array[String] = []
	for index in count:
		var pos: int = base + start + data.decode_u32(base + header + index * 4)
		if pos < base + start or pos >= end:
			return _fail("invalid string offset")
		var unit := 1 if flags & 0x100 else 2
		var length := _read_length(data, pos, end, unit)
		if length.x < 0:
			return _fail("truncated string length")
		if unit == 1:
			length = _read_length(data, length.y, end, 1)
		var bytes := length.x * unit
		if length.x < 0 or length.y + bytes + unit > end:
			return _fail("truncated string data")
		for offset in range(length.y + bytes, length.y + bytes + unit):
			if data[offset] != 0:
				return _fail("string terminator missing")
		var raw := data.slice(length.y, length.y + bytes)
		result.append(raw.get_string_from_utf8() if unit == 1 else raw.get_string_from_utf16())
	return {"ok": true, "strings": result}


static func _read_length(data: PackedByteArray, pos: int, end: int, unit: int) -> Vector2i:
	if pos + unit > end:
		return Vector2i(-1, -1)
	var value: int = data[pos] if unit == 1 else data.decode_u16(pos)
	var mask := 0x80 if unit == 1 else 0x8000
	if value & mask:
		if pos + unit * 2 > end:
			return Vector2i(-1, -1)
		var next: int = data[pos + unit] if unit == 1 else data.decode_u16(pos + unit)
		return Vector2i(((value & (mask - 1)) << (unit * 8)) | next, pos + unit * 2)
	return Vector2i(value, pos + unit)


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "error": "Recovery Android manifest: " + reason}
