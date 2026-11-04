## 可变频道只选择不可变发布；签名覆盖原始字节，清单哈希绑定本次选择。
## 同一频道 revision 必须递增。回退内容时发布更高 revision，指向旧 release 即可。
class_name ContentChannel
extends RefCounted

const Manifest = preload("res://scripts/framework/content/content_manifest.gd") # 复用清单的验签、标识符、哈希与错误回执工具。
const MAX_BYTES := 64 * 1024 # 频道文件最大 64 KiB；先限长再解析，避免入口文件无限膨胀。
const MAX_TARGETS := 64 # 同一频道最多登记 64 个运行时目标；每种 runtime 只能出现一次。
const MAX_REVISION := 9007199254740991 # JSON number 在各发布工具中均可精确表示。


## 入口顺序：限制字节数 → 对原始字节验签 → 解析 JSON → 校验并选择兼容 runtime。
## 成功回执附上频道原文 SHA-256，供持久化水位识别“同 revision 换了内容”的异常。
static func parse_verified(bytes: PackedByteArray, signature: PackedByteArray, public_key: String, product: String, channel: String, runtime: String, allow_local_http: bool = false) -> Dictionary:
	if bytes.is_empty() or bytes.size() > MAX_BYTES:
		return Manifest.failure("channel_size")
	var signed := Manifest.verify_signature(bytes, signature, public_key)
	if not signed.ok:
		return signed
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		return Manifest.failure("channel_json")
	var result := validate(parser.data, product, channel, runtime, allow_local_http)
	if result.ok:
		result["sha256"] = Manifest.digest(bytes).hex_encode()
	return result


## 检查频道字段、产品身份、revision 和所有目标，再选出当前 runtime 对应的不可变发布。
## 这里只检查本次文档；是否倒退或复用 revision 的判断由保存频道水位的 ContentStore 执行。
static func validate(value: Dictionary, product: String, channel: String, runtime: String, allow_local_http: bool = false) -> Dictionary:
	if not Manifest.exact_keys(value, ["format", "product", "channel", "revision", "targets"]):
		return Manifest.failure("channel_fields")
	if not Manifest.integer(value.format) or int(value.format) != 1:
		return Manifest.failure("channel_format")
	if not value.product is String or value.product != product or not Manifest.identifier(product):
		return Manifest.failure("product_mismatch")
	if not value.channel is String or value.channel != channel or not Manifest.identifier(channel):
		return Manifest.failure("channel_mismatch")
	if not Manifest.integer(value.revision) or value.revision < 1 or value.revision > MAX_REVISION:
		return Manifest.failure("channel_revision")
	if not value.targets is Array or value.targets.is_empty() or value.targets.size() > MAX_TARGETS:
		return Manifest.failure("channel_targets")
	var runtimes: Dictionary = {}
	var selected: Dictionary = {}
	for entry: Variant in value.targets:
		if not entry is Dictionary or not Manifest.exact_keys(entry, ["runtime", "release", "url", "manifest_sha256"]):
			return Manifest.failure("channel_target_fields")
		if not entry.runtime is String or entry.runtime.is_empty() or entry.runtime.length() > 160 or runtimes.has(entry.runtime):
			return Manifest.failure("channel_runtime")
		if not entry.release is String or not Manifest.identifier(entry.release):
			return Manifest.failure("release_id")
		if not entry.url is String or not allowed_url(entry.url, allow_local_http):
			return Manifest.failure("channel_url")
		if not entry.manifest_sha256 is String or not Manifest.is_sha256(entry.manifest_sha256):
			return Manifest.failure("channel_manifest_hash")
		runtimes[entry.runtime] = true
		if entry.runtime == runtime:
			selected = entry.duplicate(true)
	if selected.is_empty():
		return Manifest.failure("channel_no_compatible_release")
	return {"ok": true, "error": "", "value": selected, "channel": channel, "revision": int(value.revision)}


## 只接受没有凭证、查询串和重定向需求的绝对地址；开发 HTTP 仅限 loopback。
static func allowed_url(url: String, allow_local_http: bool) -> bool:
	if url.length() > 2048 or url.contains("?") or url.contains("#") or url.contains("\\") or url.contains("@"):
		return false
	for index in url.length():
		if url.unicode_at(index) <= 32 or url.unicode_at(index) > 126:
			return false
	var secure := url.begins_with("https://")
	if not secure and not (allow_local_http and url.begins_with("http://")):
		return false
	var remainder := url.substr(8 if secure else 7)
	var authority := remainder.get_slice("/", 0)
	if authority.is_empty() or authority.count(":") > 1:
		return false
	var host := authority.get_slice(":", 0)
	if host.is_empty() or host.begins_with(".") or host.ends_with(".") or host.contains(".."):
		return false
	for index in host.length():
		var code := host.unicode_at(index)
		if not ((code >= 65 and code <= 90) or (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code in [45, 46]):
			return false
	if authority.contains(":"):
		var port := authority.get_slice(":", 1)
		if not port.is_valid_int() or port.to_int() < 1 or port.to_int() > 65535:
			return false
	if not secure and host not in ["localhost", "127.0.0.1"]:
		return false
	return true
