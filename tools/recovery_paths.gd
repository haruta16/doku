## 原始恢复身份到当前产品路径的单向映射；不会改写历史清单中的身份或哈希。
extends RefCounted

const MANIFEST := "res://tools/validation/fixtures/recovery_122_paths.json"
static var _paths: Dictionary = {}


static func load_paths() -> Dictionary:
	if _paths.is_empty():
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if not value is Dictionary or value.get("schema") != 1 or not value.get("paths") is Dictionary:
			push_error("Invalid 1.22 recovery relocation manifest")
			return {}
		_paths = value["paths"]
	return _paths


static func resolve(original: String) -> String:
	var resource := original if original.begins_with("res://") else "res://" + original
	return str(load_paths().get(resource, resource))
