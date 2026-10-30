## 调试命令面板：管理页签和输入框，将执行请求交给 CheatBus。
class_name CheatPanel
extends Control

const _TAB_BTN_FONT_SIZE: int = 48

var _tab_inputs: Dictionary = {}

var _cur_tab_title: String = ""

var _last_tab_title: String = ""

@onready var _tab_container: TabContainer = $PanelContainer/Margin/VBox/TabContainer
@onready var _tab_scroll: ScrollContainer = $PanelContainer/Margin/VBox/TabScroll
@onready var _tab_row: HBoxContainer = $PanelContainer/Margin/VBox/TabScroll/TabRow
@onready var _cmd_input: LineEdit = $PanelContainer/Margin/VBox/InputRow/CmdInput
@onready var _run_btn: Button = $PanelContainer/Margin/VBox/InputRow/RunBtn
@onready var _close_btn: Button = $PanelContainer/Margin/VBox/TitleRow/CloseBtn


func _ready() -> void:
	visible = false
	_run_btn.pressed.connect(_on_run_pressed)

	_close_btn.pressed.connect(close_panel)

	ScrollDragHelper.attach(_tab_scroll)


func open_panel() -> void:
	_rebuild_tabs()
	visible = true


func close_panel() -> void:
	_stash_input()
	visible = false


func toggle() -> void:
	if visible:
		close_panel()
	else:
		open_panel()


## 保存当前输入，释放旧页签节点，再从注册表重建界面并恢复上次选中的页签。
func _rebuild_tabs() -> void:
	_stash_input()
	_cur_tab_title = ""

	for child in _tab_container.get_children():
		_tab_container.remove_child(child)
		child.queue_free()

	for child in _tab_row.get_children():
		_tab_row.remove_child(child)
		child.queue_free()

	var group := ButtonGroup.new()

	var tab_btns: Array[Button] = []
	var tab_titles: Array[String] = []
	var idx: int = 0
	for tab in CheatBus.get_tabs():
		var title: String = tab["title"]
		var builder: Callable = tab["builder"]

		var page := Control.new()
		page.name = title
		var scroll := ScrollContainer.new()
		scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		page.add_child(scroll)
		_tab_container.add_child(page)

		builder.call(scroll, self)

		var btn := Button.new()
		btn.text = title
		btn.toggle_mode = true
		btn.button_group = group
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", _TAB_BTN_FONT_SIZE)
		var captured_idx: int = idx
		var captured_title: String = title
		btn.pressed.connect(func() -> void: _switch_tab(captured_idx, captured_title))
		_tab_row.add_child(btn)
		tab_btns.append(btn)
		tab_titles.append(title)
		idx += 1

	if tab_titles.is_empty():
		_cmd_input.text = ""
		return
	var sel: int = tab_titles.find(_last_tab_title)
	if sel < 0:
		sel = 0
	tab_btns[sel].button_pressed = true
	_tab_container.current_tab = sel
	_cur_tab_title = tab_titles[sel]
	_last_tab_title = _cur_tab_title
	_cmd_input.text = _tab_inputs.get(_cur_tab_title, "")
	_scroll_tab_into_view(tab_btns[sel])


func _scroll_tab_into_view(btn: Button) -> void:
	await get_tree().process_frame

	if is_instance_valid(btn) and btn.is_inside_tree():
		_tab_scroll.ensure_control_visible(btn)


func fill_input(text: String) -> void:
	_cmd_input.text = text
	_stash_input()


func _switch_tab(idx: int, title: String) -> void:
	_stash_input()
	_tab_container.current_tab = idx
	_cur_tab_title = title
	_last_tab_title = title
	_cmd_input.text = _tab_inputs.get(title, "")


func _stash_input() -> void:
	if not _cur_tab_title.is_empty():
		_tab_inputs[_cur_tab_title] = _cmd_input.text


## 忽略空输入，将命令交给总线后立即关闭面板。
func _on_run_pressed() -> void:
	var raw := _cmd_input.text.strip_edges()
	if raw.is_empty():
		return
	CheatBus.issue(raw)
	close_panel()
