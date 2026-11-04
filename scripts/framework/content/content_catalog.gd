## 每个发布版本一份目录。对外返回副本，旧局保留已解析题面，不依赖全局可变缓存。
class_name ContentCatalog
extends RefCounted

const Validation = preload("res://scripts/framework/content/content_validation.gd")

const Manifest = preload("res://scripts/framework/content/content_manifest.gd")
const RawPack = preload("res://scripts/framework/content/content_raw_pack.gd")
const MediaMap = preload("res://scripts/framework/content/content_media_map.gd")

var _root: String # 已安装发布的磁盘目录；JSON 在此读取，媒体 PCK 的身份也以此定位。
var _manifest: Dictionary # 构造时复制的已验证清单；一个 Catalog 始终代表同一个发布。
var _json: Dictionary = {} # 逻辑 ID → 已解析 JSON；对外返回深拷贝，调用方不能改动共享缓存。
var _validator: Validation # 产品提供的逐文件/整目录/媒体校验入口；公共层不认识具体题库格式。


## 绑定一个发布目录、清单副本和可选产品校验器；这里不自行验签或扫描文件。
func _init(root: String = "", manifest: Dictionary = {}, validator: Validation = null) -> void:
	_root = root
	_manifest = manifest.duplicate(true)
	_validator = validator


## 读取此目录固定的发布身份，供对局记录来源或诊断回执引用。
func release_id() -> String:
	return str(_manifest.get("release", ""))


## 返回清单深拷贝，防止消费者通过修改返回字典改变本目录的寻址规则。
func manifest_snapshot() -> Dictionary:
	return _manifest.duplicate(true)


## 原始媒体资源按发布目录寻址，不能借此访问基包或另一发布版本。
func raw_asset_path(relative_path: String) -> Dictionary:
	if not Manifest.safe_relative_path(relative_path) or relative_path.get_extension() not in Manifest.RAW_EXTENSIONS:
		return Manifest.failure("raw_asset_path")
	for entry: Dictionary in _manifest.get("files", []):
		if entry.kind not in ["raw_pck", "spine_pck"]:
			continue
		var pack_path := _root.path_join(entry.path)
		if RawPack.mounted_path() != pack_path:
			return Manifest.failure("pack_not_active")
		var path := "res://content/%s/%s/%s" % [_manifest.product, _manifest.release, relative_path]
		if not FileAccess.file_exists(path) and not (entry.kind == "spine_pck" and ResourceLoader.exists(path)):
			return Manifest.failure("raw_asset_missing")
		return {"ok": true, "value": path, "error": ""}
	return Manifest.failure("no_raw_pack")


## 先限制到当前已挂载发布的媒体路径，再解码为 Image；导出后原图不存在时从导入纹理取图。
func load_image(relative_path: String) -> Dictionary:
	var resolved := raw_asset_path(relative_path)
	if not resolved.ok:
		return resolved
	if relative_path.get_extension() not in ["png", "jpg", "jpeg", "webp"]:
		return Manifest.failure("not_image")
	if not FileAccess.file_exists(resolved.value):
		var texture := ResourceLoader.load(resolved.value) as Texture2D
		if texture == null:
			return Manifest.failure("image_decode")
		return {"ok": true, "value": texture.get_image(), "error": ""}
	var image := Image.new()
	if image.load(resolved.value) != OK:
		return Manifest.failure("image_decode")
	return {"ok": true, "value": image, "error": ""}


## 在当前发布命名空间内按扩展名解码 ogg/wav/mp3；不认识的格式或解码失败返回明确错误。
func load_audio(relative_path: String) -> Dictionary:
	var resolved := raw_asset_path(relative_path)
	if not resolved.ok:
		return resolved
	var stream: AudioStream
	match relative_path.get_extension():
		"ogg": stream = AudioStreamOggVorbis.load_from_file(resolved.value)
		"wav": stream = AudioStreamWAV.load_from_file(resolved.value)
		"mp3": stream = AudioStreamMP3.load_from_file(resolved.value)
		_: return Manifest.failure("not_audio")
	if stream == null:
		return Manifest.failure("audio_decode")
	return {"ok": true, "value": stream, "error": ""}


## 只加载当前 spine_pck 内的 .tres，并确认它是带 atlas 与 skeleton 依赖的 Spine 数据资源。
func load_spine(relative_path: String) -> Dictionary:
	if not Manifest.safe_relative_path(relative_path) or relative_path.get_extension() != "tres":
		return Manifest.failure("spine_path")
	for entry: Dictionary in _manifest.get("files", []):
		if entry.kind != "spine_pck":
			continue
		if RawPack.mounted_path() != _root.path_join(entry.path):
			return Manifest.failure("pack_not_active")
		var path := "res://content/%s/%s/%s" % [_manifest.product, _manifest.release, relative_path]
		if not ResourceLoader.exists(path):
			return Manifest.failure("spine_missing")
		var resource := ResourceLoader.load(path)
		if resource == null or resource.get_class() != "SpineSkeletonDataResource" or resource.get("atlas_res") == null or resource.get("skeleton_file_res") == null:
			return Manifest.failure("spine_decode")
		return {"ok": true, "value": resource, "error": ""}
	return Manifest.failure("no_spine_pack")


## 已挂载后验证将被产品使用的媒体。失败必须让启动器保留试运行标记并等待下一次冷启动回退。
func validate_registered_media() -> Dictionary:
	var mapping := read_json("media")
	if mapping.ok:
		if not MediaMap.validate(mapping.value):
			return Manifest.failure("media_schema")
		for kind: String in mapping.value:
			for relative: String in mapping.value[kind].values():
				var loaded: Dictionary
				match kind:
					"textures": loaded = load_image(relative)
					"audio": loaded = load_audio(relative)
					"spine": loaded = load_spine(relative)
				if not loaded.ok:
					return loaded
	elif mapping.error != "unknown_content":
		return mapping
	for entry: Dictionary in _manifest.get("files", []):
		if entry.kind != "spine_pck":
			continue
		var checked: Dictionary = RawPack.inspect(_root.path_join(entry.path), _manifest.product, _manifest.release, entry.kind)
		if not checked.ok:
			return checked
		var prefix := "res://content/%s/%s/" % [_manifest.product, _manifest.release]
		for resource: Dictionary in checked.value:
			if resource.path.ends_with(".tres"):
				var loaded := load_spine(resource.path.trim_prefix(prefix))
				if not loaded.ok:
					return loaded
	if _validator != null:
		return _validator.check_media(self)
	return {"ok": true, "error": ""}


## 按清单逻辑 ID 查找 JSON，首次读取先检查长度与 SHA-256，再解析并缓存；每次返回深拷贝。
## 成功回执附 release 身份；未登记 ID 返回 unknown_content，已登记但损坏则保留具体失败原因。
func read_json(logical_id: String) -> Dictionary:
	if _json.has(logical_id):
		return {"ok": true, "value": _json[logical_id].duplicate(true), "release": release_id(), "error": ""}
	for entry: Dictionary in _manifest.get("files", []):
		if entry.id != logical_id:
			continue
		if entry.kind != "json":
			return Manifest.failure("not_json")
		var path := _root.path_join(entry.path)
		var check: Dictionary = Manifest.verify_file(path, entry)
		if not check.ok:
			return check
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(path)) != OK or not (parser.data is Array or parser.data is Dictionary):
			return Manifest.failure("content_json")
		_json[logical_id] = parser.data
		return {"ok": true, "value": parser.data.duplicate(true), "release": release_id(), "error": ""}
	return Manifest.failure("unknown_content")


## 产品显式注入逐文件、整个候选目录与挂载媒体的校验合同。
func validate_all(validator: Validation = null) -> Dictionary:
	if validator != null:
		_validator = validator
	else:
		validator = _validator
	var original_cache: Dictionary = _json.duplicate()
	for entry: Dictionary in _manifest.get("files", []):
		if entry.kind != "json":
			continue
		var already_cached := _json.has(entry.id)
		var result := read_json(entry.id)
		if not result.ok:
			_json = original_cache
			return result
		if validator != null:
			var checked := validator.check_file(entry.id, result.value)
			if not checked.get("ok", false):
				_json = original_cache
				return checked
		# 发行校验逐文件进行，不能为了校验把全部题库长期展开成 Variant 数组。
		if not already_cached:
			_json.erase(entry.id)
	# 完成或失败都恢复原缓存；验证不改变长期驻留的题库集合。
	var checked: Dictionary = validator.check_catalog(self) if validator != null else {"ok": true, "error": ""}
	_json = original_cache
	return checked
