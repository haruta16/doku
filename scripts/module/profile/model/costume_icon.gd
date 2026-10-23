## 服装缩略图的资源查询；先判断图标是否存在，再向 UI 提供对应纹理。

class_name CostumeIcon
extends RefCounted

const _DIR: String = "res://assets/sprites/profile/costume/"

static var _cache: Dictionary = {}


static func has_icon(costume_id: int) -> bool:
	return texture_for(costume_id) != null


static func texture_for(costume_id: int) -> Texture2D:
	if _cache.has(costume_id):
		return _cache[costume_id]
	var tex: Texture2D = null
	var path: String = _path_for(costume_id)
	if not path.is_empty() and ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_cache[costume_id] = tex
	return tex


static func _path_for(costume_id: int) -> String:
	if not CostumeCatalog.is_valid(costume_id):
		return ""
	return "%scat_costume_%02d.png" % [_DIR, CostumeCatalog.asset_index(costume_id)]
