## raw_pck 包含自有目录的原始媒体；spine_pck 另允许固定 Spine 模板与经核对的导入闭包。
## 不接受全局 UID 缓存、任意资源/场景/脚本、删除或差分条目。
## 先检查包目录，再挂载；load_resource_pack 本身不是包内容安全检查器。
class_name ContentRawPack
extends RefCounted

const Manifest = preload("res://scripts/framework/content/content_manifest.gd")
static var _mounted_path: String = ""


static func inspect(path: String, product: String, release: String, profile: String = "raw_pck") -> Dictionary:
	if profile not in ["raw_pck", "spine_pck"]:
		return Manifest.failure("pack_profile")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 108:
		return Manifest.failure("pack_header")
	var length := file.get_length()
	if file.get_32() != 0x43504447 or file.get_32() != 3:
		return Manifest.failure("pack_format")
	var major := file.get_32()
	var minor := file.get_32()
	file.get_32() # patch：完整运行时指纹由清单校验。
	if major != 4 or minor > int(Engine.get_version_info().minor) or file.get_32() != 2:
		return Manifest.failure("pack_features")
	var base := file.get_64()
	var directory := file.get_64()
	if base < 104 or directory < base or directory > length - 4:
		return Manifest.failure("pack_bounds")
	file.seek(directory)
	var count := file.get_32()
	if count == 0 or count > Manifest.MAX_ENTRIES:
		return Manifest.failure("pack_count")
	var prefix := "content/%s/%s/" % [product, release]
	var entries: Array[Dictionary] = []
	var paths: Dictionary = {}
	for index in count:
		if file.get_position() > length - 4:
			return Manifest.failure("pack_directory")
		var path_bytes := file.get_32()
		if path_bytes == 0 or path_bytes > 512 or file.get_position() + path_bytes + 36 > length:
			return Manifest.failure("pack_directory")
		var raw_path := file.get_buffer(path_bytes)
		while not raw_path.is_empty() and raw_path[-1] == 0:
			raw_path.resize(raw_path.size() - 1)
		if raw_path.has(0):
			return Manifest.failure("pack_path")
		var resource_path := raw_path.get_string_from_utf8()
		var offset := file.get_64()
		var size := file.get_64()
		file.get_buffer(16) # 整包 SHA-256 由外层验证；这里不把 PCK 的 MD5 当认证。
		var flags := file.get_32()
		var namespaced := resource_path.begins_with(prefix) and Manifest.safe_relative_path(resource_path)
		var imported := profile == "spine_pck" and resource_path.begins_with(".godot/imported/") and Manifest.safe_relative_path(resource_path.trim_prefix(".godot/imported/")) and not resource_path.trim_prefix(".godot/imported/").contains("/")
		if (not namespaced and not imported) or paths.has("res://" + resource_path):
			return Manifest.failure("pack_namespace")
		var allowed_extensions: Array = Manifest.RAW_EXTENSIONS if profile == "raw_pck" else Manifest.RAW_EXTENSIONS + ["atlas", "skel", "tres", "import", "ctex", "spatlas", "spskel"]
		if resource_path.get_extension() not in allowed_extensions or flags != 0:
			return Manifest.failure("pack_resource_type")
		if offset < 0 or size <= 0 or size > Manifest.MAX_FILE_BYTES or base + offset > directory - size:
			return Manifest.failure("pack_entry_bounds")
		var entry := {"path": "res://" + resource_path, "bytes": size, "offset": base + offset}
		paths[entry.path] = entry
		entries.append(entry)
	if profile == "spine_pck":
		var checked := _validate_spine(file, paths, "res://" + prefix)
		if not checked.ok:
			return checked
	file.close()
	return {"ok": true, "value": entries, "error": ""}


## 只由冷启动入口调用。同一进程不允许切换到另一 PCK，也不假装可卸载。
static func mount_once(path: String, product: String, release: String, profile: String = "raw_pck") -> Dictionary:
	if not _mounted_path.is_empty():
		return {"ok": _mounted_path == path, "error": "" if _mounted_path == path else "pack_requires_cold_start", "restart_required": _mounted_path != path}
	var check := inspect(path, product, release, profile)
	if not check.ok:
		return check
	for entry: Dictionary in check.value:
		if FileAccess.file_exists(entry.path):
			return Manifest.failure("pack_existing_path")
	if not ProjectSettings.load_resource_pack(path, false):
		return {"ok": false, "error": "pack_mount", "restart_required": true}
	_mounted_path = path
	return {"ok": true, "value": check.value, "error": ""}


static func mounted_path() -> String:
	return _mounted_path


## spine_pck 只允许固定的 SkeletonData 模板与其导入闭包，不接受任意 .tres/.tscn。
static func _validate_spine(file: FileAccess, paths: Dictionary, prefix: String) -> Dictionary:
	var imported_references: Dictionary = {}
	var skeleton_count := 0
	var template := RegEx.new()
	template.compile('\\A\\[gd_resource type="SpineSkeletonDataResource" format=3\\]\\s*\\[ext_resource type="SpineAtlasResource" path="(res://[^"\\r\\n]+\\.atlas)" id="1"\\]\\s*\\[ext_resource type="SpineSkeletonFileResource" path="(res://[^"\\r\\n]+\\.skel)" id="2"\\]\\s*\\[resource\\]\\s*atlas_res = ExtResource\\("1"\\)\\s*skeleton_file_res = ExtResource\\("2"\\)\\s*\\z')
	for path: String in paths:
		var entry: Dictionary = paths[path]
		if path.ends_with(".tres"):
			if not path.begins_with(prefix) or entry.bytes > 4096:
				return Manifest.failure("spine_template")
			file.seek(entry.offset)
			var matched := template.search(file.get_buffer(entry.bytes).get_string_from_utf8())
			if matched == null:
				return Manifest.failure("spine_template")
			for group in [1, 2]:
				var dependency := matched.get_string(group)
				if not dependency.begins_with(prefix) or not paths.has(dependency + ".import"):
					return Manifest.failure("spine_dependency")
			skeleton_count += 1
		elif path.ends_with(".import"):
			if not path.begins_with(prefix) or entry.bytes > 16384:
				return Manifest.failure("import_metadata")
			file.seek(entry.offset)
			var text := file.get_buffer(entry.bytes).get_string_from_utf8()
			# Generated import files are primitive configuration data; reject serialized object constructors.
			if text.contains("Object(") or text.contains("Resource(") or text.contains("ExtResource(") or text.contains("SubResource("):
				return Manifest.failure("import_metadata")
			var config := ConfigFile.new()
			if config.parse(text) != OK:
				return Manifest.failure("import_metadata")
			var source := path.trim_suffix(".import")
			var extension := source.get_extension()
			var kinds := {"png": ["texture", "CompressedTexture2D", "ctex"], "atlas": ["spine.atlas", "SpineAtlasResource", "spatlas"], "skel": ["spine.skel", "SpineSkeletonFileResource", "spskel"]}
			if not kinds.has(extension):
				return Manifest.failure("import_type")
			var kind: Array = kinds[extension]
			var expected: String = "res://.godot/imported/" + source.get_file() + "-" + source.md5_text() + "." + str(kind[2])
			if config.get_value("remap", "importer", "") != kind[0] or config.get_value("remap", "type", "") != kind[1] or config.get_value("remap", "path", "") != expected:
				return Manifest.failure("import_mapping")
			# Godot's exporter may strip editor-only [deps]; identity is derived from the signed .import path.
			if config.get_value("deps", "source_file", source) != source or not paths.has(expected):
				return Manifest.failure("import_dependency")
			var destinations: Variant = config.get_value("deps", "dest_files", [expected])
			if not (destinations is Array or destinations is PackedStringArray) or destinations.size() != 1 or destinations[0] != expected:
				return Manifest.failure("import_dependency")
			var uid_text: Variant = config.get_value("remap", "uid", "")
			if not uid_text is String:
				return Manifest.failure("import_uid")
			if not uid_text.is_empty():
				var uid := ResourceUID.text_to_id(uid_text)
				if uid == ResourceUID.INVALID_ID or (ResourceUID.has_id(uid) and ResourceUID.get_id_path(uid) != source):
					return Manifest.failure("import_uid_collision")
			imported_references[expected] = true
		elif path.begins_with("res://.godot/imported/"):
			continue
		elif path.get_extension() in Manifest.RAW_EXTENSIONS:
			continue
		elif not paths.has(path + ".import"):
			return Manifest.failure("unexpected_spine_source")
	if skeleton_count == 0:
		return Manifest.failure("spine_template_missing")
	for path: String in paths:
		if path.begins_with("res://.godot/imported/") and not imported_references.has(path):
			return Manifest.failure("unreferenced_import")
	return {"ok": true, "error": ""}
