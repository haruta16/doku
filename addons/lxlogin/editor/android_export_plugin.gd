## Android 登录导出器：注入 Facebook 清单配置，并同步主界面的屏幕方向。
@tool
class_name LXAuthAndroidExportPlugin
extends EditorExportPlugin

const _CONFIG_TRES := "res://lxauth_android_config.tres"

const _ORIENTATION_SETTING := "display/window/handheld/orientation"
const _MANIFEST_MAIN := "res://android/build/src/main/AndroidManifest.xml"
const _MANIFEST_DEBUG := "res://android/build/src/debug/AndroidManifest.xml"

const _ORIENTATION_VALUES := [
	"landscape",
	"portrait",
	"reverseLandscape",
	"reversePortrait",
	"sensorLandscape",
	"sensorPortrait",
	"fullSensor",
]

var _is_android_export: bool = false


## 提供导出插件标识，供编辑器区分多个导出扩展。
func _get_name() -> String:
	return "LXAuthAndroidExporter"


## 只参与 Android 平台的导出流程。
func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid


## 配置齐备时生成 Facebook 元数据与内容提供者，缺项时不注入。
func _get_android_manifest_application_element_contents(
	platform: EditorExportPlatform, debug: bool
) -> String:
	if not FileAccess.file_exists(_CONFIG_TRES):
		return ""
	var cfg: LXAuthAndroidConfig = load(_CONFIG_TRES) as LXAuthAndroidConfig
	if cfg == null:
		push_error("[LXAuthAndroidExporter] %s 加载失败或不是 LXAuthAndroidConfig 类型" % _CONFIG_TRES)
		return ""
	var app_id: String = cfg.facebook_app_id
	var client_token: String = cfg.facebook_client_token
	if app_id.is_empty() and client_token.is_empty():
		return ""
	if app_id.is_empty() or client_token.is_empty():
		push_warning(
			(
				"[LXAuthAndroidExporter] %s 里 facebook_app_id/facebook_client_token 只填了一个，Facebook 登录不会生效"
				% _CONFIG_TRES
			)
		)
		return ""
	return (
		'<provider android:name="com.facebook.FacebookContentProvider" '
		+ 'android:authorities="com.facebook.app.FacebookContentProvider%s" ' % app_id
		+ 'android:exported="true" />\n'
		+ (
			'<meta-data android:name="com.facebook.sdk.ApplicationId" android:value="%s" />\n'
			% app_id
		)
		+ (
			'<meta-data android:name="com.facebook.sdk.ClientToken" android:value="%s" />\n'
			% client_token
		)
	)


## Android 导出开始时把项目方向配置同步到构建清单。
func _export_begin(features: PackedStringArray, is_debug: bool, path: String, flags: int) -> void:
	_is_android_export = get_export_platform() is EditorExportPlatformAndroid
	if not _is_android_export:
		return
	_patch_screen_orientation()


## 按 Godot 方向枚举修改主清单和调试清单中的屏幕方向。
func _patch_screen_orientation() -> void:
	var idx: int = ProjectSettings.get_setting(_ORIENTATION_SETTING, 0)
	if idx < 0 or idx >= _ORIENTATION_VALUES.size():
		push_error("[LXAuthAndroidExporter] %s 取值 %s 超出合法范围" % [_ORIENTATION_SETTING, idx])
		return
	var target: String = _ORIENTATION_VALUES[idx]
	var re := RegEx.new()
	re.compile('android:screenOrientation="[A-Za-z]+"')
	for path in [_MANIFEST_MAIN, _MANIFEST_DEBUG]:
		if not FileAccess.file_exists(path):
			push_warning("[LXAuthAndroidExporter] %s 不存在，跳过屏幕方向 patch" % path)
			continue
		var src := FileAccess.get_file_as_string(path)
		var patched := re.sub(src, 'android:screenOrientation="%s"' % target, true)
		if patched == src:
			continue
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			push_error("[LXAuthAndroidExporter] 写 %s 失败" % path)
			continue
		f.store_string(patched)
		f.close()
		print("[LXAuthAndroidExporter] ✓ %s screenOrientation 已改为 %s" % [path, target])
