## 签名覆盖 manifest 的原始 UTF-8 字节；客户端只接收公钥，不接受未签名远端清单。
class_name ContentManifest
extends RefCounted

const MAX_MANIFEST_BYTES := 1024 * 1024
const MAX_FILE_BYTES := 128 * 1024 * 1024
const MAX_RELEASE_BYTES := 256 * 1024 * 1024
const MAX_ENTRIES := 2048
const FORMAT_VERSION := 1
const RAW_EXTENSIONS := ["json", "png", "jpg", "jpeg", "webp", "ogg", "wav", "mp3"]


static func parse_verified(bytes: PackedByteArray, signature: PackedByteArray, public_key_pem: String, product: String, runtime: String) -> Dictionary:
	if bytes.is_empty() or bytes.size() > MAX_MANIFEST_BYTES:
		return failure("manifest_size")
	var verified := verify_signature(bytes, signature, public_key_pem)
	if not verified.ok:
		return verified
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		return failure("manifest_json")
	return validate(parser.data, product, runtime)


## 清单和频道共享同一个身份验证算法；调用方先限制输入大小，再解释签名后的结构。
static func verify_signature(bytes: PackedByteArray, signature: PackedByteArray, public_key_pem: String) -> Dictionary:
	if signature.is_empty() or signature.size() > 1024:
		return failure("signature_size")
	var key := CryptoKey.new()
	if key.load_from_string(public_key_pem, true) != OK:
		return failure("public_key")
	if not Crypto.new().verify(HashingContext.HASH_SHA256, digest(bytes), signature, key):
		return failure("signature_invalid")
	return {"ok": true, "error": ""}


## 此函数只做结构校验，不能代替 parse_verified 的远端身份验证。
static func validate(value: Dictionary, product: String, runtime: String) -> Dictionary:
	if not exact_keys(value, ["format", "product", "release", "runtime", "files"]):
		return failure("manifest_fields")
	if not integer(value.format) or int(value.format) != FORMAT_VERSION:
		return failure("manifest_format")
	if not value.product is String or value.product != product or not identifier(product):
		return failure("product_mismatch")
	if not value.release is String or not identifier(value.release):
		return failure("release_id")
	if not value.runtime is String or value.runtime != runtime or runtime.is_empty():
		return failure("runtime_mismatch")
	if not value.files is Array or value.files.is_empty() or value.files.size() > MAX_ENTRIES:
		return failure("files_count")
	var ids: Dictionary = {}
	var paths: Dictionary = {}
	var total := 0
	var packs := 0
	for entry: Variant in value.files:
		if not entry is Dictionary or not exact_keys(entry, ["id", "path", "kind", "bytes", "sha256"]):
			return failure("file_fields")
		if not entry.id is String or not safe_relative_path(entry.id) or ids.has(entry.id):
			return failure("file_id")
		if not entry.path is String or not safe_relative_path(entry.path) or paths.has(entry.path):
			return failure("file_path")
		if not entry.kind is String or entry.kind not in ["json", "raw_pck", "spine_pck"]:
			return failure("file_kind")
		if not integer(entry.bytes) or int(entry.bytes) <= 0 or int(entry.bytes) > MAX_FILE_BYTES:
			return failure("file_size")
		if not entry.sha256 is String or not is_sha256(entry.sha256):
			return failure("file_hash")
		if entry.kind == "json" and entry.path.get_extension() != "json":
			return failure("json_extension")
		if entry.kind in ["raw_pck", "spine_pck"]:
			packs += 1
			if packs > 1 or entry.path.get_extension() != "pck":
				return failure("pack_profile")
		ids[entry.id] = true
		paths[entry.path] = true
		total += int(entry.bytes)
	if total > MAX_RELEASE_BYTES:
		return failure("release_size")
	if ids.has("media") and packs == 0:
		return failure("media_requires_pack")
	return {"ok": true, "value": value.duplicate(true), "error": ""}


static func verify_file(path: String, entry: Dictionary) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return failure("file_missing")
	var length := file.get_length()
	file.close()
	if length != int(entry.bytes):
		return failure("file_size_mismatch")
	if FileAccess.get_sha256(path) != entry.sha256:
		return failure("file_hash_mismatch")
	return {"ok": true, "error": ""}


static func digest(bytes: PackedByteArray) -> PackedByteArray:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish()


static func exact_keys(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size():
		return false
	for key: Variant in keys:
		if not value.has(key):
			return false
	return true


static func integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value) and floor(value) == value)


static func identifier(value: String) -> bool:
	if value.is_empty() or value.length() > 80:
		return false
	for index in value.length():
		var char_code := value.unicode_at(index)
		if not ((char_code >= 97 and char_code <= 122) or (char_code >= 48 and char_code <= 57) or char_code in [45, 95]):
			return false
	return true


static func safe_relative_path(value: String) -> bool:
	if value.is_empty() or value.length() > 240 or value.begins_with("/") or value.ends_with("/") or value.contains("\\") or value.contains(":"):
		return false
	for segment: String in value.split("/"):
		if segment.is_empty() or segment in [".", ".."] or segment.begins_with("."):
			return false
		for index in segment.length():
			var char_code := segment.unicode_at(index)
			if not ((char_code >= 97 and char_code <= 122) or (char_code >= 48 and char_code <= 57) or char_code in [45, 95, 46]):
				return false
	return true


static func is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for index in value.length():
		var char_code := value.unicode_at(index)
		if not ((char_code >= 48 and char_code <= 57) or (char_code >= 97 and char_code <= 102)):
			return false
	return true


static func failure(reason: String) -> Dictionary:
	return {"ok": false, "error": reason}
