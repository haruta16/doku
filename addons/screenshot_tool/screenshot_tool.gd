@tool
extends EditorPlugin

const SCREENSHOT_FOLDER: String = "Screenshots"
const MAX_FILES_PER_DAY: int = 1000
const MCP_REQUEST_PATH: String = "user://mcp_screenshot_request"
const MCP_SCREENSHOT_PATH: String = "user://mcp_screenshot.png"


func _enter_tree() -> void:
	add_tool_menu_item("截图 - 截取屏幕", _capture_screenshot)
	add_tool_menu_item("截图 - 打开今日文件夹", _open_today_folder)
	add_tool_menu_item("截图 - 打开根文件夹", _open_root_folder)
	add_tool_menu_item("截图 - 清空所有截图", _clear_all_screenshots)
	add_autoload_singleton("ScreenshotHotkey", "res://addons/screenshot_tool/screenshot_hotkey.gd")


func _exit_tree() -> void:
	remove_tool_menu_item("截图 - 截取屏幕")
	remove_tool_menu_item("截图 - 打开今日文件夹")
	remove_tool_menu_item("截图 - 打开根文件夹")
	remove_tool_menu_item("截图 - 清空所有截图")
	remove_autoload_singleton("ScreenshotHotkey")


func _get_screenshot_root() -> String:
	return ProjectSettings.globalize_path("res://").get_base_dir().get_base_dir().path_join(
		SCREENSHOT_FOLDER
	)


func _get_today_folder() -> String:
	var dt: Dictionary = Time.get_date_dict_from_system()
	var date_str: String = "%d%02d%02d" % [dt.year, dt.month, dt.day]
	return _get_screenshot_root().path_join(date_str)


func _capture_screenshot() -> void:
	var request_global: String = ProjectSettings.globalize_path(MCP_REQUEST_PATH)
	var screenshot_global: String = ProjectSettings.globalize_path(MCP_SCREENSHOT_PATH)

	var old_mtime: int = 0
	if FileAccess.file_exists(MCP_SCREENSHOT_PATH):
		old_mtime = FileAccess.get_modified_time(screenshot_global)

	var f: FileAccess = FileAccess.open(MCP_REQUEST_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[截图工具] 无法写入请求文件")
		return
	f.store_string("1")
	f.close()

	var waited: float = 0.0
	var got_screenshot: bool = false
	while waited < 3.0:
		OS.delay_msec(100)
		waited += 0.1
		if FileAccess.file_exists(MCP_SCREENSHOT_PATH):
			var new_mtime: int = FileAccess.get_modified_time(screenshot_global)
			if new_mtime > old_mtime:
				got_screenshot = true
				break
	if not got_screenshot:
		push_error("[截图工具] 截图超时（游戏是否在运行？MCPScreenshot 是否已启用？）")
		return

	var image: Image = Image.load_from_file(screenshot_global)
	if image == null:
		push_error("[截图工具] 读取截图文件失败")
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

	var today_path: String = _get_today_folder()
	DirAccess.make_dir_recursive_absolute(today_path)

	var dt: Dictionary = Time.get_datetime_dict_from_system()
	var filename: String = (
		"Screenshot_%d%02d%02d_%02d%02d%02d_%03d.png"
		% [dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second, Time.get_ticks_msec() % 1000]
	)
	var full_path: String = today_path.path_join(filename)
	var err: Error = image.save_png(full_path)
	if err != OK:
		push_error("[截图工具] 保存失败: %s" % error_string(err))
		return

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
			push_warning("[截图工具] 复制到剪贴板失败: %s" % str(output))


func _open_today_folder() -> void:
	var path: String = _get_today_folder()
	DirAccess.make_dir_recursive_absolute(path)
	OS.shell_open(path)


func _open_root_folder() -> void:
	var path: String = _get_screenshot_root()
	DirAccess.make_dir_recursive_absolute(path)
	OS.shell_open(path)


func _clear_all_screenshots() -> void:
	var root: String = _get_screenshot_root()
	if not DirAccess.dir_exists_absolute(root):
		print("[截图工具] 截图文件夹不存在")
		return
	var count: int = _delete_pngs_recursive(root)
	print("[截图工具] 已删除 %d 张截图" % count)


func _delete_pngs_recursive(path: String) -> int:
	var deleted: int = 0
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return 0
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		var full: String = path.path_join(fname)
		if dir.current_is_dir():
			if fname != "." and fname != "..":
				deleted += _delete_pngs_recursive(full)
				var sub: DirAccess = DirAccess.open(full)
				if sub and sub.get_files().is_empty() and sub.get_directories().is_empty():
					DirAccess.remove_absolute(full)
		elif fname.ends_with(".png"):
			DirAccess.remove_absolute(full)
			deleted += 1
		fname = dir.get_next()
	dir.list_dir_end()
	return deleted
