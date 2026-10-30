# 已启用内容的只读访问口；静态数据读取可在 Autoload 创建前安全回退内置内容。
class_name ContentContext
extends RefCounted

static var _catalog: RefCounted
static var _media_catalog: RefCounted
static var _generation: int = 0
static var _media: Dictionary = {}
static var _resources: Dictionary = {}
static var _content_error: Dictionary = {}
const MediaMap = preload("res://scripts/framework/content/content_media_map.gd")


static func publish(catalog: RefCounted, media_catalog: RefCounted = null) -> void:
	_catalog = catalog
	_content_error = {}
	if _media_catalog != media_catalog:
		_media_catalog = media_catalog
		_media = {}
		_resources.clear()
		if _media_catalog != null:
			var mapping: Dictionary = _media_catalog.read_json("media")
			if bool(mapping.get("ok", false)) and MediaMap.validate(mapping.value):
				_media = mapping.value
	_generation += 1


static func generation() -> int:
	return _generation


static func read_json(logical_id: String) -> Dictionary:
	if _catalog == null:
		return {"ok": false, "error": "unknown_content"}
	var result: Dictionary = _catalog.read_json(logical_id)
	if not bool(result.get("ok", false)) and result.get("error", "") != "unknown_content":
		report_content_error(logical_id, str(result.get("error", "content_read")))
	return result


static func report_content_error(logical_id: String, reason: String) -> void:
	if _content_error.is_empty():
		_content_error = {"logical_id": logical_id, "release": _catalog.release_id() if _catalog != null else "builtin", "error": reason}


static func content_error() -> Dictionary:
	return _content_error.duplicate(true)


static func data_release_id() -> String:
	return _catalog.release_id() if _catalog != null else "builtin"


static func media_release_id() -> String:
	return _media_catalog.release_id() if _media_catalog != null else "builtin"


static func load_texture(slot: String, fallback: Texture2D = null) -> Texture2D:
	var key := "textures/" + slot
	if _resources.has(key):
		return _resources[key] if _resources[key] != null else fallback
	var relative: String = str(_media.get("textures", {}).get(slot, ""))
	if _media_catalog != null and not relative.is_empty():
		var loaded: Dictionary = _media_catalog.load_image(relative)
		if bool(loaded.get("ok", false)):
			var texture := ImageTexture.create_from_image(loaded.value)
			_resources[key] = texture
			return texture
	_resources[key] = null
	return fallback


static func load_audio(slot: String, fallback: AudioStream = null) -> AudioStream:
	var key := "audio/" + slot
	if _resources.has(key):
		return _resources[key] if _resources[key] != null else fallback
	var relative: String = str(_media.get("audio", {}).get(slot, ""))
	if _media_catalog != null and not relative.is_empty():
		var loaded: Dictionary = _media_catalog.load_audio(relative)
		if bool(loaded.get("ok", false)):
			_resources[key] = loaded.value
			return loaded.value
	_resources[key] = null
	return fallback


static func load_spine(slot: String, fallback: Resource = null) -> Resource:
	var key := "spine/" + slot
	if _resources.has(key):
		return _resources[key] if _resources[key] != null else fallback
	var relative: String = str(_media.get("spine", {}).get(slot, ""))
	if _media_catalog != null and not relative.is_empty():
		var loaded: Dictionary = _media_catalog.load_spine(relative)
		if bool(loaded.get("ok", false)):
			_resources[key] = loaded.value
			return loaded.value
	_resources[key] = null
	return fallback
