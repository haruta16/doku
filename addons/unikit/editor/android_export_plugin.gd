## UniKit Android 导出器：备份清单、注入原生 SDK 配置，并在导出结束后还原清单。
@tool
class_name UniKitAndroidExportPlugin
extends EditorExportPlugin

const _CONFIG_TRES := "res://unikit_config.tres"
const _MANIFEST := "res://android/build/src/main/AndroidManifest.xml"
const _MANIFEST_BAK := "res://android/build/src/main/AndroidManifest.xml.unikit.bak"

const _APPLICATION_CLASS := "com.beatles.unity.delegate.DelegateApplication"

const _PLUGIN_CLASS := "com.learnings.godot.unikit.UnikitPlugin"
const _PLUGIN_REG_KEY := "org.godotengine.plugin.v2.UniKitPlugin"

const _META_KEYS := {
	"analyze_product_id": "com.learnings.godot.analyze.PRODUCT_ID",
	"analyze_api_key": "com.learnings.godot.analyze.API_KEY",
	"analyze_secret": "com.learnings.godot.analyze.SECRET",
	"analyze_af_dev_key": "com.learnings.godot.analyze.AF_DEV_KEY",
	"analyze_log_level": "com.learnings.godot.analyze.LOG_LEVEL",
	"analyze_dev_mode": "com.learnings.godot.analyze.DEV_MODE",
	"analyze_tiktok_app_id": "com.learnings.godot.analyze.TIKTOK_APP_ID",
	"analyze_tiktok_secret": "com.learnings.godot.analyze.TIKTOK_SECRET",
	"push_product_id": "com.learnings.godot.push.PRODUCT_ID",
	"push_api_key": "com.learnings.godot.push.API_KEY",
	"push_secret": "com.learnings.godot.push.SECRET",
	"push_debug": "com.learnings.godot.push.DEBUG",
	"push_icon_bg_color": "com.learnings.godot.push.ICON_BG_COLOR",
	"notification_icon": "com.google.firebase.messaging.default_notification_icon",
	"admob_app_id": "com.google.android.gms.ads.APPLICATION_ID",
}

var _is_debug: bool = false
var _is_android_export: bool = false


## 提供导出器名称，便于编辑器识别此扩展。
func _get_name() -> String:
	return "UniKitAndroidExporter"


## 只参与 Android 平台导出。
func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid


## 在 Android 导出前验证配置，再按调试或发布模式修改清单。
func _export_begin(features: PackedStringArray, is_debug: bool, path: String, flags: int) -> void:
	_is_android_export = get_export_platform() is EditorExportPlatformAndroid
	if not _is_android_export:
		return
	_is_debug = is_debug
	print("[UniKitAndroidExporter] _export_begin is_debug=%s" % is_debug)
	var cfg: UniKitConfig = _load_and_validate_config()
	if cfg == null:
		return
	_patch_manifest(cfg)


## Android 导出结束后恢复清单备份，避免导出配置留在源工程中。
func _export_end() -> void:
	if not _is_android_export:
		return
	print("[UniKitAndroidExporter] _export_end")
	_restore_manifest()


## 加载 UniKit 配置并检查 Android 必填字段，任何缺项都会终止本次注入。
func _load_and_validate_config() -> UniKitConfig:
	if not FileAccess.file_exists(_CONFIG_TRES):
		push_error(
			(
				"[UniKitAndroidExporter] %s 不存在；FileSystem 右键 New Resource → UniKitConfig 创建并填字段后再 export"
				% _CONFIG_TRES
			)
		)
		return null
	var cfg = load(_CONFIG_TRES) as UniKitConfig
	if cfg == null:
		push_error("[UniKitAndroidExporter] %s 加载失败或不是 UniKitConfig 类型" % _CONFIG_TRES)
		return null
	if cfg.android == null:
		push_error("[UniKitAndroidExporter] UniKitConfig.android 子 Resource 未创建")
		return null
	var errors: Array[String] = cfg.android.validate()
	if errors.size() > 0:
		push_error(
			(
				"[UniKitAndroidExporter] UniKitConfig.android 必填缺失: %s"
				% ", ".join(errors.map(func(e): return "android." + e))
			)
		)
		return null
	print("[UniKitAndroidExporter] ✓ UniKitConfig.android 校验通过")
	return cfg


## 先写完整备份再生成并保存新清单，写入失败时尝试恢复。
func _patch_manifest(cfg: UniKitConfig) -> void:
	if not FileAccess.file_exists(_MANIFEST):
		push_error("[UniKitAndroidExporter] AndroidManifest.xml 不存在: %s" % _MANIFEST)
		return

	var src := FileAccess.get_file_as_string(_MANIFEST)
	var f_bak := FileAccess.open(_MANIFEST_BAK, FileAccess.WRITE)
	if f_bak == null:
		push_error("[UniKitAndroidExporter] 备份失败: %s" % _MANIFEST_BAK)
		return
	f_bak.store_string(src)
	f_bak.close()

	var patched := _apply_manifest_patches(src, cfg)
	if patched == src:
		print("[UniKitAndroidExporter] manifest 已 patched（无变化），跳过写")
		return
	var f := FileAccess.open(_MANIFEST, FileAccess.WRITE)
	if f == null:
		push_error("[UniKitAndroidExporter] 写 manifest 失败")
		_restore_manifest()
		return
	f.store_string(patched)
	f.close()
	print("[UniKitAndroidExporter] ✓ AndroidManifest patched, %s saved" % _MANIFEST_BAK)


## 将备份内容写回源清单，成功后删除备份文件。
func _restore_manifest() -> void:
	if not FileAccess.file_exists(_MANIFEST_BAK):
		return
	var src := FileAccess.get_file_as_string(_MANIFEST_BAK)
	var f := FileAccess.open(_MANIFEST, FileAccess.WRITE)
	if f == null:
		push_error("[UniKitAndroidExporter] 还原 manifest 失败！请手动从 %s 恢复" % _MANIFEST_BAK)
		return
	f.store_string(src)
	f.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_MANIFEST_BAK))
	print("[UniKitAndroidExporter] ✓ AndroidManifest restored")


## 合成应用类、插件注册、统计、推送和广告字段，返回修改后的 XML。
func _apply_manifest_patches(src: String, cfg: UniKitConfig) -> String:
	var a: UniKitAndroidConfig = cfg.android
	var s := src
	s = _patch_application_name(s)
	s = _patch_plugin_registration(s)

	s = _ensure_meta_data(s, _META_KEYS["analyze_product_id"], a.production_id, false)
	s = _ensure_meta_data(s, _META_KEYS["analyze_api_key"], a.analyze_key_id, false)
	s = _ensure_meta_data(s, _META_KEYS["analyze_secret"], a.analyze_secret, false)
	s = _ensure_meta_data(s, _META_KEYS["analyze_af_dev_key"], a.analyze_af_dev_key, false)

	s = _ensure_meta_data(s, _META_KEYS["analyze_log_level"], "4" if _is_debug else "0", false)
	s = _ensure_meta_data(s, _META_KEYS["analyze_dev_mode"], str(_is_debug).to_lower(), false)

	if not a.tiktok_app_id.is_empty():
		s = _ensure_meta_data(s, _META_KEYS["analyze_tiktok_app_id"], a.tiktok_app_id, false)
	if not a.tiktok_secret.is_empty():
		s = _ensure_meta_data(s, _META_KEYS["analyze_tiktok_secret"], a.tiktok_secret, false)

	s = _ensure_meta_data(s, _META_KEYS["push_product_id"], a.production_id, false)
	s = _ensure_meta_data(s, _META_KEYS["push_api_key"], a.push_key_id, false)
	s = _ensure_meta_data(s, _META_KEYS["push_secret"], a.push_secret, false)

	s = _ensure_meta_data(s, _META_KEYS["push_debug"], str(_is_debug).to_lower(), false)

	s = _ensure_meta_data(
		s, _META_KEYS["notification_icon"], "@drawable/%s" % a.notification_small_icon_name, true
	)
	if not a.notification_icon_bg_color.is_empty():
		s = _ensure_meta_data(
			s, _META_KEYS["push_icon_bg_color"], a.notification_icon_bg_color, false
		)

	s = _ensure_meta_data(s, _META_KEYS["admob_app_id"], a.admob_app_id, false)
	return s


## 替换已有 UniKit 注册项的原生类名，注册项不存在时保留原文并警告。
func _patch_plugin_registration(s: String) -> String:
	var re := RegEx.new()
	re.compile(
		(
			'(<meta-data\\b[^/]*?android:name="%s"[^/]*?android:value=")[^"]*(")'
			% _re_escape(_PLUGIN_REG_KEY)
		)
	)
	var m := re.search(s)
	if m == null:
		push_warning(
			(
				"[UniKitAndroidExporter] manifest 未找到插件注册 %s —— 若消费方未手写此项，AAR 插件可能未被 Godot 加载"
				% _PLUGIN_REG_KEY
			)
		)
		return s
	return (
		s.substr(0, m.get_start(1))
		+ m.get_string(1)
		+ _PLUGIN_CLASS
		+ m.get_string(2)
		+ s.substr(m.get_end(2))
	)


## 替换 application 的 Android 类名，使原生 SDK 能接管应用初始化。
func _patch_application_name(s: String) -> String:
	var re := RegEx.new()
	re.compile('(<application\\b[^>]*?\\bandroid:name=")[^"]*(")')
	var m := re.search(s)
	if m == null:
		push_error(
			"[UniKitAndroidExporter] manifest 找不到 <application android:name> — 请确认 manifest 格式"
		)
		return s
	return (
		s.substr(0, m.get_start(1))
		+ m.get_string(1)
		+ _APPLICATION_CLASS
		+ m.get_string(2)
		+ s.substr(m.get_end(2))
	)


## 更新已有元数据或插入新条目，先转义值以保持 XML 结构有效。
static func _ensure_meta_data(s: String, key: String, value: String, is_resource: bool) -> String:
	var attr := "android:resource" if is_resource else "android:value"

	var xml_value := value.xml_escape(true)

	var re_existing := RegEx.new()
	re_existing.compile(
		'(<meta-data\\b[^/]*?android:name="%s"[^/]*?%s=")[^"]*(")' % [_re_escape(key), attr]
	)
	var m := re_existing.search(s)
	if m != null:
		return (
			s.substr(0, m.get_start(1))
			+ m.get_string(1)
			+ xml_value
			+ m.get_string(2)
			+ s.substr(m.get_end(2))
		)

	var close_tag := "</application>"
	var idx := s.find(close_tag)
	if idx < 0:
		push_error("[UniKitAndroidExporter] manifest 找不到 </application>")
		return s
	var indent := "        "
	var snippet := (
		'%s<meta-data android:name="%s"\n%s    %s="%s" />\n%s'
		% [indent, key, indent, attr, xml_value, "    "]
	)
	return s.substr(0, idx) + snippet + s.substr(idx)


## 转义正则特殊字符，让元数据键按字面值参与匹配。
static func _re_escape(literal: String) -> String:
	var out := ""
	for c in literal:
		if c in [".", "+", "*", "?", "(", ")", "[", "]", "{", "}", "|", "^", "$", "\\"]:
			out += "\\" + c
		else:
			out += c
	return out
