## 运行时二进制题库：MDBK 头部记录版本、原始长度和压缩内容的 SHA-256，负载使用 Zstandard 压缩。
extends RefCounted

const VERSION: int = 1
const HEADER_SIZE: int = 44
const MAX_PAYLOAD_SIZE: int = 128 * 1024 * 1024
const _CODEC: GDScript = preload("res://scripts/module/bank/model/bank_level_codec.gd")
const _MAGIC: String = "MDBK"


## 把普通 bankData JSON 文件名映射到二进制文件；节奏指标的 .pace.json 保持原名。
static func runtime_filename(filename: String) -> String:
	if (
		filename.begins_with("bankData")
		and filename.ends_with(".json")
		and not filename.ends_with(".pace.json")
	):
		return filename.get_basename() + ".bin"
	return filename


## 先原地紧凑化传入题库，再序列化压缩并添加校验头；失败返回空字节数组。
static func encode(data: Variant) -> PackedByteArray:
	if not (data is Dictionary or data is Array):
		push_error("BankBinaryFormat: 题库根类型无效")
		return PackedByteArray()
	_CODEC.compact_bank(data)
	var payload: PackedByteArray = var_to_bytes(data)
	var payload_size: int = payload.size()
	if payload_size == 0 or payload_size > MAX_PAYLOAD_SIZE:
		push_error("BankBinaryFormat: 题库负载长度无效，bytes=%d" % payload_size)
		return PackedByteArray()
	var compressed: PackedByteArray = payload.compress(FileAccess.COMPRESSION_ZSTD)
	payload.clear()
	if compressed.is_empty():
		push_error("BankBinaryFormat: 题库压缩失败")
		return PackedByteArray()
	var header: PackedByteArray = _MAGIC.to_utf8_buffer()
	header.resize(HEADER_SIZE)
	header.encode_u32(4, VERSION)
	header.encode_u32(8, payload_size)
	var digest: PackedByteArray = _hash(compressed)
	for index in digest.size():
		header[12 + index] = digest[index]
	header.append_array(compressed)
	return header


## 校验魔数、版本、长度和摘要后解压，统一返回 ok、data、error 三个字段。
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() <= HEADER_SIZE or bytes.slice(0, 4) != _MAGIC.to_utf8_buffer():
		return _failure("invalid_header")
	if bytes.decode_u32(4) != VERSION:
		return _failure("unsupported_version")
	var payload_size: int = bytes.decode_u32(8)
	if payload_size == 0 or payload_size > MAX_PAYLOAD_SIZE:
		return _failure("invalid_payload_size")
	var compressed: PackedByteArray = bytes.slice(HEADER_SIZE)
	if _hash(compressed) != bytes.slice(12, HEADER_SIZE):
		return _failure("checksum_mismatch")
	var payload: PackedByteArray = compressed.decompress(payload_size, FileAccess.COMPRESSION_ZSTD)
	compressed.clear()
	if payload.size() != payload_size:
		return _failure("decompression_failed")
	var data: Variant = bytes_to_var(payload)
	payload.clear()
	if not (data is Dictionary or data is Array):
		return _failure("invalid_root_type")
	return {"ok": true, "data": data, "error": ""}


## 计算压缩字节的 SHA-256，用于发现题库内容损坏。
static func _hash(bytes: PackedByteArray) -> PackedByteArray:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish()


## 包装解码失败原因；调用方通过 ok 判断，失败时 data 为 null。
static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "data": null, "error": reason}
