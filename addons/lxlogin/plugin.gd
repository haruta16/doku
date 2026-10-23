## 登录 SDK 编辑器插件：管理 LXAuth 自动加载、平台导出器和 iOS 插件链接。
@tool
extends EditorPlugin

const AUTOLOAD_NAME = "LXAuth"
const AUTOLOAD_PATH = "res://addons/lxlogin/scripts/lx_auth.gd"
const LXAuthIOSExportPlugin = preload("editor/ios_export_plugin.gd")
const LXAuthAndroidExportPlugin = preload("editor/android_export_plugin.gd")
const _PLUGINS_SRC = "res://addons/lxlogin/native/ios/plugins"
const _PLUGINS_DST = "res://ios/plugins/lxauth"

var _ios_export_plugin: EditorExportPlugin = null
var _android_export_plugin: EditorExportPlugin = null


## 启用插件时添加 LXAuth 自动加载，使运行时可通过统一入口访问认证。
func _enable_plugin() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


## 停用插件时移除 LXAuth 自动加载配置。
func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)


## 注册 Android、iOS 导出器，并准备 iOS 原生插件的工程链接。
func _enter_tree() -> void:
	_ios_export_plugin = LXAuthIOSExportPlugin.new()
	add_export_plugin(_ios_export_plugin)
	_android_export_plugin = LXAuthAndroidExportPlugin.new()
	add_export_plugin(_android_export_plugin)
	_ensure_ios_plugins_symlink()


## 卸载两个导出器并清空引用。
func _exit_tree() -> void:
	if _android_export_plugin:
		remove_export_plugin(_android_export_plugin)
		_android_export_plugin = null
	if _ios_export_plugin:
		remove_export_plugin(_ios_export_plugin)
		_ios_export_plugin = null


## 确认 iOS 插件目录指向 addon；目标不符时删除原目标并重建符号链接。
func _ensure_ios_plugins_symlink() -> void:
	var src_abs: String = ProjectSettings.globalize_path(_PLUGINS_SRC)
	var dst_abs: String = ProjectSettings.globalize_path(_PLUGINS_DST)
	if not DirAccess.dir_exists_absolute(_PLUGINS_SRC):
		return

	var rel_target: String = "../../addons/lxlogin/native/ios/plugins"
	var output: Array = []
	OS.execute("readlink", [dst_abs], output)
	var current_target: String = (
		output[0].strip_edges() if output.size() > 0 and output[0] is String else ""
	)
	if current_target == rel_target or current_target == src_abs:
		return
	if DirAccess.dir_exists_absolute(dst_abs) or FileAccess.file_exists(dst_abs):
		OS.execute("rm", ["-rf", dst_abs])
	var parent: String = dst_abs.get_base_dir()
	DirAccess.make_dir_recursive_absolute(parent)
	OS.execute("ln", ["-s", rel_target, dst_abs])
	print("[LXLogin] iOS plugins symlinked: %s → %s" % [dst_abs, rel_target])
