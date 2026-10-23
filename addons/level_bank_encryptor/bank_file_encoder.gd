## 本地编辑工具：使用发布包编解码器生成运行题库，供插件与无窗口往返验收共用。
extends RefCounted

const KEY := "meowdoku-2026-bank-secret"
const BINARY_FORMAT = preload("res://scripts/module/bank/model/bank_binary_format.gd")


static func encrypt_file(source_path: String, target_path: String) -> bool:
	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		push_error("LevelBankEncryptor: cannot read %s" % source_path)
		return false
	var bytes := source.get_buffer(source.get_length())
	source.close()

	var parsed := JSON.parse_string(bytes.get_string_from_utf8())
	if parsed == null:
		push_error("LevelBankEncryptor: invalid JSON in %s" % source_path)
		return false

	# 1.22.0 的正式题库优先读取 .bin；只更新同名 JSON 会使编辑内容被旧二进制遮住。
	# 编码流程沿用发布包：紧凑数组 → Variant 字节 → ZSTD → MDBK 头和 SHA-256 → XOR。
	if target_path.ends_with(".bin"):
		bytes = BINARY_FORMAT.encode(parsed)
		if bytes.is_empty():
			push_error("LevelBankEncryptor: cannot encode %s" % source_path)
			return false

	_xor_in_place(bytes)
	var target := FileAccess.open(target_path, FileAccess.WRITE)
	if target == null:
		push_error("LevelBankEncryptor: cannot write %s" % target_path)
		return false
	target.store_buffer(bytes)
	target.close()
	return true


static func _xor_in_place(bytes: PackedByteArray) -> void:
	for index in bytes.size():
		bytes[index] ^= KEY.unicode_at(index % KEY.length())
