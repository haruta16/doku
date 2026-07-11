@tool
class_name UICodeGenerator
extends EditorPlugin

var _context_menu_plugin: UIBindContextMenu = null


func _enter_tree() -> void:
	add_tool_menu_item("Generate UI Code", _on_generate)
	_context_menu_plugin = UIBindContextMenu.new()
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_SCENE_TREE, _context_menu_plugin)


func _exit_tree() -> void:
	remove_tool_menu_item("Generate UI Code")
	if _context_menu_plugin != null:
		remove_context_menu_plugin(_context_menu_plugin)
		_context_menu_plugin = null


const _REGION_AUTO_BIND_START := "# ------ Auto bind region start ------"
const _REGION_AUTO_BIND_END := "# ------ Auto bind region end ------"
const _REGION_USER_VAR_START := "# ------ User variable region start ------"
const _REGION_USER_VAR_END := "# ------ User variable region end ------"
const _REGION_USER_CODE_START := "# ------ User code region start ------"
const _REGION_USER_CODE_END := "# ------ User code region end ------"


func _on_generate() -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		push_warning("[UICodeGen] No scene open")
		return
	generate(root)


static func generate(root: Node, extra_bindings: Array = []) -> Error:
	if root == null:
		push_warning("[UICodeGen] generate(): root is null")
		return ERR_INVALID_PARAMETER
	var scene_path: String = root.scene_file_path
	if scene_path.is_empty():
		push_warning(
			"[UICodeGen] generate(): scene_file_path empty (forgot to set it before calling?)"
		)
		return ERR_INVALID_PARAMETER
	var gd_path := _resolve_output_path(scene_path)
	var user_var_content := ""
	var user_code_content := ""
	if FileAccess.file_exists(gd_path):
		var existing := FileAccess.get_file_as_string(gd_path)
		user_var_content = _extract_region(existing, _REGION_USER_VAR_START, _REGION_USER_VAR_END)
		user_code_content = _extract_region(
			existing, _REGION_USER_CODE_START, _REGION_USER_CODE_END
		)
		if (
			user_var_content.is_empty()
			and user_code_content.is_empty()
			and existing.find(_REGION_AUTO_BIND_START) < 0
		):
			push_warning(
				(
					"[UICodeGen] File exists but has no region markers. Refusing to overwrite: %s"
					% gd_path
				)
			)
			return ERR_ALREADY_EXISTS
	var code := _generate_code(
		root, scene_path, user_var_content, user_code_content, extra_bindings
	)
	DirAccess.make_dir_recursive_absolute(gd_path.get_base_dir())
	var f := FileAccess.open(gd_path, FileAccess.WRITE)
	if f == null:
		push_warning("[UICodeGen] Failed to open for write: %s" % gd_path)
		return ERR_FILE_CANT_WRITE
	f.store_string(code)
	f.close()
	_attach_script_to_root(root, gd_path)
	_register_in_ui_framework(scene_path)
	print("[UICodeGen] Generated: %s" % gd_path)
	return OK


static func _attach_script_to_root(root: Node, gd_path: String) -> void:
	var script: Script = load(gd_path)
	if script == null:
		push_warning("[UICodeGen] Failed to load script: %s" % gd_path)
		return
	root.set_script(script)
	var scene_path: String = root.scene_file_path
	if not scene_path.is_empty():
		var packed := PackedScene.new()
		packed.pack(root)
		ResourceSaver.save(packed, scene_path)


static func _extract_region(content: String, start_label: String, end_label: String) -> String:
	var start_idx := content.find(start_label)
	var end_idx := content.find(end_label)
	if start_idx < 0 or end_idx < 0 or end_idx <= start_idx:
		return ""
	var from := start_idx + start_label.length()
	if from < content.length() and content[from] == "\n":
		from += 1
	return content.substr(from, end_idx - from)


static func _resolve_output_path(scene_path: String) -> String:
	return scene_path.replace("/ui/", "/view/").replace(".tscn", ".gd")


static func _generate_code(
	root: Node,
	scene_path: String,
	user_var_content: String = "",
	user_code_content: String = "",
	extra_bindings: Array = []
) -> String:
	var file_name := scene_path.get_file().replace(".tscn", "")
	var is_cell := file_name.ends_with("_cell")
	var base_class := "UIChildWindow" if is_cell else "UIFrameWindow"
	var ui_name := file_name.replace("_page", "").replace("_dialog", "")
	var lines: PackedStringArray = []
	lines.append("extends %s" % base_class)
	lines.append("")
	if not is_cell:
		lines.append('const SCENE_PATH := "%s"' % scene_path)
		lines.append('const UI_NAME := "%s"' % ui_name)
		lines.append("")

	lines.append(_REGION_AUTO_BIND_START)
	var bound_names := {}
	for child in root.get_children():
		var type_name := child.get_class()
		var var_name := _to_snake_case(child.name)
		var path := "$%s" % child.name
		lines.append("@onready var _%s: %s = %s" % [var_name, type_name, path])
		bound_names[var_name] = true

	for entry in extra_bindings:
		var ev_name: String = String(entry.get("name", ""))
		var ev_type: String = String(entry.get("type", ""))
		var ev_path: String = String(entry.get("path", ""))
		if ev_name.is_empty() or ev_type.is_empty() or ev_path.is_empty():
			continue
		if bound_names.has(ev_name):
			push_warning(
				(
					"[UICodeGen] @outlet '%s' (var '_%s') 被丢弃 — 该变量名已被其它节点占用,请在 figma 重命名该节点或避免多个同名节点同时打 @outlet"
					% [ev_path, ev_name]
				)
			)
			continue
		lines.append("@onready var _%s: %s = %s" % [ev_name, ev_type, ev_path])
		bound_names[ev_name] = true
	lines.append(_REGION_AUTO_BIND_END)
	lines.append("")

	lines.append(_REGION_USER_VAR_START)
	if not user_var_content.is_empty():
		lines.append(user_var_content.rstrip("\n"))
	lines.append(_REGION_USER_VAR_END)
	lines.append("")
	lines.append("")

	lines.append(_REGION_USER_CODE_START)
	if not user_code_content.is_empty():
		lines.append(user_code_content.rstrip("\n"))
	else:
		lines.append("func on_create() -> void:")
		lines.append("\tpass  #TODO: one-time init")
		lines.append("")
		lines.append("")
		lines.append("func on_show(params: Dictionary = {}) -> void:")
		lines.append("\tpass  #TODO: implement")
		lines.append("")
		lines.append("")
		lines.append("func on_hide() -> void:")
		lines.append("\tpass  #TODO: implement")
		lines.append("")
		lines.append("")
		lines.append("func on_destroy() -> void:")
		lines.append("\tpass  #TODO: cleanup")
		for child in root.find_children("*", "BaseButton", true, false):
			var cb_name := "_on_%s_pressed" % _to_snake_case(child.name)
			lines.append("")
			lines.append("")
			lines.append("func %s() -> void:" % cb_name)
			lines.append("\tpass  #TODO: implement")
	lines.append(_REGION_USER_CODE_END)
	lines.append("")
	return "\n".join(lines)


static func _register_in_ui_framework(scene_path: String) -> void:
	var file_name := scene_path.get_file().replace(".tscn", "")
	if file_name.ends_with("_cell"):
		return
	var snake_name := file_name.replace("_page", "").replace("_dialog", "")
	var const_name := snake_name.to_upper()
	_ensure_ui_name_const("res://scripts/module/ui/ui_name.gd", const_name, snake_name)
	_ensure_registry_entry("res://scripts/module/ui/ui_registry.gd", const_name, scene_path)


static func _ensure_ui_name_const(path: String, const_name: String, value: String) -> void:
	if not FileAccess.file_exists(path):
		push_warning("[UICodeGen] ui_name.gd not found at %s, skip const registration" % path)
		return
	var content := FileAccess.get_file_as_string(path)

	if content.find("\nconst %s:" % const_name) >= 0:
		return
	var section_marker := "# ── 正式页面 ──"
	var section_idx := content.find(section_marker)
	var insert_point: int
	if section_idx < 0:
		insert_point = content.length()
	else:
		var search_from := section_idx + section_marker.length()
		var next_section_idx := content.find("\n# ── ", search_from)
		insert_point = next_section_idx if next_section_idx >= 0 else content.length()
	var entry := 'const %s: StringName = &"%s"\n' % [const_name, value]
	content = content.substr(0, insert_point) + entry + content.substr(insert_point)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("[UICodeGen] Failed to open ui_name.gd for write")
		return
	f.store_string(content)
	f.close()
	print('[UICodeGen] Added UiName.%s = &"%s" to ui_name.gd' % [const_name, value])


static func _ensure_registry_entry(path: String, const_name: String, scene_path: String) -> void:
	if not FileAccess.file_exists(path):
		push_warning("[UICodeGen] ui_registry.gd not found at %s, skip registration" % path)
		return
	var content := FileAccess.get_file_as_string(path)
	if content.find("UiName.%s:" % const_name) >= 0:
		return
	var entry := '\tUiName.%s: "%s",' % [const_name, scene_path]
	var brace_idx := content.find("\n}")
	if brace_idx < 0:
		push_warning("[UICodeGen] ui_registry.gd PAGES closing brace not found")
		return
	content = content.substr(0, brace_idx) + "\n" + entry + content.substr(brace_idx)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("[UICodeGen] Failed to open ui_registry.gd for write")
		return
	f.store_string(content)
	f.close()
	print("[UICodeGen] Registered UiName.%s in PAGES (%s)" % [const_name, scene_path])


static func _to_snake_case(pascal: String) -> String:
	var result := ""
	for i in pascal.length():
		var c := pascal[i]
		var is_ascii_upper := c >= "A" and c <= "Z"
		if is_ascii_upper and i > 0 and pascal[i - 1] != "_":
			result += "_"
		result += c.to_lower()
	return result


class UIBindContextMenu:
	extends EditorContextMenuPlugin

	func _to_snake(pascal: String) -> String:
		var result := ""
		for i in pascal.length():
			var c := pascal[i]
			if c == c.to_upper() and i > 0 and pascal[i - 1] != "_":
				result += "_"
			result += c.to_lower()
		return result

	func _popup_menu(paths: PackedStringArray) -> void:
		var editor := EditorInterface
		var root := editor.get_edited_scene_root()
		if root == null:
			return
		var selection := editor.get_selection()
		var selected := selection.get_selected_nodes()
		if selected.is_empty():
			return

		var has_root := false
		for node in selected:
			if node == root:
				has_root = true
				break
		if has_root:
			add_context_menu_item("生成UI代码", _on_generate)

		add_context_menu_item("绿字绑定", _on_bind)

		if _has_bound_nodes(root, selected):
			add_context_menu_item("取消绿字", _on_unbind)

	func _on_generate(paths: PackedStringArray) -> void:
		var root := EditorInterface.get_edited_scene_root()
		if root == null:
			push_warning("[UICodeGen] No scene open")
			return
		UICodeGenerator.generate(root)

	func _on_bind(paths: PackedStringArray) -> void:
		var editor := EditorInterface
		var root := editor.get_edited_scene_root()
		if root == null:
			push_warning("[绿字] No scene open")
			return
		var script: Script = root.get_script()
		if script == null:
			push_warning("[绿字] Scene root has no script attached")
			return
		var script_path: String = script.resource_path
		if script_path.is_empty():
			push_warning("[绿字] Script has no file path")
			return
		var selection := editor.get_selection()
		var selected_nodes := selection.get_selected_nodes()
		if selected_nodes.is_empty():
			push_warning("[绿字] No nodes selected")
			return
		var content := FileAccess.get_file_as_string(script_path)
		var new_lines: PackedStringArray = []
		for node: Node in selected_nodes:
			if node == root:
				continue
			var rel_path: String = str(root.get_path_to(node))
			var type_name: String = node.get_class()
			var var_name: String = _to_snake(node.name)
			var line := "@onready var _%s: %s = $%s" % [var_name, type_name, rel_path]
			if content.find(line) >= 0:
				continue
			if content.find("_%s" % var_name) >= 0:
				push_warning("[绿字] Variable '_%s' already exists in script, skipping" % var_name)
				continue
			new_lines.append(line)
		if new_lines.is_empty():
			print("[绿字] All selected nodes already bound")
			return
		var insert_pos := _find_onready_insert_position(content)
		if insert_pos < 0:
			push_warning("[绿字] Script has no Auto bind region, please run 'Generate UI Code' first")
			return
		var before := content.substr(0, insert_pos)
		var after := content.substr(insert_pos)
		var insert_text := "\n".join(new_lines) + "\n"
		content = before + insert_text + after
		var f := FileAccess.open(script_path, FileAccess.WRITE)
		f.store_string(content)
		f.close()
		print("[绿字] Added %d binding(s) to %s:" % [new_lines.size(), script_path])
		for line in new_lines:
			print("  %s" % line)

	func _find_onready_insert_position(content: String) -> int:
		var region_end_pos := content.find("# ------ Auto bind region end ------")
		if region_end_pos >= 0:
			return region_end_pos
		return -1

	func _has_bound_nodes(root: Node, selected_nodes: Array[Node]) -> bool:
		var script: Script = root.get_script()
		if script == null:
			return false
		var script_path: String = script.resource_path
		if script_path.is_empty():
			return false
		var content := FileAccess.get_file_as_string(script_path)
		for node: Node in selected_nodes:
			if node == root:
				continue
			var var_name: String = _to_snake(node.name)
			if content.find("var _%s:" % var_name) >= 0:
				return true
		return false

	func _on_unbind(paths: PackedStringArray) -> void:
		var editor := EditorInterface
		var root := editor.get_edited_scene_root()
		if root == null:
			push_warning("[取消绿字] No scene open")
			return
		var script: Script = root.get_script()
		if script == null:
			push_warning("[取消绿字] Scene root has no script attached")
			return
		var script_path: String = script.resource_path
		if script_path.is_empty():
			push_warning("[取消绿字] Script has no file path")
			return
		var selection := editor.get_selection()
		var selected_nodes := selection.get_selected_nodes()
		if selected_nodes.is_empty():
			push_warning("[取消绿字] No nodes selected")
			return
		var content := FileAccess.get_file_as_string(script_path)
		var lines := content.split("\n")
		var removed: PackedStringArray = []
		for node: Node in selected_nodes:
			if node == root:
				continue
			var var_name: String = _to_snake(node.name)
			var pattern := "var _%s:" % var_name
			var new_lines: PackedStringArray = []
			for line in lines:
				if line.find(pattern) >= 0:
					removed.append(line.strip_edges())
				else:
					new_lines.append(line)
			lines = new_lines
		if removed.is_empty():
			print("[取消绿字] No bindings found for selected nodes")
			return
		var f := FileAccess.open(script_path, FileAccess.WRITE)
		f.store_string("\n".join(lines))
		f.close()
		print("[取消绿字] Removed %d binding(s) from %s:" % [removed.size(), script_path])
		for line in removed:
			print("  %s" % line)
