## 仅替换登记的表现资源。场景结构与脚本仍随客户端发布；原资源始终保留为回退。
class_name ContentSceneBindings
extends RefCounted

const PROPERTIES: Array[String] = ["texture", "icon", "texture_normal", "texture_pressed", "texture_hover", "texture_disabled", "skeleton_data_res"]
const ORIGINALS: StringName = &"_content_binding_originals"
static var _bindings: Dictionary = {}
static var _loaded: bool = false
static var _spine_checks: Dictionary = {}


static func registry() -> Dictionary:
	if not _loaded:
		_loaded = true
		var path: String = str(ProjectSettings.get_setting("content/scene_bindings_path", ""))
		if not path.is_empty():
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary and typeof(parsed.get("schema")) in [TYPE_INT, TYPE_FLOAT] and parsed.schema == 1 and parsed.get("resources") is Dictionary:
				for resource_path: Variant in parsed.resources:
					var binding: Variant = parsed.resources[resource_path]
					if resource_path is String and resource_path.begins_with("res://") and binding is Dictionary and binding.get("kind") in ["textures", "spine"] and binding.get("slot") is String and ContentManifest.safe_relative_path(binding.slot):
						_bindings[resource_path] = binding.duplicate(true)
	return _bindings.duplicate(true)


## 可在入树前调用；关卡复用窗口时传入新的 overrides，会从原资源重新解析。
static func apply(root: Node, overrides: Dictionary = {}) -> void:
	var bindings: Dictionary = registry()
	if bindings.is_empty() or root == null:
		return
	_apply_tree(root, bindings, overrides)


static func _apply_tree(node: Node, bindings: Dictionary, overrides: Dictionary) -> void:
	var originals: Dictionary = node.get_meta(ORIGINALS, {})
	for property: Dictionary in node.get_property_list():
		var name: String = str(property.name)
		if name not in PROPERTIES:
			continue
		var original: Resource = originals.get(name) as Resource
		if original == null:
			original = node.get(name) as Resource
		if original == null or not bindings.has(original.resource_path):
			continue
		originals[name] = original
		var binding: Dictionary = bindings[original.resource_path]
		var slot: String = str(overrides.get(binding.slot, binding.slot))
		var replacement: Resource = original
		match binding.kind:
			"textures":
				replacement = ContentContext.load_texture(slot, original as Texture2D)
				if not texture_compatible(original as Texture2D, replacement as Texture2D):
					ContentContext.report_content_error("media/" + slot, "texture_binding_dimensions")
					replacement = original
			"spine":
				replacement = ContentContext.load_spine(slot, original)
				if not spine_compatible(original, replacement):
					ContentContext.report_content_error("media/" + slot, "spine_binding_contract")
					replacement = original
		if node.get(name) != replacement:
			node.set(name, replacement)
	if not originals.is_empty():
		node.set_meta(ORIGINALS, originals)
	for child: Node in node.get_children():
		_apply_tree(child, bindings, overrides)


## 既有 NinePatch 的裁剪、边距和布局使用像素值，固定场景槽位保留原像素尺寸。
static func texture_compatible(original: Texture2D, replacement: Texture2D) -> bool:
	return original != null and replacement != null and original.get_size() == replacement.get_size()


## 既有轨道和换肤代码依赖名称；新资源至少要保留原动画与皮肤集合。
static func spine_compatible(original: Resource, replacement: Resource) -> bool:
	if original == replacement:
		return true
	if original == null or replacement == null or replacement.get_class() != "SpineSkeletonDataResource":
		return false
	var key: String = "%s|%s" % [original.get_instance_id(), replacement.get_instance_id()]
	if _spine_checks.has(key):
		return _spine_checks[key]
	var valid: bool = original.has_method("get_animations") and replacement.has_method("find_animation")
	if valid:
		for animation: Object in original.call("get_animations"):
			if replacement.call("find_animation", animation.call("get_name")) == null:
				valid = false
				break
	if valid:
		for skin: Object in original.call("get_skins"):
			if replacement.call("find_skin", skin.call("get_name")) == null:
				valid = false
				break
	_spine_checks[key] = valid
	return valid


static func validate_media(catalog: RefCounted, overrides: Dictionary = {}) -> Dictionary:
	var mapping: Dictionary = catalog.read_json("media")
	if not mapping.get("ok", false):
		return {"ok": true} if mapping.get("error") == "unknown_content" and overrides.is_empty() else {"ok": false, "error": "binding_media_missing"}
	for path: String in registry():
		var binding: Dictionary = _bindings[path]
		var slot: String = str(overrides.get(binding.slot, binding.slot))
		var relative: String = str(mapping.value.get(binding.kind, {}).get(slot, ""))
		if relative.is_empty():
			if overrides.has(binding.slot):
				return {"ok": false, "error": "binding_slot_missing:" + slot}
			continue
		if binding.kind == "textures":
			var loaded: Dictionary = catalog.load_image(relative)
			if not loaded.get("ok", false):
				return loaded
			var original: Texture2D = load(path) as Texture2D
			if original == null or Vector2i(original.get_size()) != loaded.value.get_size():
				return {"ok": false, "error": "texture_binding_dimensions:" + slot}
		elif binding.kind == "spine":
			var loaded: Dictionary = catalog.load_spine(relative)
			if not loaded.get("ok", false):
				return loaded
			if not spine_compatible(load(path), loaded.value):
				return {"ok": false, "error": "spine_binding_contract:" + slot}
	return {"ok": true}
