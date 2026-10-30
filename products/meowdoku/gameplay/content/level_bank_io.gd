## 题库文件入口：编辑器读明文 JSON，运行包先解 XOR，再优先解码二进制题库，兼容旧 JSON。
class_name LevelBankIO
extends RefCounted

# ---- 常量：密钥与两个题库目录 ----
const _KEY: String = "meowdoku-2026-bank-secret" # XOR 密钥，明文写死在脚本里，加解密共用
const _EDITOR_DIR: String = "res://products/meowdoku/assets/editor/levels" # 编辑器环境：明文题库目录
const _RUNTIME_DIR: String = "res://products/meowdoku/assets/resources/levels" # 非编辑器（导出后）：加密题库目录
const _LEVEL_CODEC: GDScript = preload("res://products/meowdoku/gameplay/content/bank_level_codec.gd")
const _BINARY_FORMAT: GDScript = preload("res://products/meowdoku/gameplay/content/bank_binary_format.gd")


## 按 editor 特性选择编辑器明文目录或发布包运行时目录。
static func load_builtin(filename: String) -> Variant:
	if OS.has_feature("editor"):
		return _load_text_json(_EDITOR_DIR + "/" + filename, filename, false)
	return _load_runtime_json(filename)


## 优先读取对应 .bin 并解 XOR、校验和解压；没有二进制文件时才回退加密 JSON。
static func _load_runtime_json(filename: String) -> Variant:
	var binary_filename: String = _BINARY_FORMAT.runtime_filename(filename)
	var binary_path: String = _RUNTIME_DIR + "/" + binary_filename
	if binary_filename != filename and FileAccess.file_exists(binary_path):
		var bytes: PackedByteArray = _read_bytes(binary_path)
		_xor_inplace(bytes)
		var result: Dictionary = _BINARY_FORMAT.decode(bytes)
		bytes.clear()
		if not result["ok"]:
			push_error(
				"LevelBankIO: 二进制题库读取失败，file=%s reason=%s" % [binary_filename, result["error"]]
			)
			return null
		return result["data"]
	return _load_text_json(_RUNTIME_DIR + "/" + filename, filename, true)


## 读取完整文件字节，文件缺失或打开失败返回空数组。
static func _read_bytes(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("LevelBankIO: cannot open %s" % path)
		return PackedByteArray()
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	return bytes


## 按需解 XOR 后解析 UTF-8 JSON，普通题库字段会原地紧凑化以减少内存。
static func _load_text_json(path: String, filename: String, encrypted: bool) -> Variant:
	var bytes: PackedByteArray = _read_bytes(path)
	if bytes.is_empty():
		return null
	if encrypted:
		_xor_inplace(bytes)
	var text: String = bytes.get_string_from_utf8()
	var data: Variant = JSON.parse_string(text)
	bytes.clear()
	text = ""
	if _BINARY_FORMAT.runtime_filename(filename) != filename:
		_LEVEL_CODEC.compact_bank(data)
	return data


## 原地 XOR 解密：密钥按字节循环异或，加密与解密是同一套操作
static func _xor_inplace(bytes: PackedByteArray) -> void:
	var key_len: int = _KEY.length()
	if key_len == 0 or bytes.is_empty():
		return
	for i in bytes.size():
		bytes[i] ^= _KEY.unicode_at(i % key_len)


## 更新包仍使用已验证的 JSON 内容合同；内置库保留 1.22 的二进制优先读取。
static func load_json(filename: String) -> Variant:
	var logical_id: String = "doku/levels/" + filename.get_basename().to_lower()
	var updated: Dictionary = ContentContext.read_json(logical_id)
	if bool(updated.get("ok", false)):
		var value: Variant = updated.value
		_annotate_entries(value, {"logical_id": logical_id, "release": str(updated.release), "fallback_error": ""})
		if _BINARY_FORMAT.runtime_filename(filename) != filename:
			_LEVEL_CODEC.compact_bank(value)
		return value
	if updated.get("error", "") != "unknown_content":
		return null
	if filename.ends_with(".pace.json"):
		# 被替换的题库不能沿用基包按索引绑定的旧节奏；缺少同批旁表就禁用此旁表。
		var main_id: String = logical_id.trim_suffix(".pace")
		if ContentContext.read_json(main_id).get("ok", false):
			return null
	var builtin: Variant = load_builtin(filename)
	_annotate_entries(builtin, {"logical_id": logical_id, "release": "builtin", "fallback_error": ""})
	return builtin


static func builtin_by_id(logical_id: String) -> Dictionary:
	if not logical_id.begins_with("doku/levels/"):
		return {"ok": false, "error": "unknown_content"}
	var basename: String = logical_id.trim_prefix("doku/levels/")
	for directory: String in [_EDITOR_DIR, _RUNTIME_DIR]:
		for filename: String in DirAccess.get_files_at(directory):
			if filename.get_basename().to_lower() != basename or filename.get_extension() not in ["json", "bin"]:
				continue
			var json_name: String = filename.get_basename() + ".json" if filename.ends_with(".bin") else filename
			var value: Variant = _materialize_json_value(load_builtin(json_name))
			if value != null:
				_annotate_entries(value, {"logical_id": logical_id, "release": "builtin", "fallback_error": ""})
				return {"ok": true, "value": value, "release": "builtin"}
	return {"ok": false, "error": "builtin_bank_missing:" + logical_id}


static func _annotate_entries(value: Variant, provenance: Dictionary) -> void:
	if value is Dictionary:
		if value.has("regionMap") and value.has("solution"):
			value["_content_provenance"] = provenance.duplicate(true)
			return
		for child: Variant in value.values():
			_annotate_entries(child, provenance)
	elif value is Array:
		for child: Variant in value:
			_annotate_entries(child, provenance)


## 目录/发布校验提供 JSON 值语义；紧凑缓存仅由 load_json 留给游戏热路径。
static func _materialize_json_value(value: Variant) -> Variant:
	if value is Dictionary:
		if value.has("regionMap") and value.has("solution"):
			return _LEVEL_CODEC.materialize_entry(value, true)
		var result: Dictionary = {}
		for key: Variant in value:
			result[key] = _materialize_json_value(value[key])
		return result
	if value is Array:
		var result: Array = []
		for child: Variant in value:
			result.append(_materialize_json_value(child))
		return result
	return value


static func is_optional_pace_omission(filename: String) -> bool:
	if not filename.ends_with(".pace.json"):
		return false
	var id: String = "doku/levels/" + filename.get_basename().to_lower()
	return ContentContext.read_json(id.trim_suffix(".pace")).get("ok", false) and ContentContext.read_json(id).get("error") == "unknown_content"
