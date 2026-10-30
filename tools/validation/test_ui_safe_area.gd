## 真实窗口/画布变换与页面布局；仅系统提供的安全矩形使用受控输入。
extends SceneTree

var checks: int = 0
var failures: int = 0
var ui: Node
var host: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		printerr("TEST_FAILED: use tools/run_validation.py")
		quit(2)
		return
	host = Node.new()
	root.add_child(host)
	current_scene = host
	ui = root.get_node("UIManager")
	root.get_node("GameState").set_sound_on(false)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.content_scale_size = Vector2i(1080, 2400)
	for scale_factor: float in [0.5, 2.0]:
		root.size = Vector2i(Vector2(1080, 2400) * scale_factor)
		await _settle()
		_check(is_equal_approx(root.get_screen_transform().y.y, scale_factor), "real window stretch scale %s" % scale_factor)
		await _check_controls(scale_factor)
	await _check_letterbox()
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.size = Vector2i(540, 1200)
	await _settle()
	await _check_product_pages()
	host.queue_free()
	await _settle()
	print("UI SAFE AREA TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check_controls(scale_factor: float) -> void:
	var page := Control.new()
	host.add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var parent := Control.new()
	page.add_child(parent)
	parent.position = Vector2(30, 45)
	parent.size = Vector2(600, 1000)
	parent.scale = Vector2(1.25, 1.5)
	var top := _marker(parent, &"_safe_top")
	var bottom := _marker(parent, &"_safe_bottom")
	# 自身缩放不改变 offset 所在坐标系。
	top.scale = Vector2(0.8, 0.6)
	top.pivot_offset = Vector2(20, 15)
	var stretch := _marker(page, &"_safe_top")
	stretch.add_to_group(&"_safe_bottom")
	stretch.anchor_bottom = 1.0
	stretch.offset_bottom = -20.0
	var collapse := Control.new()
	page.add_child(collapse)
	collapse.custom_minimum_size.y = 36.0
	collapse.size_flags_vertical = Control.SIZE_EXPAND_FILL
	collapse.add_to_group(&"_collapse_when_top_safe")
	await _settle()
	var top_before: Vector2 = _control_to_screen(top).origin
	var bottom_before: Vector2 = _control_to_screen(bottom).origin
	var size_before: Vector2 = top.size
	var stretch_before := Vector2(stretch.offset_top, stretch.offset_bottom)
	var bounds: Rect2 = _screen_rect()
	var safe := Rect2(bounds.position + Vector2(0, 100), bounds.size - Vector2(0, 160))
	ui._apply_safe_area_rect("game", page, safe)
	_check(is_equal_approx(_control_to_screen(top).origin.y - top_before.y, 100.0), "top avoids physical 100 px including parent and self scale %s" % scale_factor)
	_check(is_equal_approx(_control_to_screen(bottom).origin.y - bottom_before.y, -60.0), "bottom avoids physical 60 px %s" % scale_factor)
	_check(top.size.is_equal_approx(size_before), "fixed-height marker retains size")
	_check(is_equal_approx(stretch.offset_top - stretch_before.x, 100.0 / scale_factor) and is_equal_approx(stretch.offset_bottom - stretch_before.y, -60.0 / scale_factor), "stretched marker insets both edges from one baseline: before=%s after=%s scale=%s" % [stretch_before, Vector2(stretch.offset_top, stretch.offset_bottom), scale_factor])
	_check(not collapse.visible and collapse.custom_minimum_size.y == 0.0 and collapse.size_flags_vertical == 0, "top spacer collapses")
	ui._apply_safe_area_rect("game", page, safe)
	_check(is_equal_approx(_control_to_screen(top).origin.y - top_before.y, 100.0), "repeated apply never accumulates")
	ui._apply_safe_area_rect("game", page, bounds)
	_check(_control_to_screen(top).origin.is_equal_approx(top_before) and _control_to_screen(bottom).origin.is_equal_approx(bottom_before), "zero inset restores fixed markers")
	_check(Vector2(stretch.offset_top, stretch.offset_bottom).is_equal_approx(stretch_before), "zero inset restores both edges")
	_check(collapse.visible and collapse.custom_minimum_size.y == 36.0 and collapse.size_flags_vertical == Control.SIZE_EXPAND_FILL, "zero inset restores spacer visibility, minimum height and flags")
	ui._apply_safe_area_rect("game", page, bounds.grow(100.0))
	_check(_control_to_screen(top).origin.is_equal_approx(top_before) and _control_to_screen(bottom).origin.is_equal_approx(bottom_before), "negative insets cannot push layout outside baseline")
	ui._apply_safe_area_rect("game", page, safe)
	ui._apply_safe_area_rect("game", page, Rect2())
	_check(_control_to_screen(top).origin.is_equal_approx(top_before) and collapse.visible, "unavailable safe rectangle restores baseline")
	ui._apply_safe_area_rect("confirm", page, safe)
	_check(_control_to_screen(top).origin.is_equal_approx(top_before), "unlisted page is unaffected")
	ui._apply_safe_area("game", page)
	_check(_control_to_screen(top).origin.is_equal_approx(top_before), "desktop entry point retains existing layout")
	page.queue_free()
	await _settle()


func _check_letterbox() -> void:
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(540, 1400)
	root.position = Vector2i(73, 91)
	await _settle()
	var page := Control.new()
	host.add_child(page)
	var marker := _marker(page, &"_safe_top")
	var before: Vector2 = _control_to_screen(marker).origin
	var bounds: Rect2 = _screen_rect()
	_check(is_equal_approx(bounds.size.y, 1200.0), "viewport bounds exclude vertical letterbox padding")
	# 安全边缘尚在黑边内，或超过黑边 30 px：只挪实际侵入内容的部分。
	ui._apply_safe_area_rect("home", page, Rect2(bounds.position - Vector2(0, 20), bounds.size + Vector2(0, 40)))
	_check(_control_to_screen(marker).origin.is_equal_approx(before), "window origin and existing padding are not counted as inset")
	ui._apply_safe_area_rect("home", page, Rect2(bounds.position + Vector2(0, 30), bounds.size - Vector2(0, 30)))
	_check(is_equal_approx(_control_to_screen(marker).origin.y - before.y, 30.0), "only safe edge intrusion moves content after window placement")
	page.queue_free()
	await _settle()


func _check_product_pages() -> void:
	for page_name: String in ["home", "game", "daily_game", "win", "fail", "bank"]:
		var packed: PackedScene = load(UIRegistry.PAGES[page_name])
		var page: Node = packed.instantiate()
		host.add_child(page)
		await _settle()
		var markers: Array[Control] = []
		var before: Array[Vector2] = []
		for child: Node in page.find_children("*", "Control", true, false):
			var c := child as Control
			if c.is_in_group(&"_safe_top") or c.is_in_group(&"_safe_bottom"):
				_check(not c.get_parent() is Container, "safe marker is not overridden by a Container: " + page_name)
				markers.append(c)
				before.append(Vector2(c.offset_top, c.offset_bottom))
		var fail_sizes: Array[Vector2] = []
		var fail_origins: Array[Vector2] = []
		if page_name == "fail":
			for button: String in ["ReviveBtn", "RestartBtn"]:
				var c: Control = page.get_node("Root/Ctrl/VBoxContainer/" + button)
				fail_sizes.append(c.size)
				fail_origins.append(_control_to_screen(c).origin)
		var bounds: Rect2 = _screen_rect()
		ui._apply_safe_area_rect(page_name, page, Rect2(bounds.position + Vector2(0, 50), bounds.size - Vector2(0, 80)))
		await _settle()
		for index: int in markers.size():
			var c: Control = markers[index]
			var expected := before[index]
			var top: float = 100.0 if c.is_in_group(&"_safe_top") else 0.0
			var bottom: float = 60.0 if c.is_in_group(&"_safe_bottom") else 0.0
			if is_equal_approx(c.anchor_top, c.anchor_bottom):
				expected += Vector2.ONE * (top - bottom)
			else:
				expected += Vector2(top, -bottom)
			_check(Vector2(c.offset_top, c.offset_bottom).is_equal_approx(expected), "actual page offsets remain stable after layout: %s expected=%s actual=%s transform=%s" % [page_name, expected, Vector2(c.offset_top, c.offset_bottom), _control_to_screen(c)])
		if page_name == "fail":
			var box: Container = page.get_node("Root/Ctrl/VBoxContainer")
			box.queue_sort()
			await _settle()
			for index: int in 2:
				var button: String = ["ReviveBtn", "RestartBtn"][index]
				var c: Control = box.get_node(button)
				_check(c.size.is_equal_approx(fail_sizes[index]), "fail button retains dimensions after safe-area relayout: " + button)
				_check(is_equal_approx(_control_to_screen(c).origin.y - fail_origins[index].y, -30.0), "fail button retains physical inset after container sort: " + button)
		ui._apply_safe_area_rect(page_name, page, bounds)
		await _settle()
		for index: int in markers.size():
			_check(Vector2(markers[index].offset_top, markers[index].offset_bottom).is_equal_approx(before[index]), "actual cached page restores baseline: " + page_name)
		page.queue_free()
		await _settle()


func _marker(parent: Control, group: StringName) -> Control:
	var marker := Control.new()
	parent.add_child(marker)
	marker.position = Vector2(10, 20)
	marker.size = Vector2(300, 100)
	marker.add_to_group(group)
	return marker


func _control_to_screen(control: Control) -> Transform2D:
	return control.get_viewport().get_screen_transform() * control.get_global_transform_with_canvas()


func _screen_rect() -> Rect2:
	return root.get_screen_transform() * root.get_visible_rect()


func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TEST_FAILED: " + message)
