@tool
extends EditorPlugin

var _export_plugin: IOSUniKitExportPlugin


func _enter_tree() -> void:
	_export_plugin = IOSUniKitExportPlugin.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null


class IOSUniKitExportPlugin:
	extends EditorExportPlugin
	const TEMPLATE_DIR: String = "res://ios/build/"
	const APP_DELEGATE_DIR: String = "res://ios/build/app_delegate/"
	const ADCONFIGS_BUNDLE_DIR: String = "res://ios/build/adconfigs.bundle/"

	var _export_path: String = ""
	var _active_export: bool = false

	func _get_name() -> String:
		return "UniKitIOSExporter"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformIOS

	func _export_begin(
		features: PackedStringArray, is_debug: bool, path: String, flags: int
	) -> void:
		_active_export = features.has("ios")
		if not _active_export:
			return
		_export_path = path
		print("[UniKitIOSExporter] _export_begin path=%s" % path)

		_inject_app_delegate_hook()

		_register_google_service_plist()
		_register_splash_overlay_images()
		_register_abtest_config()

	func _export_file(_path: String, _type: String, _features: PackedStringArray) -> void:
		pass

	func _export_end() -> void:
		if not _active_export:
			return
		_inject_info_plist()
		_patch_entitlements()
		_patch_dummy_cpp_filetype()
		_patch_code_sign_identity_for_automatic_signing()
		_copy_podfile()
		_print_pod_install_hint()
		print("[UniKitIOSExporter] _export_end completed")
		_active_export = false

	func _inject_app_delegate_hook() -> void:
		var mm_path: String = APP_DELEGATE_DIR + "godot_app_delegate_unikit.mm"
		if not FileAccess.file_exists(mm_path):
			push_warning("[UniKitIOSExporter] AppDelegate hook 不存在: %s" % mm_path)
			return
		var content: String = FileAccess.get_file_as_string(mm_path)

		content += '\n\n__attribute__((constructor)) static void _unikit_register_app_delegate(void) {\n\tNSLog(@"[UniKitBridge:probe] ctor01 _unikit_register_app_delegate enter");\n    GodotAppDelegateUniKit *shared = [GodotAppDelegateUniKit shared];\n\tNSLog(@"[UniKitBridge:probe] ctor02 [GodotAppDelegateUniKit shared]=%p", shared);\n    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];\n\tNSLog(@"[UniKitBridge:probe] ctor03 nc=%p, before addObserver willFinishLaunching", nc);\n    [nc addObserver:shared\n           selector:@selector(_onAppDidFinishLaunching:)\n               name:UIApplicationDidFinishLaunchingNotification\n             object:nil];\n\tNSLog(@"[UniKitBridge:probe] ctor04 before addObserver didBecomeActive");\n    [nc addObserver:shared\n           selector:@selector(_onAppDidBecomeActive:)\n               name:UIApplicationDidBecomeActiveNotification\n             object:nil];\n    // splash overlay 安装推迟到主线程下一轮(那时 keyWindow 应该已经创建或在创建路上;\n    // 内部 _unikit_install_splash_overlay 还有 keyWindow 重试机制兜底)\n\tNSLog(@"[UniKitBridge:probe] ctor05 before dispatch_async splash install");\n    dispatch_async(dispatch_get_main_queue(), ^{\n\t\tNSLog(@"[UniKitBridge:probe] ctor06 splash dispatch_async block fired");\n        _unikit_install_splash_overlay();\n    });\n\tNSLog(@"[UniKitBridge] AppDelegate hook registered (constructor + NSNotification observers + splash dispatch)");\n}\n'

		add_ios_cpp_code(content)
		print("  injected AppDelegate hook (godot_app_delegate_unikit.mm + constructor)")

	func _inject_info_plist() -> void:
		print("[UniKitIOSExporter] _inject_info_plist 开始")

		var json_path: String = TEMPLATE_DIR + "info_plist_patch.json"
		if not FileAccess.file_exists(json_path):
			push_error(
				(
					(
						"[UniKitIOSExporter] info_plist_patch.json 不存在: %s。该文件应跟随仓库分发,"
						+ " 请检查 git 状态或联系 SDK 商业产品获取真品配置(详见 ios/build/README.md Step 3)。"
					)
					% json_path
				)
			)
			return
		var json_str: String = FileAccess.get_file_as_string(json_path)
		var data: Variant = JSON.parse_string(json_str)
		if typeof(data) != TYPE_DICTIONARY:
			push_error("[UniKitIOSExporter] info_plist_patch.json 解析失败: %s" % json_path)
			return
		var dict: Dictionary = data

		var plist_path: String = _resolve_info_plist_path()
		print("  [path] _export_path  = %s" % _export_path)
		print("  [path] target plist  = %s" % plist_path)
		if not FileAccess.file_exists(plist_path):
			push_error(
				(
					(
						"[UniKitIOSExporter] 目标 Info.plist 不存在: %s。请确认 Godot 导出已完成,"
						+ " 且导出路径命名规则未变(预期 <export_dir>/<scheme>/<scheme>-Info.plist)。"
					)
					% plist_path
				)
			)
			return

		var before_keys: Array = _list_plist_top_keys(plist_path)
		print("  [before] Info.plist 已有 %d 个顶层 key:" % before_keys.size())
		for k in before_keys:
			print("    - %s" % k)

		var success_count: int = 0
		var fail_count: int = 0
		var skip_count: int = 0
		print("  [patch] 开始注入 patch JSON 中的 key:")
		for key: String in dict.keys():
			if key.begins_with("_"):
				print("    ~ skip :%s (下划线开头,JSON 内部注释字段)" % key)
				skip_count += 1
				continue
			var v: Variant = dict[key]
			if _patch_one_key(plist_path, key, v):
				success_count += 1
			else:
				fail_count += 1

		_strip_empty_unused_usage_descriptions(plist_path)

		var lint_out: Array = []
		var lint_rc: int = OS.execute("plutil", ["-lint", plist_path], lint_out, true)
		print("  [lint] plutil -lint rc=%d output=%s" % [lint_rc, _flat_lines(lint_out)])
		if lint_rc != 0:
			push_error("[UniKitIOSExporter] plutil -lint 失败,Info.plist 可能已损坏: %s" % plist_path)

		var after_keys: Array = _list_plist_top_keys(plist_path)
		print("  [after] Info.plist 现有 %d 个顶层 key" % after_keys.size())
		var added: Array = []
		for k in after_keys:
			if not before_keys.has(k):
				added.append(k)
		print("  [after] 本次新增 %d 个 key: [%s]" % [added.size(), ", ".join(added)])

		var critical_keys: Array = [
			"GADApplicationIdentifier",
			"FacebookAppID",
			"LEARNINGS_PRODUCT_IDENTIFIER",
		]
		print("  [verify] 关键 key 检查:")
		var missing_critical: Array = []
		for k: String in critical_keys:
			var got: String = _read_plist_string(plist_path, k)
			if got.is_empty():
				print("    ✗ %s = <缺失>" % k)
				missing_critical.append(k)
			else:
				print("    ✓ %s = %s" % [k, got])
		if not missing_critical.is_empty():
			push_error("[UniKitIOSExporter] 关键 key 缺失,运行时大概率崩溃: %s" % missing_critical)

		print(
			(
				"[UniKitIOSExporter] _inject_info_plist 完成: success=%d fail=%d skip=%d (target=%s)"
				% [success_count, fail_count, skip_count, plist_path]
			)
		)

	const _UNUSED_USAGE_DESCRIPTION_KEYS: Array[String] = [
		"NSCameraUsageDescription",
		"NSMicrophoneUsageDescription",
		"NSPhotoLibraryUsageDescription",
	]

	func _strip_empty_unused_usage_descriptions(plist_path: String) -> void:
		print("  [strip] 检查未使用的硬件 UsageDescription:")
		for key: String in _UNUSED_USAGE_DESCRIPTION_KEYS:
			var extract_out: Array = []
			var extract_rc: int = OS.execute(
				"plutil", ["-extract", key, "raw", plist_path], extract_out, true
			)
			if extract_rc != 0:
				print("    ~ skip %s (key 不在 plist)" % key)
				continue
			var value: String = _flat_lines(extract_out).strip_edges()
			if value != "" and value != "<NULL>":
				print("    = keep %s = %s (有文案,保留)" % [key, value])
				continue
			var rm_out: Array = []
			var rm_rc: int = OS.execute("plutil", ["-remove", key, plist_path], rm_out, true)
			if rm_rc == 0:
				print("    ✓ removed empty %s" % key)
			else:
				push_warning(
					(
						"[UniKitIOSExporter] plutil -remove %s 失败 rc=%d output=%s"
						% [key, rm_rc, _flat_lines(rm_out)]
					)
				)

	func _patch_dummy_cpp_filetype() -> void:
		var pbxproj_path: String = _export_path.path_join("project.pbxproj")
		if not FileAccess.file_exists(pbxproj_path):
			push_error("[UniKitIOSExporter] project.pbxproj 不存在: %s" % pbxproj_path)
			return
		var content: String = FileAccess.get_file_as_string(pbxproj_path)
		var old_str: String = "lastKnownFileType = sourcecode.cpp.cpp; path = dummy.cpp;"
		var new_str: String = "explicitFileType = sourcecode.cpp.objcpp; path = dummy.cpp;"
		if content.contains(new_str):
			print(
				"  dummy.cpp file type already patched (explicitFileType=sourcecode.cpp.objcpp), skip"
			)
			return
		if not content.contains(old_str):
			push_warning(
				"[UniKitIOSExporter] project.pbxproj 中找不到 dummy.cpp 的 lastKnownFileType=sourcecode.cpp.cpp,Godot 模板可能已变化,xcodebuild archive 可能因 ObjC++ 注入而失败"
			)
			return
		content = content.replace(old_str, new_str)
		var f: FileAccess = FileAccess.open(pbxproj_path, FileAccess.WRITE)
		if f == null:
			push_error("[UniKitIOSExporter] 写 project.pbxproj 失败: %s" % FileAccess.get_open_error())
			return
		f.store_string(content)
		f.close()
		print("  patched dummy.cpp file type → explicitFileType=sourcecode.cpp.objcpp")

	func _patch_code_sign_identity_for_automatic_signing() -> void:
		var pbxproj_path: String = _export_path.path_join("project.pbxproj")
		if not FileAccess.file_exists(pbxproj_path):
			push_error("[UniKitIOSExporter] project.pbxproj 不存在: %s" % pbxproj_path)
			return
		var content: String = FileAccess.get_file_as_string(pbxproj_path)
		var old_str: String = 'CODE_SIGN_IDENTITY = "Apple Distribution";'
		var new_str: String = 'CODE_SIGN_IDENTITY = "Apple Development";'
		if not content.contains(old_str):
			print(
				'  CODE_SIGN_IDENTITY="Apple Distribution" not found, skip (already patched or template changed)'
			)
			return
		var occurrences: int = content.count(old_str)
		content = content.replace(old_str, new_str)
		var f: FileAccess = FileAccess.open(pbxproj_path, FileAccess.WRITE)
		if f == null:
			push_error("[UniKitIOSExporter] 写 project.pbxproj 失败: %s" % FileAccess.get_open_error())
			return
		f.store_string(content)
		f.close()
		print(
			(
				'  patched %d occurrence(s) of CODE_SIGN_IDENTITY "Apple Distribution" → "Apple Development"'
				% occurrences
			)
		)

	func _patch_entitlements() -> void:
		print("[UniKitIOSExporter] _patch_entitlements 开始")

		var ent_path: String = _resolve_entitlements_path()
		var scheme: String = _export_path.get_file().get_basename()
		var ent_relpath: String = "%s/%s.entitlements" % [scheme, scheme]
		print("  [path] target entitlements = %s" % ent_path)
		print("  [path] CODE_SIGN_ENTITLEMENTS relpath = %s" % ent_relpath)

		var created_now: bool = false
		if not FileAccess.file_exists(ent_path):
			if not _create_empty_entitlements(ent_path):
				push_error("[UniKitIOSExporter] 创建 entitlements 文件失败,LUID 注入终止: %s" % ent_path)
				return
			created_now = true
			print(
				"  [create] 创建空 entitlements 文件 (Godot 未自动生成,export_presets entitlements/* 全 Disabled)"
			)
			if not _patch_pbxproj_set_entitlements(ent_relpath):
				push_warning(
					"[UniKitIOSExporter] patch pbxproj CODE_SIGN_ENTITLEMENTS 失败,Xcode 不会签名 entitlements,LUID 仍可能不生效"
				)
		else:
			print("  [reuse] entitlements 文件已存在 (Godot 自动生成或上次 patch 残留)")

		var groups_xml: String = (
			"<array>%s</array>"
			% _value_to_plist_xml("$(AppIdentifierPrefix)com.learningsSharingGroup")
		)
		var rm_out: Array = []
		var rm_rc: int = OS.execute(
			"plutil", ["-remove", "keychain-access-groups", ent_path], rm_out, true
		)
		var ins_out: Array = []
		var ins_rc: int = OS.execute(
			"plutil",
			["-insert", "keychain-access-groups", "-xml", groups_xml, ent_path],
			ins_out,
			true
		)
		if ins_rc != 0:
			push_error(
				(
					"[UniKitIOSExporter] plutil -insert keychain-access-groups 失败 rc=%d output=[%s]"
					% [ins_rc, _flat_lines(ins_out)]
				)
			)
			return
		print(
			(
				'  ✓ keychain-access-groups = ["$(AppIdentifierPrefix)com.learningsSharingGroup"] (created_now=%s, remove rc=%d, insert rc=%d)'
				% [created_now, rm_rc, ins_rc]
			)
		)

		var lint_out: Array = []
		var lint_rc: int = OS.execute("plutil", ["-lint", ent_path], lint_out, true)
		print("  [lint] plutil -lint rc=%d output=%s" % [lint_rc, _flat_lines(lint_out)])
		if lint_rc != 0:
			push_error("[UniKitIOSExporter] plutil -lint 失败,entitlements 已损坏: %s" % ent_path)
			return

		var verify_out: Array = []
		var verify_rc: int = OS.execute(
			"/usr/libexec/PlistBuddy",
			["-c", "Print :keychain-access-groups:0", ent_path],
			verify_out,
			true
		)
		if verify_rc == 0:
			var v: String = _flat_lines(verify_out).strip_edges()
			print("  [verify] keychain-access-groups[0] = %s" % v)
			if v != "$(AppIdentifierPrefix)com.learningsSharingGroup":
				push_error(
					(
						'[UniKitIOSExporter] keychain-access-groups[0] 不匹配预期: expect="$(AppIdentifierPrefix)com.learningsSharingGroup" got="%s"'
						% v
					)
				)
		else:
			push_error(
				(
					"[UniKitIOSExporter] verify keychain-access-groups[0] 失败 rc=%d output=[%s]"
					% [verify_rc, _flat_lines(verify_out)]
				)
			)

		print("[UniKitIOSExporter] _patch_entitlements 完成")

	func _resolve_entitlements_path() -> String:
		var xcodeproj_dir: String = _export_path.get_base_dir()
		var scheme: String = _export_path.get_file().get_basename()
		return xcodeproj_dir.path_join(scheme).path_join("%s.entitlements" % scheme)

	func _create_empty_entitlements(path: String) -> bool:
		var dir: String = path.get_base_dir()
		if not DirAccess.dir_exists_absolute(dir):
			push_error("[UniKitIOSExporter] entitlements 父目录不存在: %s" % dir)
			return false
		var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			push_error(
				(
					"[UniKitIOSExporter] 创建 entitlements 文件失败: %s err=%s"
					% [path, FileAccess.get_open_error()]
				)
			)
			return false
		(
			f
			. store_string(
				(
					'<?xml version="1.0" encoding="UTF-8"?>\n'
					+ '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
					+ '<plist version="1.0">\n'
					+ "<dict>\n"
					+ "</dict>\n"
					+ "</plist>\n"
				)
			)
		)
		f.close()
		return true

	func _patch_pbxproj_set_entitlements(ent_relpath: String) -> bool:
		var pbxproj_path: String = _export_path.path_join("project.pbxproj")
		if not FileAccess.file_exists(pbxproj_path):
			push_error("[UniKitIOSExporter] project.pbxproj 不存在: %s" % pbxproj_path)
			return false
		var content: String = FileAccess.get_file_as_string(pbxproj_path)

		if content.contains("CODE_SIGN_ENTITLEMENTS"):
			print(
				"  [pbxproj] CODE_SIGN_ENTITLEMENTS 已存在 (Godot 自动生成或上次 patch 残留),跳过 pbxproj patch"
			)
			return true

		var regex := RegEx.new()

		var err: int = regex.compile('INFOPLIST_FILE = "[^"]+";')
		if err != OK:
			push_error("[UniKitIOSExporter] regex compile 失败 err=%d" % err)
			return false
		var matches: Array = regex.search_all(content)
		if matches.is_empty():
			push_warning(
				(
					'[UniKitIOSExporter] project.pbxproj 找不到 INFOPLIST_FILE = "..."; anchor,'
					+ "Godot 模板可能已变化,无法自动 patch CODE_SIGN_ENTITLEMENTS"
				)
			)
			return false

		var append_str: String = '\n\t\t\t\tCODE_SIGN_ENTITLEMENTS = "%s";' % ent_relpath
		for i in range(matches.size() - 1, -1, -1):
			var m: RegExMatch = matches[i]
			content = content.substr(0, m.get_end()) + append_str + content.substr(m.get_end())

		var f: FileAccess = FileAccess.open(pbxproj_path, FileAccess.WRITE)
		if f == null:
			push_error("[UniKitIOSExporter] 写 project.pbxproj 失败: %s" % FileAccess.get_open_error())
			return false
		f.store_string(content)
		f.close()
		print(
			(
				'  [pbxproj] 在 %d 处 INFOPLIST_FILE 后追加 CODE_SIGN_ENTITLEMENTS = "%s"'
				% [matches.size(), ent_relpath]
			)
		)
		return true

	func _resolve_info_plist_path() -> String:
		var xcodeproj_dir: String = _export_path.get_base_dir()
		var scheme: String = _export_path.get_file().get_basename()
		return xcodeproj_dir.path_join(scheme).path_join("%s-Info.plist" % scheme)

	func _patch_one_key(plist_path: String, key: String, value: Variant) -> bool:
		var xml: String = _value_to_plist_xml(value)
		var summary: String = _summarize_value(value)

		var rm_out: Array = []
		var rm_rc: int = OS.execute("plutil", ["-remove", key, plist_path], rm_out, true)

		var ins_out: Array = []
		var ins_rc: int = OS.execute(
			"plutil", ["-insert", key, "-xml", xml, plist_path], ins_out, true
		)
		if ins_rc != 0:
			push_error(
				(
					"[UniKitIOSExporter]     ✗ plutil -insert :%s 失败 rc=%d output=[%s] xml_preview=%s"
					% [key, ins_rc, _flat_lines(ins_out), xml.substr(0, 300)]
				)
			)
			return false
		print("    ✓ :%s = %s  (remove rc=%d, insert rc=%d)" % [key, summary, rm_rc, ins_rc])
		return true

	func _list_plist_top_keys(plist_path: String) -> Array:
		var out: Array = []
		var rc: int = OS.execute("plutil", ["-convert", "json", "-o", "-", plist_path], out, true)
		if rc != 0:
			push_warning(
				(
					"[UniKitIOSExporter] _list_plist_top_keys: plutil -convert json 失败 rc=%d output=[%s]"
					% [rc, _flat_lines(out)]
				)
			)
			return []
		var json_str: String = "\n".join(out)
		var parsed: Variant = JSON.parse_string(json_str)
		if typeof(parsed) != TYPE_DICTIONARY:
			push_warning(
				"[UniKitIOSExporter] _list_plist_top_keys: JSON 解析失败 (%s 字节)" % json_str.length()
			)
			return []
		var keys: Array = (parsed as Dictionary).keys()
		keys.sort()
		return keys

	func _read_plist_string(plist_path: String, key: String) -> String:
		var out: Array = []
		var rc: int = OS.execute(
			"/usr/libexec/PlistBuddy", ["-c", "Print :%s" % key, plist_path], out, true
		)
		if rc != 0:
			return ""
		return _flat_lines(out).strip_edges()

	func _summarize_value(v: Variant) -> String:
		var t: int = typeof(v)
		match t:
			TYPE_STRING:
				var s: String = v
				if s.length() <= 60:
					return '"%s"' % s
				return '"%s..." (string len=%d)' % [s.substr(0, 55), s.length()]
			TYPE_INT, TYPE_FLOAT, TYPE_BOOL:
				return str(v)
			TYPE_ARRAY:
				return "<array len=%d>" % (v as Array).size()
			TYPE_DICTIONARY:
				return "<dict %d keys>" % (v as Dictionary).size()
		return "<%s>" % type_string(t)

	func _flat_lines(lines: Array) -> String:
		return " | ".join(lines).strip_edges()

	func _shell_escape_for_argv(s: String) -> String:
		return s.replace("\\", "\\\\").replace("$", "\\$")

	func _value_to_plist_xml(v: Variant) -> String:
		match typeof(v):
			TYPE_STRING:
				return "<string>%s</string>" % _shell_escape_for_argv(str(v).xml_escape())
			TYPE_INT:
				return "<integer>%d</integer>" % v
			TYPE_FLOAT:
				return "<real>%f</real>" % v
			TYPE_BOOL:
				return "<true/>" if v else "<false/>"
			TYPE_ARRAY:
				var inner: Array[String] = []
				for item: Variant in v:
					inner.append(_value_to_plist_xml(item))
				return "<array>\n%s\n</array>" % "\n".join(inner)
			TYPE_DICTIONARY:
				var inner: Array[String] = []
				for k: String in v.keys():
					inner.append("<key>%s</key>" % k)
					inner.append(_value_to_plist_xml(v[k]))
				return "<dict>\n%s\n</dict>" % "\n".join(inner)
		return "<string></string>"

	func _copy_podfile() -> void:
		var src: String = ProjectSettings.globalize_path(TEMPLATE_DIR + "Podfile")
		if not FileAccess.file_exists(src):
			push_warning("[UniKitIOSExporter] Podfile 模板不存在: %s" % src)
			return
		var dst: String = _export_path.get_base_dir().path_join("Podfile")
		_copy_file(src, dst)
		print("  copied Podfile -> %s" % dst)

	func _register_google_service_plist() -> void:
		var src: String = TEMPLATE_DIR + "GoogleService-Info.plist"
		if not FileAccess.file_exists(src):
			push_warning(
				"[UniKitIOSExporter] GoogleService-Info.plist 不存在,Firebase 不可用。请从 Firebase 控制台下载,放到 ios/build/(模板见 .example)"
			)
			return
		add_ios_bundle_file(src)
		print("  registered %s → Godot 将自动 cp 到 export 目录并注册到 PBXResourcesBuildPhase" % src)

	func _register_abtest_config() -> void:
		var names: PackedStringArray = ["ABTest.json", "ABTest_Debug.json"]
		var registered: bool = false
		for name in names:
			var src: String = TEMPLATE_DIR + name
			if FileAccess.file_exists(src):
				add_ios_bundle_file(src)
				print("  registered %s → 注册到 PBXResourcesBuildPhase(.app 根目录)" % src)
				registered = true
		if not registered:
			push_warning(
				(
					"[UniKitIOSExporter] ABTest.json / ABTest_Debug.json 均不存在,本地分流 AB 参数将回落默认。"
					+ " CI 由 jenkins FetchABTestConfig stage 在 GodotPack 前拉取;本地开发无此步属正常"
				)
			)

	func _register_splash_overlay_images() -> void:
		var src_2x: String = ProjectSettings.get_setting("application/boot_splash/image") as String
		var src_3x: String = ""

		src_2x = "res://assets/icons/ios_launch_2x.png"
		src_3x = "res://assets/icons/ios_launch_3x.png"

		var dst_2x: String = TEMPLATE_DIR + "SplashImage@2x.png"
		var dst_3x: String = TEMPLATE_DIR + "SplashImage@3x.png"

		var ok_2x: bool = _copy_file_for_bundle(src_2x, dst_2x)
		var ok_3x: bool = _copy_file_for_bundle(src_3x, dst_3x)

		if ok_2x:
			add_ios_bundle_file(dst_2x)
		if ok_3x:
			add_ios_bundle_file(dst_3x)

		if ok_2x or ok_3x:
			print("  registered SplashImage overlay: @2x=%s @3x=%s" % [ok_2x, ok_3x])
		else:
			push_warning(
				(
					"[UniKitIOSExporter] SplashImage 启动图未找到,iOS 启动时可能出现白屏。"
					+ " 请确认 res://assets/icons/ios_launch_2x.png 和 ios_launch_3x.png 存在。"
				)
			)

	func _copy_file_for_bundle(src: String, dst: String) -> bool:
		if not FileAccess.file_exists(src):
			push_warning("[UniKitIOSExporter] 源文件不存在: %s" % src)
			return false
		var data: PackedByteArray = FileAccess.get_file_as_bytes(src)
		if data.is_empty():
			push_warning("[UniKitIOSExporter] 源文件为空: %s" % src)
			return false
		var f: FileAccess = FileAccess.open(dst, FileAccess.WRITE)
		if f == null:
			push_error("[UniKitIOSExporter] 写入失败: %s err=%s" % [dst, FileAccess.get_open_error()])
			return false
		f.store_buffer(data)
		f.close()
		return true

	func _copy_file(src: String, dst: String) -> void:
		var data: PackedByteArray = FileAccess.get_file_as_bytes(src)
		var f: FileAccess = FileAccess.open(dst, FileAccess.WRITE)
		if f == null:
			push_error("[UniKitIOSExporter] 写入失败: %s" % dst)
			return
		f.store_buffer(data)

	func _print_pod_install_hint() -> void:
		var dir: String = _export_path.get_base_dir()
		print("════════════════════════════════════════════════════════════════════")
		print("[UniKit iOS] Xcode 工程已生成,接下来手动执行:")
		print("")
		print("  cd %s" % dir)
		print("  pod install")
		print("  open *.xcworkspace")
		print("")
		print("⚠️ 注意:必须用 gem install cocoapods,brew install 会导致广告配置拉取失败。")
		print("⚠️ 私有源需要配置 SSH:确保 ~/.ssh/config 能 ssh 到 bitbucket.org/sealcn")
		print("⚠️ 首次构建前需跑 vita-queendoku-godot/ios/build/bridge/build_xcframework.sh")
		print("   编出 unikit.xcframework 到 ios/plugins/unikit/")
		print("⚠️ 广告 adconfigs.bundle 需要 pod install 之后跑 meeviiads install:")
		print(
			"   ./Pods/LearningsAdsKit/releases/LearningsAdsKit/MeeviiAdsHelper/meeviiads install \\"
		)
		print("       <scheme> <scheme> <productionId> .  [--debug]")
		print("   (jenkins 走 CommoniOSPipeline 的 MeeviiAdsInstall stage 自动跑)")
		print("════════════════════════════════════════════════════════════════════")
