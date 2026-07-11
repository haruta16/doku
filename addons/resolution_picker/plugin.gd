@tool
extends EditorPlugin

const RESOLUTIONS: Array[Dictionary] = [
	{"label": "1080×2400 (20:9 设计基准)", "w": 1080, "h": 2400},
	{"label": "1080×1920 (16:9)", "w": 1080, "h": 1920},
	{"label": "1080×2340 (19.5:9)", "w": 1080, "h": 2340},
	{"label": "1080×2160 (18:9)", "w": 1080, "h": 2160},
	{"label": "1284×2778 (iPhone 14 Pro Max)", "w": 1284, "h": 2778},
	{"label": "1170×2532 (iPhone 14 Pro)", "w": 1170, "h": 2532},
	{"label": "828×1792 (iPhone XR)", "w": 828, "h": 1792},
	{"label": "720×1280 (低端机)", "w": 720, "h": 1280},
	{"label": "1080×2640 (21:9 长屏)", "w": 1080, "h": 2640},
]

const CUSTOM_SAVE_PATH := "user://resolution_picker_custom.cfg"
const ID_SEPARATOR := 900
const ID_CUSTOM_INPUT := 999

var _picker: OptionButton
var _menu: PopupMenu
var _custom_dialog: AcceptDialog
var _width_input: SpinBox
var _height_input: SpinBox
var _custom_resolutions: Array[Dictionary] = []
var _picker_item_count: int = 0
var _ignore_picker_signal: bool = false


func _enter_tree() -> void:
	_load_custom_resolutions()

	if _picker != null:
		remove_control_from_container(EditorPlugin.CONTAINER_TOOLBAR, _picker)
		_picker.queue_free()
		_picker = null

	_picker = OptionButton.new()
	_picker.flat = true
	_picker.custom_minimum_size.x = 260
	_picker.tooltip_text = "切换运行分辨率（Play 生效）"
	_picker.item_selected.connect(_on_picker_selected)
	_rebuild_picker()
	add_control_to_container(EditorPlugin.CONTAINER_TOOLBAR, _picker)

	_menu = PopupMenu.new()
	_rebuild_menu()
	_menu.id_pressed.connect(_on_menu_pressed)
	add_tool_submenu_item("Resolution", _menu)

	_build_custom_dialog()


func _exit_tree() -> void:
	if _picker != null:
		remove_control_from_container(EditorPlugin.CONTAINER_TOOLBAR, _picker)
		_picker.queue_free()
		_picker = null
	if _menu != null:
		remove_tool_menu_item("Resolution")
		_menu = null
	if _custom_dialog != null:
		_custom_dialog.queue_free()
		_custom_dialog = null


func _rebuild_picker() -> void:
	_ignore_picker_signal = true
	_picker.clear()
	var cur_w: int = ProjectSettings.get_setting("display/window/size/window_width_override", 0)
	var cur_h: int = ProjectSettings.get_setting("display/window/size/window_height_override", 0)
	var selected_idx: int = 0

	for i in range(RESOLUTIONS.size()):
		var r: Dictionary = RESOLUTIONS[i]
		_picker.add_item(r["label"])
		if r["w"] == cur_w and r["h"] == cur_h:
			selected_idx = i

	if not _custom_resolutions.is_empty():
		_picker.add_separator("── 自定义 ──")
		for i in range(_custom_resolutions.size()):
			var r: Dictionary = _custom_resolutions[i]
			var idx: int = _picker.get_item_count()
			_picker.add_item(r["label"])
			if r["w"] == cur_w and r["h"] == cur_h:
				selected_idx = idx

	_picker.add_separator("")
	_picker.add_item("➕ 添加自定义...")
	_picker_item_count = _picker.get_item_count()

	_picker.selected = selected_idx
	_ignore_picker_signal = false


func _on_picker_selected(idx: int) -> void:
	if _ignore_picker_signal:
		return

	if idx == _picker_item_count - 1:
		_show_custom_dialog()

		_sync_picker_selection()
		return

	var text: String = _picker.get_item_text(idx)
	if text.begins_with("──") or text.is_empty():
		_sync_picker_selection()
		return

	var res: Dictionary = _find_resolution_by_label(text)
	if not res.is_empty():
		_apply_resolution(res["w"], res["h"])


func _sync_picker_selection() -> void:
	_ignore_picker_signal = true
	var cur_w: int = ProjectSettings.get_setting("display/window/size/window_width_override", 0)
	var cur_h: int = ProjectSettings.get_setting("display/window/size/window_height_override", 0)
	for i in range(_picker.get_item_count()):
		var r: Dictionary = _find_resolution_by_label(_picker.get_item_text(i))
		if not r.is_empty() and r["w"] == cur_w and r["h"] == cur_h:
			_picker.selected = i
			break
	_ignore_picker_signal = false


func _rebuild_menu() -> void:
	_menu.clear()
	var cur_w: int = ProjectSettings.get_setting("display/window/size/window_width_override", 0)
	var cur_h: int = ProjectSettings.get_setting("display/window/size/window_height_override", 0)

	for i in range(RESOLUTIONS.size()):
		var r: Dictionary = RESOLUTIONS[i]
		_menu.add_radio_check_item(r["label"], i)
		if r["w"] == cur_w and r["h"] == cur_h:
			_menu.set_item_checked(_menu.get_item_index(i), true)

	if not _custom_resolutions.is_empty():
		_menu.add_separator("── 自定义 ──")
		for i in range(_custom_resolutions.size()):
			var r: Dictionary = _custom_resolutions[i]
			var id: int = ID_SEPARATOR + i
			_menu.add_radio_check_item(r["label"], id)
			if r["w"] == cur_w and r["h"] == cur_h:
				_menu.set_item_checked(_menu.get_item_index(id), true)

	_menu.add_separator("")
	_menu.add_item("➕ 添加自定义分辨率...", ID_CUSTOM_INPUT)


func _on_menu_pressed(id: int) -> void:
	if id == ID_CUSTOM_INPUT:
		_show_custom_dialog()
		return
	var res: Dictionary
	if id < ID_SEPARATOR:
		if id >= 0 and id < RESOLUTIONS.size():
			res = RESOLUTIONS[id]
	else:
		var custom_idx: int = id - ID_SEPARATOR
		if custom_idx >= 0 and custom_idx < _custom_resolutions.size():
			res = _custom_resolutions[custom_idx]
	if not res.is_empty():
		_apply_resolution(res["w"], res["h"])


func _apply_resolution(w: int, h: int) -> void:
	ProjectSettings.set_setting("display/window/size/window_width_override", w)
	ProjectSettings.set_setting("display/window/size/window_height_override", h)
	ProjectSettings.save()
	_rebuild_picker()
	_rebuild_menu()
	print("[ResolutionPicker] Override → %d×%d — Play 即生效" % [w, h])


func _find_resolution_by_label(label: String) -> Dictionary:
	for r in RESOLUTIONS:
		if r["label"] == label:
			return r
	for r in _custom_resolutions:
		if r["label"] == label:
			return r
	return {}


func _build_custom_dialog() -> void:
	_custom_dialog = AcceptDialog.new()
	_custom_dialog.title = "添加自定义分辨率"
	_custom_dialog.ok_button_text = "保存并应用"
	_custom_dialog.confirmed.connect(_on_custom_confirmed)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(300, 0)

	var w_hbox := HBoxContainer.new()
	var w_label := Label.new()
	w_label.text = "Width:"
	w_label.custom_minimum_size.x = 60
	_width_input = SpinBox.new()
	_width_input.min_value = 320
	_width_input.max_value = 4096
	_width_input.value = 1080
	_width_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	w_hbox.add_child(w_label)
	w_hbox.add_child(_width_input)
	vbox.add_child(w_hbox)

	var h_hbox := HBoxContainer.new()
	var h_label := Label.new()
	h_label.text = "Height:"
	h_label.custom_minimum_size.x = 60
	_height_input = SpinBox.new()
	_height_input.min_value = 480
	_height_input.max_value = 4096
	_height_input.value = 2400
	_height_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h_hbox.add_child(h_label)
	h_hbox.add_child(_height_input)
	vbox.add_child(h_hbox)

	_custom_dialog.add_child(vbox)
	EditorInterface.get_base_control().add_child(_custom_dialog)


func _show_custom_dialog() -> void:
	var cur_w: int = ProjectSettings.get_setting("display/window/size/window_width_override", 1080)
	var cur_h: int = ProjectSettings.get_setting("display/window/size/window_height_override", 2400)
	_width_input.value = cur_w
	_height_input.value = cur_h
	_custom_dialog.popup_centered()


func _on_custom_confirmed() -> void:
	var w: int = int(_width_input.value)
	var h: int = int(_height_input.value)

	for r in RESOLUTIONS:
		if r["w"] == w and r["h"] == h:
			_apply_resolution(w, h)
			return
	for r in _custom_resolutions:
		if r["w"] == w and r["h"] == h:
			_apply_resolution(w, h)
			return
	_custom_resolutions.append({"label": "%d×%d" % [w, h], "w": w, "h": h})
	_save_custom_resolutions()
	_apply_resolution(w, h)


func _save_custom_resolutions() -> void:
	var cfg := ConfigFile.new()
	for i in range(_custom_resolutions.size()):
		var r: Dictionary = _custom_resolutions[i]
		cfg.set_value("custom", "res_%d" % i, "%d,%d" % [r["w"], r["h"]])
	cfg.set_value("custom", "count", _custom_resolutions.size())
	cfg.save(CUSTOM_SAVE_PATH)


func _load_custom_resolutions() -> void:
	_custom_resolutions.clear()
	var cfg := ConfigFile.new()
	if cfg.load(CUSTOM_SAVE_PATH) != OK:
		return
	var count: int = cfg.get_value("custom", "count", 0)
	for i in range(count):
		var raw: String = cfg.get_value("custom", "res_%d" % i, "")
		if raw.is_empty():
			continue
		var parts: PackedStringArray = raw.split(",")
		if parts.size() != 2:
			continue
		var w: int = int(parts[0])
		var h: int = int(parts[1])
		if w > 0 and h > 0:
			_custom_resolutions.append({"label": "%d×%d" % [w, h], "w": w, "h": h})
