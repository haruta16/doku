## Android 应用内评分导出插件：注册平台导出钩子，把原生 AAR 接入构建。
@tool
extends EditorPlugin

var export_plugin: AndroidExportPlugin


## 编辑器加载插件时注册 Android 导出钩子。
func _enter_tree() -> void:
	export_plugin = AndroidExportPlugin.new()
	add_export_plugin(export_plugin)


## 卸载编辑器插件时移除导出钩子，避免重复注册。
func _exit_tree() -> void:
	remove_export_plugin(export_plugin)
	export_plugin = null


class AndroidExportPlugin:
	extends EditorExportPlugin
	var _plugin_name: String = "InAppReviewPlugin"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		if debug:
			return PackedStringArray(["in_app_review_plugin/bin/debug/in_app_review-debug.aar"])
		else:
			return PackedStringArray(["in_app_review_plugin/bin/release/in_app_review-release.aar"])

	func _get_name() -> String:
		return _plugin_name
