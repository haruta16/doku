## 逻辑媒体槽位只描述“哪一个槽用哪份已签名包中的资源”，不能执行脚本或访问任意路径。
class_name ContentMediaMap
extends RefCounted

const Manifest = preload("res://scripts/framework/content/content_manifest.gd")
const EXTENSIONS := {"textures": ["png", "jpg", "jpeg", "webp"], "audio": ["ogg", "wav", "mp3"], "spine": ["tres"]}


static func validate(value: Variant) -> bool:
	return bool(inspect(value).ok)


static func inspect(value: Variant) -> Dictionary:
	if not value is Dictionary or value.size() > 3:
		return _invalid("$", "expected an object with at most three media kinds")
	for kind: Variant in value:
		var path: String = "$[" + JSON.stringify(kind) + "]"
		if not kind is String or not EXTENSIONS.has(kind):
			return _invalid(path, "unsupported media kind")
		if not value[kind] is Dictionary or value[kind].size() > 256:
			return _invalid(path, "expected an object with at most 256 media slots")
		for slot: Variant in value[kind]:
			var slot_path: String = path + "[" + JSON.stringify(slot) + "]"
			var relative: Variant = value[kind][slot]
			if not slot is String or not Manifest.safe_relative_path(slot):
				return _invalid(slot_path, "expected a safe logical media slot")
			if not relative is String or not Manifest.safe_relative_path(relative) or relative.get_extension() not in EXTENSIONS[kind]:
				return _invalid(slot_path, "expected a safe relative file path with an allowed " + str(kind) + " extension")
	return {"ok": true, "error": ""}


static func _invalid(path: String, detail: String) -> Dictionary:
	return {"ok": false, "path": path, "detail": detail}
