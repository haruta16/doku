extends Node

const SCREENSHOT_FOLDER: String = "Screenshots"
const MCP_REQUEST_PATH: String = "user://mcp_screenshot_request"
const MCP_SCREENSHOT_PATH: String = "user://mcp_screenshot.png"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if (
		event.keycode == KEY_T
		and event.shift_pressed
		and (event.meta_pressed or event.ctrl_pressed)
	):
		_capture()
		get_viewport().set_input_as_handled()


func _capture() -> void:
	var screenshot_global: String = ProjectSettings.globalize_path(MCP_SCREENSHOT_PATH)
	var old_mtime: int = 0
	if FileAccess.file_exists(MCP_SCREENSHOT_PATH):
		old_mtime = FileAccess.get_modified_time(screenshot_global)

	var f: FileAccess = FileAccess.open(MCP_REQUEST_PATH, FileAccess.WRITE)
	if f == null:
		print("[截图工具] 无法写入请求文件")
		return
	f.store_string("1")
	f.close()

	await get_tree().create_timer(0.2).timeout

	if not FileAccess.file_exists(MCP_SCREENSHOT_PATH):
		print("[截图工具] 截图超时")
		return
	var new_mtime: int = FileAccess.get_modified_time(screenshot_global)
	if new_mtime <= old_mtime:
		print("[截图工具] 截图未更新")
		return

	var image: Image = Image.load_from_file(screenshot_global)
	if image == null:
		print("[截图工具] 读取截图失败")
		return

	var target_w: int = ProjectSettings.get_setting("display/window/size/window_width_override", 0)
	var target_h: int = ProjectSettings.get_setting("display/window/size/window_height_override", 0)
	if target_w <= 0 or target_h <= 0:
		target_w = ProjectSettings.get_setting("display/window/size/viewport_width")
		target_h = ProjectSettings.get_setting("display/window/size/viewport_height")
	var src_w: int = image.get_width()
	var src_h: int = image.get_height()
	var crop_w: int = mini(src_w, int(src_h * float(target_w) / float(target_h)))
	var crop_h: int = mini(src_h, int(src_w * float(target_h) / float(target_w)))
	if crop_w < src_w or crop_h < src_h:
		image = image.get_region(Rect2i(0, 0, crop_w, crop_h))
	if image.get_width() != target_w or image.get_height() != target_h:
		image.resize(target_w, target_h, Image.INTERPOLATE_LANCZOS)

	var root_path: String = (
		ProjectSettings
		. globalize_path("res://")
		. get_base_dir()
		. get_base_dir()
		. path_join(SCREENSHOT_FOLDER)
	)
	var dt: Dictionary = Time.get_date_dict_from_system()
	var today_path: String = root_path.path_join("%d%02d%02d" % [dt.year, dt.month, dt.day])
	DirAccess.make_dir_recursive_absolute(today_path)

	var dtm: Dictionary = Time.get_datetime_dict_from_system()
	var filename: String = (
		"Screenshot_%d%02d%02d_%02d%02d%02d_%03d.png"
		% [
			dtm.year,
			dtm.month,
			dtm.day,
			dtm.hour,
			dtm.minute,
			dtm.second,
			Time.get_ticks_msec() % 1000
		]
	)
	var full_path: String = today_path.path_join(filename)
	image.save_png(full_path)
	print("[截图工具] 截图已保存: %s" % full_path)

	if OS.get_name() == "macOS":
		var tmp_script: String = "/tmp/_screenshot_tool_clip.applescript"
		var sf: FileAccess = FileAccess.open(tmp_script, FileAccess.WRITE)
		sf.store_string('set the clipboard to (read (POSIX file "%s") as «class PNGf»)' % full_path)
		sf.close()
		var output: Array = []
		var exit_code: int = OS.execute("osascript", [tmp_script], output)
		if exit_code == 0:
			print("[截图工具] 已复制到剪贴板")
		else:
			push_warning("[截图工具] 复制到剪贴板失败")
