## BI 配置 Inspector 扩展：在平台配置资源中添加调试和发布配置下载按钮。
@tool
class_name UniKitBIConfigInspectorPlugin
extends EditorInspectorPlugin

const _IOS_CONFIG_DIR_DEFAULT := "res://ios/build"


## 仅扩展 UniKit 的 Android 和 iOS 配置资源。
func _can_handle(object: Object) -> bool:
	return object is UniKitAndroidConfig or object is UniKitIOSConfig


## 识别平台配置，为其添加调试与发布两种拉取入口。
func _parse_begin(object: Object) -> void:
	var platform := ""
	if object is UniKitAndroidConfig:
		platform = UniKitBIConfigRequester.PLATFORM_ANDROID
	elif object is UniKitIOSConfig:
		platform = UniKitBIConfigRequester.PLATFORM_IOS
	else:
		return
	var pid := str(object.production_id)

	var ad_major := int(object.ad_major_version)

	var row := HBoxContainer.new()
	row.add_child(_make_button("拉取 Debug", platform, true, pid, ad_major))
	row.add_child(_make_button("拉取 Release", platform, false, pid, ad_major))
	add_custom_control(row)


## 创建按钮并绑定当前平台、环境和产品标识。
func _make_button(
	label: String, platform: String, is_debug: bool, pid: String, ad_major: int
) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(_on_pressed.bind(platform, is_debug, pid, ad_major))
	return btn


## 先校验产品标识，再同步下载配置，最后刷新文件系统并输出结果。
func _on_pressed(platform: String, is_debug: bool, pid: String, ad_major: int) -> void:
	if pid.strip_edges() == "":
		push_error("[UniKitBIConfig] production_id 为空，无法拉取；请先填 %s.production_id" % platform)
		return
	print(
		(
			"[UniKitBIConfig] 手动拉取 platform=%s is_debug=%s pid=%s ad=%s"
			% [
				platform,
				is_debug,
				pid,
				"AD6" if ad_major == UniKitBIConfigRequester.AD_MAJOR_6 else "AD7"
			]
		)
	)
	var fetcher := UniKitBIConfigFetcher.new()
	var r := fetcher.fetch(pid, platform, is_debug, _IOS_CONFIG_DIR_DEFAULT, ad_major)
	if r.ok:
		print("[UniKitBIConfig] ✓ 拉取完成，写入 %d 个文件: %s" % [r.written.size(), str(r.written)])
		EditorInterface.get_resource_filesystem().scan()
	else:
		push_error("[UniKitBIConfig] 拉取失败: %s" % str(r.errors))
