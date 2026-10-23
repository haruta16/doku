## 题库文件入口：编辑器读明文 JSON，运行包先解 XOR，再优先解码二进制题库，兼容旧 JSON。
class_name LevelBankIO
extends RefCounted

# ---- 常量：密钥与两个题库目录 ----
const _KEY: String = "meowdoku-2026-bank-secret" # XOR 密钥，明文写死在脚本里，加解密共用
const _EDITOR_DIR: String = "res://assets/editor/levels" # 编辑器环境：明文题库目录
const _RUNTIME_DIR: String = "res://assets/resources/levels" # 非编辑器（导出后）：加密题库目录
const _LEVEL_CODEC: GDScript = preload("res://scripts/module/bank/model/bank_level_codec.gd")
const _BINARY_FORMAT: GDScript = preload("res://scripts/module/bank/model/bank_binary_format.gd")


## 按 editor 特性选择编辑器明文目录或发布包运行时目录。
static func load_json(filename: String) -> Variant:
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
