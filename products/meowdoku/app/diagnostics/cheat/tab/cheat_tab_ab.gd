## 实验调试页签：列出当前参数、提供搜索，并为指定实验值填入调试命令。
class_name CheatTabAb
extends CheatTabBase

const _PEEK_GROUPS: Array = [
	[0, "0对照"],
	[LoadingPageTestConfig.VALUE_PAW_SEGMENT_BAR, "1猫脚印"],
	[LoadingPageTestConfig.VALUE_BOX_CAT_ARROW_BAR, "2纸箱猫"],
	[LoadingPageTestConfig.VALUE_RUNNING_CAT_BAR, "3侧跑猫"],
	[LoadingPageTestConfig.VALUE_SWIMMING_FISH_NO_BAR, "4游泳鱼"],
	[LoadingPageTestConfig.VALUE_FISHBOWL_CAT_BAR, "5鱼缸猫"],
	[LoadingPageTestConfig.VALUE_CLAW_MACHINE, "6娃娃机"],
	[LoadingPageTestConfig.VALUE_TREADMILL_CAT_BAR, "7跑步机"],
	[LoadingPageTestConfig.VALUE_WEEKDAY_COMIC, "8漫画"],
	[LoadingPageTestConfig.VALUE_WEEKDAY_COMIC_TEXT, "9漫画+字"],
	[LoadingPageTestConfig.VALUE_TRUST_STATS, "10用户数"],
	[LoadingPageTestConfig.VALUE_TRUST_STATS_LIVE, "11开局数"],
]


func title() -> String:
	return "AB测"


func build(content: ScrollContainer, panel: CheatPanel) -> void:
	ScrollDragHelper.attach(content, true)
	var search := _add_search_header(content, "搜索 AB 参数(key / 名称)…")

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 16)
	content.add_child(vbox)

	var searchable: Array = []

	var params: Array = CheatBus.get_ab_params()
	params.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return a["key"].to_lower() < b["key"].to_lower()
	)
	for param in params:
		var key: String = param["key"]
		var label: String = param["label"]
		var value_fn: Callable = param["current_value_fn"]

		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 110)
		row.add_theme_constant_override("separation", 20)

		var btn := Button.new()
		var cur_val: String = value_fn.call()
		btn.text = "%s  [当前: %s]" % [label, cur_val]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 110)
		btn.add_theme_font_size_override("font_size", 46)
		btn.clip_text = true
		var captured_key: String = key
		var captured_value_fn: Callable = value_fn
		btn.pressed.connect(
			func() -> void: panel.fill_input("ab %s %s" % [captured_key, captured_value_fn.call()])
		)
		row.add_child(btn)
		vbox.add_child(row)
		searchable.append({"row": row, "text": (key + " " + label).to_lower()})

	_add_loading_peek_block(vbox, panel, searchable)

	search.text_changed.connect(
		func(q: String) -> void:
			var needle: String = q.strip_edges().to_lower()
			for item: Dictionary in searchable:
				item.row.visible = needle.is_empty() or needle in item.text
	)


func _add_loading_peek_block(vbox: VBoxContainer, panel: CheatPanel, searchable: Array) -> void:
	var cfg: LoadingPageTestConfig = ABTestManager.loading_page_test

	if cfg == null:
		return

	var block := VBoxContainer.new()
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.add_theme_constant_override("separation", 10)
	vbox.add_child(block)

	var title_lbl := Label.new()
	title_lbl.text = "── loading_page_test 落盘 peek 强设(点组 → 写入 → 自动退出)──"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.add_theme_font_size_override("font_size", 40)
	block.add_child(title_lbl)

	var status_lbl := Label.new()
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_lbl.add_theme_font_size_override("font_size", 40)
	block.add_child(status_lbl)
	_refresh_peek_status(cfg, status_lbl)

	var grid := GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	block.add_child(grid)

	var longest_quote_row := Control.new()
	longest_quote_row.custom_minimum_size = Vector2(0, 110)
	longest_quote_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	longest_quote_row.mouse_filter = Control.MOUSE_FILTER_PASS

	var longest_quote := CheckBox.new()
	longest_quote.text = ""
	longest_quote.button_pressed = GameState.is_loading_page_test_force_longest_quote()
	longest_quote.custom_minimum_size = Vector2(27, 27)
	longest_quote.size = Vector2(27, 27)
	longest_quote.position = Vector2(0, 15)
	longest_quote.pivot_offset = Vector2.ZERO
	longest_quote.scale = Vector2(3, 3)

	var unchecked_in_checked_color := _make_checked_color_unchecked_icon(longest_quote)
	if unchecked_in_checked_color != null:
		longest_quote.add_theme_icon_override(&"unchecked", unchecked_in_checked_color)
	longest_quote_row.add_child(longest_quote)

	var longest_quote_label := Label.new()
	longest_quote_label.text = "最长名言"
	longest_quote_label.position = Vector2(100, 0)
	longest_quote_label.size = Vector2(680, 110)
	longest_quote_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	longest_quote_label.add_theme_font_size_override("font_size", 40)
	longest_quote_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	longest_quote_row.add_child(longest_quote_label)

	for entry: Array in _PEEK_GROUPS:
		var captured_value: int = int(entry[0])
		var btn := Button.new()
		btn.text = str(entry[1])
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 100)
		btn.add_theme_font_size_override("font_size", 40)
		grid.add_child(btn)

		btn.pressed.connect(
			func() -> void:
				if not cfg.clear_debug_override():
					status_lbl.text = "本地覆盖清除失败，未强设、未退出"
					return
				GameState.set_loading_page_test_peek_override(
					cfg.key, captured_value, longest_quote.button_pressed
				)
				print(
					(
						"[Cheat] loading_page_test 落盘 peek = %d,最长名言强制 = %s,退出游戏;下次冷启动 splash 生效(仅此一次)"
						% [
							captured_value,
							str(longest_quote.button_pressed),
						]
					)
				)
				panel.get_tree().quit()
		)

	block.add_child(longest_quote_row)

	var restore := Button.new()
	restore.text = "恢复 SDK 真值并退出"
	restore.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	restore.custom_minimum_size = Vector2(0, 100)
	restore.add_theme_font_size_override("font_size", 40)
	block.add_child(restore)
	restore.pressed.connect(
		func() -> void:
			if not cfg.clear_debug_override():
				status_lbl.text = "本地覆盖清除失败，未恢复、未退出"
				return
			GameState.clear_loading_page_test_force_longest_quote()
			if not ABTestManager.is_ab_init_done():
				status_lbl.text = "SDK 未就绪,恢复失败(进首页后再试),未退出"
				print("[Cheat] loading_page_test 恢复失败:SDK 未就绪")
				return

			var real: Variant = cfg.peek_value()
			print("[Cheat] loading_page_test 落盘 peek 已恢复 SDK 真值 = %s,退出游戏" % str(real))
			panel.get_tree().quit()
	)

	searchable.append({"row": block, "text": "loading_page_test peek 落盘 名言 最长 quote slogan"})


func _make_checked_color_unchecked_icon(check_box: CheckBox) -> ImageTexture:
	var checked_icon: Texture2D = check_box.get_theme_icon(&"checked")
	var unchecked_icon: Texture2D = check_box.get_theme_icon(&"unchecked")
	if checked_icon == null or unchecked_icon == null:
		return null
	var checked_image: Image = checked_icon.get_image()
	var unchecked_image: Image = unchecked_icon.get_image()
	if checked_image == null or unchecked_image == null:
		return null
	checked_image.convert(Image.FORMAT_RGBA8)
	unchecked_image.convert(Image.FORMAT_RGBA8)

	var accent: Color = Color.WHITE
	var highest_saturation: float = -1.0
	for y: int in range(checked_image.get_height()):
		for x: int in range(checked_image.get_width()):
			var pixel: Color = checked_image.get_pixel(x, y)
			if pixel.a <= 0.0:
				continue
			var highest_channel: float = maxf(pixel.r, maxf(pixel.g, pixel.b))
			var lowest_channel: float = minf(pixel.r, minf(pixel.g, pixel.b))
			var saturation: float = highest_channel - lowest_channel
			if saturation > highest_saturation:
				highest_saturation = saturation
				accent = pixel

	for y: int in range(unchecked_image.get_height()):
		for x: int in range(unchecked_image.get_width()):
			var pixel: Color = unchecked_image.get_pixel(x, y)
			if pixel.a > 0.0:
				unchecked_image.set_pixel(x, y, Color(accent.r, accent.g, accent.b, pixel.a))
	return ImageTexture.create_from_image(unchecked_image)


func _refresh_peek_status(cfg: LoadingPageTestConfig, status_lbl: Label) -> void:
	var saved: Variant = GameState.get_saved_peek_ab_group(cfg.key)
	var saved_str: String = "未记录(冷启动回落对照组)" if saved == null else str(saved)
	var longest_quote: String = "开" if GameState.is_loading_page_test_force_longest_quote() else "关"
	status_lbl.text = "当前落盘 peek 值:%s · 最长名言强制:%s" % [saved_str, longest_quote]
