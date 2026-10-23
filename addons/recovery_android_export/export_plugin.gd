## 非 Gradle Spine 模板的局部导出适配。原生库仍是官方 4.6.1 构建，只保留原包 target 36。
@tool
extends EditorExportPlugin

const SDK = preload("res://addons/recovery_android_export/manifest_sdk.gd")
const OUTPUT_GUARD = preload("res://addons/recovery_android_export/output_guard.gd")
var _output_path := ""
var _output_before: Dictionary = {}
var _failure := ""
var _next_options_check := 0


func _get_name() -> String:
	return "MeowdokuRecoveryAndroid"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid


## 向导出检查提供可见的目标版本与具体失败原因；只读值避免与实际转换常量不一致。
func _get_export_options(platform: EditorExportPlatform) -> Array[Dictionary]:
	if not platform is EditorExportPlatformAndroid:
		return []
	return [
		{
			"option":
			{
				"name": "recovery/target_sdk",
				"type": TYPE_INT,
				"usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY
			},
			"default_value": SDK.TARGET_SDK
		}
	]


func _get_export_option_warning(platform: EditorExportPlatform, option: String) -> String:
	if not platform is EditorExportPlatformAndroid or option != "recovery/target_sdk":
		return ""
	if bool(get_option("gradle_build/use_gradle_build")):
		return ""
	var errors := PackedStringArray()
	for key in ["custom_template/debug", "custom_template/release"]:
		var reason := _template_error(str(get_option(key)))
		if not reason.is_empty():
			errors.append("Recovery Android SDK [%s]: %s" % [key, reason])
	return "\n".join(errors)


## Godot 将这些覆盖值单独保存在内存中，保存 export_presets.cfg 时仍写原始值。
## 无效模板变成不可打开的路径，由引擎配置检查阻止导出；从不调用 preset.set()。
func _get_export_options_overrides(platform: EditorExportPlatform) -> Dictionary:
	if (
		not platform is EditorExportPlatformAndroid
		or bool(get_option("gradle_build/use_gradle_build"))
	):
		return {}
	var overrides := {}
	for key in ["custom_template/debug", "custom_template/release"]:
		var reason := _template_error(str(get_option(key)))
		if not reason.is_empty():
			overrides[key] = "recovery-export-refused://%s" % reason.uri_encode()
	return overrides


## 文件被替换后重新检查覆盖状态；节流到每秒一次，不在每帧解压模板清单。
func _should_update_export_options(platform: EditorExportPlatform) -> bool:
	if not platform is EditorExportPlatformAndroid or Time.get_ticks_msec() < _next_options_check:
		return false
	_next_options_check = Time.get_ticks_msec() + 1000
	return true


func _template_error(path: String) -> String:
	if path.begins_with("recovery-export-refused://"):
		return path.trim_prefix("recovery-export-refused://").uri_decode()
	var archive := ZIPReader.new()
	if archive.open(path) != OK:
		return "cannot read custom template: " + path
	var result: Dictionary = SDK.patch(archive.read_file("AndroidManifest.xml"))
	archive.close()
	return "" if result.ok else str(result.error)


func _export_begin(_features: PackedStringArray, is_debug: bool, path: String, _flags: int) -> void:
	_failure = ""
	_output_path = ""
	_output_before = {}
	if not get_export_platform() is EditorExportPlatformAndroid:
		return
	if bool(get_option("gradle_build/use_gradle_build")):
		return
	_output_path = path
	_output_before = OUTPUT_GUARD.snapshot(path)
	var key := "custom_template/debug" if is_debug else "custom_template/release"
	_failure = _template_error(str(get_option(key)))
	if not _failure.is_empty():
		_report_failure()


func _update_android_prebuilt_manifest(
	_platform: EditorExportPlatform, manifest_data: PackedByteArray
) -> PackedByteArray:
	var result: Dictionary = SDK.patch(manifest_data)
	if not result.ok:
		_failure = result.error
		_report_failure()
		return PackedByteArray()
	print("RECOVERY_ANDROID_SDK_OK: min=%d target=%d" % [result.min_sdk, result.target_sdk])
	return result.data


## 预检后若出现清单异常，清理本次新写出的产物；导出前已有且指纹未变的文件必须保留。
func _export_end() -> void:
	if not _failure.is_empty() and not _output_path.is_empty():
		var cleanup: Dictionary = OUTPUT_GUARD.remove_changed_output(_output_path, _output_before)
		if not cleanup.ok:
			_failure += " (" + str(cleanup.error) + ")"
		_report_failure()
	_output_path = ""
	_output_before = {}


func _report_failure() -> void:
	get_export_platform().add_message(
		EditorExportPlatform.EXPORT_MESSAGE_ERROR, "Recovery Android SDK", _failure
	)
	push_error(_failure)
