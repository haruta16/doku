## 逻辑媒体槽位只描述“哪一个槽用哪份已签名包中的资源”，不能执行脚本或访问任意路径。
class_name ContentMediaMap
extends RefCounted

const Manifest = preload("res://scripts/framework/content/content_manifest.gd")
const EXTENSIONS := {"textures": ["png", "jpg", "jpeg", "webp"], "audio": ["ogg", "wav", "mp3"], "spine": ["tres"]} # 各媒体类别允许引用的扩展名；仅定义通用文件种类，不定义产品槽名。


## 只取结构检查的成功标志；需要定位具体错误时用 inspect。
static func validate(value: Variant) -> bool:
	return bool(inspect(value).ok)


## 验证三类媒体映射、每类最多 256 个槽，以及槽名/文件相对路径；失败返回 JSON 路径定位。
## 这里只检查映射结构，实际文件是否在已签名包内由 ContentStore 检查。
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


## 构造结构错误的位置和说明；path 指向映射中的槽，不是可直接打开的文件路径。
static func _invalid(path: String, detail: String) -> Dictionary:
	return {"ok": false, "path": path, "detail": detail}
