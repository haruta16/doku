## 已启用内容的只读访问口；静态数据读取可在 Autoload 创建前安全回退内置内容。
## 宿主发布数据目录与媒体目录，本类只负责查找、缓存和记录首个读取错误；不下载、不安装。
## 静态字段是进程级上下文，适用于一个活动产品；不提供同进程多产品之间的隔离。
class_name ContentContext
extends RefCounted

static var _catalog: RefCounted # 当前数据目录；null 表示尚未发布，调用方可使用内置数据。
static var _media_catalog: RefCounted # 当前媒体目录；可与数据目录不同，方便把对局数据冻结而让表现资源独立切换。
static var _generation: int = 0 # 每次 publish 都递增的发布代次；消费者可用它使自身缓存失效。
static var _media: Dictionary = {} # 媒体槽映射：textures/audio/spine → 槽名 → 发布内相对路径。
static var _resources: Dictionary = {} # 按“种类/槽名”缓存已加载资源；null 也会缓存，表示本目录中该槽加载失败。
static var _content_error: Dictionary = {} # 当前数据发布后遇到的首个异常；保留根因，不让后续连锁失败覆盖它。
const MediaMap = preload("res://scripts/framework/content/content_media_map.gd") # 校验媒体映射的通用结构，不决定产品的具体槽名。


## 发布可读取的目录并增加代次；媒体目录换了才清资源缓存，数据目录刷新会清首个错误。
## 调用方应先完成安装/验证，再发布；这里不校验发布包，也不负责结束旧对局。
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


## 返回发布代次；它表示上下文变更次数，不是服务端 release 的版本号。
static func generation() -> int:
	return _generation


## 按逻辑 ID 读取活动数据；没有目录或未登记该 ID 时返回 unknown_content，留给调用方回退。
## 已登记内容读坏会登记首个内容错误，避免将损坏悄悄当作普通缺省。
static func read_json(logical_id: String) -> Dictionary:
	if _catalog == null:
		return {"ok": false, "error": "unknown_content"}
	var result: Dictionary = _catalog.read_json(logical_id)
	if not bool(result.get("ok", false)) and result.get("error", "") != "unknown_content":
		report_content_error(logical_id, str(result.get("error", "content_read")))
	return result


## 首次异常才登记逻辑 ID、数据 release 和原因，供宿主在安全时机处理失败。
static func report_content_error(logical_id: String, reason: String) -> void:
	if _content_error.is_empty():
		_content_error = {"logical_id": logical_id, "release": _catalog.release_id() if _catalog != null else "builtin", "error": reason}


## 返回首个错误的深拷贝；读取方不能通过这个字典改写全局错误记录。
static func content_error() -> Dictionary:
	return _content_error.duplicate(true)


## 返回当前数据版本身份；尚未发布目录时用 builtin 表示内置来源。
static func data_release_id() -> String:
	return _catalog.release_id() if _catalog != null else "builtin"


## 返回当前媒体版本身份；与数据版本分别查询，避免把表现更新误当作换题源。
static func media_release_id() -> String:
	return _media_catalog.release_id() if _media_catalog != null else "builtin"


## 按纹理槽惰性加载 Image 并转换成 ImageTexture；缺槽/读取失败时返回本次调用的 fallback。
## 成功资源和失败结果都会缓存；缓存失败不固定 fallback，调用方仍可传不同内置纹理。
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


## 按音频槽惰性加载并缓存 AudioStream；缺槽或读取失败时沿用调用方的内置声音。
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


## 按 Spine 槽读取已挂载资源并缓存；失败时返回内置资源，具体动画/皮肤兼容性另行校验。
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
