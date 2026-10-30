## 调试页签基类：按命令分类构建搜索列表，统一按钮生成与游戏页查找。
class_name CheatTabBase
extends RefCounted


func title() -> String:
	return ""


func owned_tab() -> int:
	return -1


func claim_commands() -> Array[CheatCommand]:
	var owned: int = owned_tab()
	if owned < 0:
		return []
	var out: Array[CheatCommand] = []
	for cmd: CheatCommand in CheatBus.get_commands():
		if cmd.tab == owned:
			out.append(cmd)
	return out


func build(_content: ScrollContainer, _panel: CheatPanel) -> void:
	pass


func _add_search_header(content: ScrollContainer, placeholder: String) -> LineEdit:
	const SEARCH_H: float = 96.0
	var page: Control = content.get_parent()
	var header := HBoxContainer.new()
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.offset_bottom = SEARCH_H
	header.add_theme_constant_override("separation", 12)
	page.add_child(header)

	var search := LineEdit.new()
	search.placeholder_text = placeholder
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.size_flags_vertical = Control.SIZE_EXPAND_FILL
	search.add_theme_font_size_override("font_size", 42)
	header.add_child(search)

	var clear_btn := Button.new()
	clear_btn.text = "x"
	clear_btn.custom_minimum_size = Vector2(110, 0)
	clear_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	clear_btn.add_theme_font_size_override("font_size", 54)
	header.add_child(clear_btn)
	clear_btn.pressed.connect(
		func() -> void:
			search.text = ""
			search.text_changed.emit("")
	)

	content.offset_top = SEARCH_H
	return search


func _build_flow_with_search(
	content: ScrollContainer, panel: CheatPanel, placeholder: String
) -> void:
	ScrollDragHelper.attach(content)
	var search := _add_search_header(content, placeholder)
	var flow := _make_cmd_flow()
	content.add_child(flow)

	var searchable: Array = []
	for cmd: CheatCommand in claim_commands():
		var btn := _add_cmd_button(flow, cmd, panel)
		searchable.append({"btn": btn, "text": (cmd.name + " " + cmd.label).to_lower()})

	search.text_changed.connect(
		func(q: String) -> void:
			var needle: String = q.strip_edges().to_lower()
			for item: Dictionary in searchable:
				item.btn.visible = needle.is_empty() or needle in item.text
	)


func _make_cmd_flow() -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 16)
	flow.add_theme_constant_override("v_separation", 16)
	return flow


func _add_cmd_button(flow: HFlowContainer, cmd: CheatCommand, panel: CheatPanel) -> Button:
	const MAX_BTN_WIDTH: float = 600.0
	var btn := Button.new()
	btn.text = cmd.label if cmd.label != "" else cmd.name
	btn.custom_minimum_size = Vector2(0, 100)
	btn.add_theme_font_size_override("font_size", 48)
	var captured_cmd: CheatCommand = cmd
	btn.pressed.connect(
		func() -> void:
			var raw: String = captured_cmd.name
			if captured_cmd.default_args != "":
				raw += " " + captured_cmd.default_args
			panel.fill_input(raw)
	)
	flow.add_child(btn)
	var natural_w: float = btn.get_minimum_size().x
	if natural_w > MAX_BTN_WIDTH:
		btn.clip_text = true
		btn.custom_minimum_size = Vector2(MAX_BTN_WIDTH, 100)
	else:
		btn.custom_minimum_size = Vector2(natural_w + 30, 100)
	return btn


static func get_active_game_page() -> Node:
	for page_name in ["game", "daily_game"]:
		var p: Node = UIManager.get_ui(page_name)
		if p != null and p is CanvasItem and (p as CanvasItem).visible:
			return p
	return null
