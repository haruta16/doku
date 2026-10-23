## UniKit iOS 导出器：组装桥接源码、资源与配置，修补 Xcode 工程及签名权限。
@tool
class_name UniKitIOSExportPlugin
extends EditorExportPlugin

const _ADDON_DIR: String = "res://addons/unikit/"
const _APP_DELEGATE_DIR: String = "res://addons/unikit/native/ios/app_delegate/"
const _BRIDGE_SWIFT_DIR: String = "res://addons/unikit/native/ios/bridge/swift/"

const _OPT_CONFIG_DIR: String = "unikit/config_dir"

const _CONFIG_TRES: String = "res://unikit_config.tres"

const _IOS_PLIST_KEY_MAP := {
	"production_id": "LEARNINGS_PRODUCT_IDENTIFIER",
	"analyze_key_id": "LEARNINGS_ANALYTICS_KEY",
	"analyze_secret": "LEARNINGS_ANALYTICS_SECRET",
	"appsflyer_dev_key": "LEARNINGS_APPSFLYER_DEV_KEY",
	"app_store_id": "LEARNINGS_APP_STORE_ID",
	"push_key_id": "LEARNINGS_PUSH_KEY_ID",
	"push_secret": "LEARNINGS_PUSH_SECRET",
	"admob_app_id": "GADApplicationIdentifier",
	"tiktok_app_id": "LEARNINGS_TIKTOK_APP_ID",
	"tiktok_secret": "LEARNINGS_TIKTOK_SECRET",
	"widget_url_schemes": "LEARNINGS_WIDGET_URL_SCHEMES",
}

const _DEFAULT_CONFIG_DIR: String = "res://ios/build"

var _export_path: String = ""
var _config_dir: String = ""
var _is_debug: bool = false
var _is_ios_export: bool = false


## 提供 UniKit iOS 导出器标识。
func _get_name() -> String:
	return "UniKitIOSExporter"


## 只参与 iOS 平台的导出流程。
func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformIOS


## 向 iOS 导出预设添加原生配置目录选项。
func _get_export_options(platform: EditorExportPlatform) -> Array[Dictionary]:
	if not platform is EditorExportPlatformIOS:
		return []
	return [
		{
			"option":
			{
				"name": _OPT_CONFIG_DIR,
				"type": TYPE_STRING,
				"hint": PROPERTY_HINT_DIR,
			},
			"default_value": "res://ios/build",
		},
	]


## 记录导出参数，确认原生产物存在后注册应用代理与配置资源。
func _export_begin(features: PackedStringArray, is_debug: bool, path: String, flags: int) -> void:
	_is_ios_export = get_export_platform() is EditorExportPlatformIOS
	if not _is_ios_export:
		return
	_export_path = path
	_is_debug = is_debug
	var opt: Variant = get_option(_OPT_CONFIG_DIR)
	_config_dir = (str(opt) if opt != null else _DEFAULT_CONFIG_DIR).rstrip("/") + "/"
	print(
		(
			"[UniKitIOSExporter] _export_begin path=%s config_dir=%s is_debug=%s"
			% [path, _config_dir, is_debug]
		)
	)
	if not _verify_xcframework_artifacts():
		return

	_inject_app_delegate_hook()

	_register_google_service_plist(_config_dir)
	_register_abtest_config(_config_dir)
	_register_bi_bundles(_config_dir)
	_register_push_resources(_config_dir)


## 保留逐文件导出回调，本插件的处理集中在导出前后。
func _export_file(_path: String, _type: String, _features: PackedStringArray) -> void:
	pass


## 在 Xcode 工程生成后注入配置、权限和源码，并提示后续 CocoaPods 步骤。
func _export_end() -> void:
	if not _is_ios_export:
		return
	_inject_info_plist()
	_inject_skadnetwork_items()
	_patch_entitlements()
	_patch_dummy_cpp_filetype()
	_inject_swift_bridge_files()
	_patch_code_sign_identity_for_automatic_signing()
	_copy_podfile(_config_dir)
	_print_pod_install_hint()
	print("[UniKitIOSExporter] _export_end completed")


## 将代理实现与注册构造函数注入原生代码，接收启动和激活通知。
func _inject_app_delegate_hook() -> void:
	var mm_path: String = _APP_DELEGATE_DIR + "UniKitAppDelegate.mm"
	if not FileAccess.file_exists(mm_path):
		push_warning("[UniKitIOSExporter] AppDelegate hook 不存在: %s" % mm_path)
		return
	var content: String = FileAccess.get_file_as_string(mm_path)

	content += '\n\n__attribute__((constructor)) static void _unikit_register_app_delegate(void) {\n    GodotAppDelegateUniKit *shared = [GodotAppDelegateUniKit shared];\n    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];\n    [nc addObserver:shared\n           selector:@selector(_onAppDidFinishLaunching:)\n               name:UIApplicationDidFinishLaunchingNotification\n             object:nil];\n    [nc addObserver:shared\n           selector:@selector(_onAppDidBecomeActive:)\n               name:UIApplicationDidBecomeActiveNotification\n             object:nil];\n    NSLog(@"[UniKit] AppDelegate hook registered (analytics init + push callbacks)");\n}\n'

	add_ios_cpp_code(content)
	print("  injected AppDelegate hook (UniKitAppDelegate.mm + constructor)")


## 扫描桥接目录的 Swift 文件并排序，保证导出处理顺序稳定。
func _scan_swift_files() -> Array[String]:
	var out: Array[String] = []
	var dir: DirAccess = DirAccess.open(_BRIDGE_SWIFT_DIR)
	if dir == null:
		push_error(
			(
				"[UniKitIOSExporter] 打不开 Swift 源目录: %s (err=%d)"
				% [_BRIDGE_SWIFT_DIR, DirAccess.get_open_error()]
			)
		)
		return out
	for f: String in dir.get_files():
		if f.ends_with(".swift"):
			out.append(f)
	out.sort()
	return out


## 复制 Swift 源码到 Xcode 目录，再补工程引用和 Swift 编译版本。
func _inject_swift_bridge_files() -> void:
	var xcodeproj_dir: String = _export_path.get_base_dir()
	var scheme: String = _export_path.get_file().get_basename()
	var dst_dir: String = xcodeproj_dir.path_join(scheme).path_join("UniKit")
	DirAccess.make_dir_recursive_absolute(dst_dir)
	var swift_files: Array[String] = _scan_swift_files()
	if swift_files.is_empty():
		push_error("[UniKitIOSExporter] Swift 源目录没有任何 .swift 文件: %s" % _BRIDGE_SWIFT_DIR)
		return
	print("  扫描到 %d 个 Swift 源文件: %s" % [swift_files.size(), str(swift_files)])
	var copied: Array[String] = []
	for fname in swift_files:
		var src: String = _BRIDGE_SWIFT_DIR + fname
		var dst: String = dst_dir.path_join(fname)
		if not FileAccess.file_exists(src):
			push_error("[UniKitIOSExporter] Swift 源缺失: %s" % src)
			continue
		_copy_file(src, dst)
		copied.append(fname)
	if copied.is_empty():
		push_error("[UniKitIOSExporter] 没有 Swift 文件被拷贝，pbxproj patch 跳过")
		return
	_patch_pbxproj_add_swift_files(copied, scheme)
	_patch_pbxproj_set_swift_version()
	print("  injected %d Swift files into Xcode project: %s" % [copied.size(), str(copied)])


## 从文件相关种子生成稳定的 Xcode 标识，供重复导出时识别已有条目。
func _pbx_uuid(seed: String) -> String:
	var h1: int = abs(seed.hash())
	var h2: int = abs((seed + "_ref").hash())
	var h3: int = abs((seed + "_build").hash())
	return "%08X%08X%08X" % [h1, h2, h3]


## 补文件引用与首个 Sources 阶段条目；已有标识时跳过重复注入。
func _patch_pbxproj_add_swift_files(files: Array, scheme: String) -> bool:
	var pbxproj_path: String = _export_path.path_join("project.pbxproj")
	if not FileAccess.file_exists(pbxproj_path):
		push_error("[UniKitIOSExporter] project.pbxproj 不存在")
		return false
	var content: String = FileAccess.get_file_as_string(pbxproj_path)

	var phase_count_re := RegEx.new()
	phase_count_re.compile("isa = PBXSourcesBuildPhase;")
	var phase_matches: Array = phase_count_re.search_all(content)
	if phase_matches.size() > 1:
		push_warning(
			(
				"[UniKitIOSExporter] project.pbxproj 包含 %d 个 PBXSourcesBuildPhase，将插入首匹配（主 target），Task 24 验证时确认是否需调整"
				% phase_matches.size()
			)
		)
	elif phase_matches.size() == 0:
		push_error("[UniKitIOSExporter] project.pbxproj 找不到 PBXSourcesBuildPhase")
		return false
	else:
		print("  [pbxproj] 检测到 %d 个 PBXSourcesBuildPhase" % phase_matches.size())

	var changed: bool = false
	for fname in files:
		var file_uuid: String = _pbx_uuid("UniKit_Swift_" + fname + "_ref")
		var build_uuid: String = _pbx_uuid("UniKit_Swift_" + fname + "_build")

		if content.contains(file_uuid):
			print("  [pbxproj] %s 已注入 (%s)，跳过" % [fname, file_uuid])
			continue

		var rel_path: String = "%s/UniKit/%s" % [scheme, fname]
		var ref_line: String = (
			'\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = "%s"; path = "%s"; sourceTree = SOURCE_ROOT; };\n'
			% [file_uuid, fname, fname, rel_path]
		)
		var anchor_ref: String = "/* End PBXFileReference section */"
		if not content.contains(anchor_ref):
			push_error("[UniKitIOSExporter] pbxproj 找不到 PBXFileReference 段尾锚点")
			return false
		content = content.replace(anchor_ref, ref_line + anchor_ref)

		var build_line: String = (
			"\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };\n"
			% [build_uuid, fname, file_uuid, fname]
		)
		var anchor_build: String = "/* End PBXBuildFile section */"
		if not content.contains(anchor_build):
			push_error("[UniKitIOSExporter] pbxproj 找不到 PBXBuildFile 段尾锚点")
			return false
		content = content.replace(anchor_build, build_line + anchor_build)

		var src_phase_anchor_re := RegEx.new()
		src_phase_anchor_re.compile(
			"(isa = PBXSourcesBuildPhase;[\\s\\S]*?files = \\([\\s\\S]*?)(\\s*\\);)"
		)
		var m: RegExMatch = src_phase_anchor_re.search(content)
		if m == null:
			push_error("[UniKitIOSExporter] pbxproj 找不到 PBXSourcesBuildPhase files anchor")
			return false
		var insert: String = "\t\t\t\t%s /* %s in Sources */,\n" % [build_uuid, fname]
		var before: String = content.substr(0, m.get_end(1))
		var after: String = content.substr(m.get_end(1))
		content = before + insert + after
		changed = true
		print("  [pbxproj] 注入 Swift 文件 %s（ref=%s build=%s）" % [fname, file_uuid, build_uuid])
	if not changed:
		return true
	var f: FileAccess = FileAccess.open(pbxproj_path, FileAccess.WRITE)
	if f == null:
		push_error("[UniKitIOSExporter] 写 pbxproj 失败: %s" % FileAccess.get_open_error())
		return false
	f.store_string(content)
	f.close()
	return true


## 工程没有 Swift 版本设置时，在各配置中补入 5.0。
func _patch_pbxproj_set_swift_version() -> bool:
	var pbxproj_path: String = _export_path.path_join("project.pbxproj")
	var content: String = FileAccess.get_file_as_string(pbxproj_path)
	if content.contains("SWIFT_VERSION ="):
		print("  [pbxproj] SWIFT_VERSION 已存在，跳过")
		return true
	var regex := RegEx.new()
	regex.compile('INFOPLIST_FILE = "[^"]+";')
	var matches: Array = regex.search_all(content)
	if matches.is_empty():
		push_error("[UniKitIOSExporter] pbxproj 找不到 INFOPLIST_FILE 锚点，无法注入 SWIFT_VERSION")
		return false
	var append_str: String = "\n\t\t\t\tSWIFT_VERSION = 5.0;"
	for i in range(matches.size() - 1, -1, -1):
		var m: RegExMatch = matches[i]
		content = content.substr(0, m.get_end()) + append_str + content.substr(m.get_end())
	var f: FileAccess = FileAccess.open(pbxproj_path, FileAccess.WRITE)
	if f == null:
		push_error(
			"[UniKitIOSExporter] 写 pbxproj 失败（SWIFT_VERSION）: %s" % FileAccess.get_open_error()
		)
		return false
	f.store_string(content)
	f.close()
	print("  [pbxproj] 在 %d 处 INFOPLIST_FILE 后追加 SWIFT_VERSION = 5.0" % matches.size())
	return true


## 写入 SDK 配置与调试标识，再检查 plist 语法和关键字段。
func _inject_info_plist() -> void:
	print("[UniKitIOSExporter] _inject_info_plist 开始")
	var dict: Dictionary = {}
	if not _build_ios_plist_keys(dict):
		return

	dict["LEARNINGS_DEV_MODE"] = str(_is_debug).to_lower()
	dict["LEARNINGS_LOG_LEVEL"] = "4" if _is_debug else "0"
	var plist_path: String = _resolve_info_plist_path()
	print("  [path] target plist = %s" % plist_path)
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
	var success_count: int = 0
	var fail_count: int = 0
	for key: String in dict.keys():
		if _patch_one_key(plist_path, key, dict[key]):
			success_count += 1
		else:
			fail_count += 1
	var lint_out: Array = []
	var lint_rc: int = OS.execute("plutil", ["-lint", plist_path], lint_out, true)
	if lint_rc != 0:
		push_error("[UniKitIOSExporter] plutil -lint 失败,Info.plist 可能已损坏: %s" % plist_path)

	var critical_keys: Array = ["LEARNINGS_PRODUCT_IDENTIFIER", "GADApplicationIdentifier"]
	var missing: Array = []
	for k: String in critical_keys:
		if _read_plist_string(plist_path, k).is_empty():
			missing.append(k)
	if not missing.is_empty():
		push_error("[UniKitIOSExporter] 关键 key 缺失,运行时大概率崩溃: %s" % missing)
	print(
		(
			"[UniKitIOSExporter] _inject_info_plist 完成: success=%d fail=%d (target=%s)"
			% [success_count, fail_count, plist_path]
		)
	)


## 将本地广告归因网络列表转换成 Info.plist 的字典数组。
func _inject_skadnetwork_items() -> void:
	var src: String = _config_dir + "SKAdNetworkIdentifier.json"
	if not FileAccess.file_exists(src):
		push_warning("[UniKitIOSExporter] SKAdNetworkIdentifier.json 缺失，跳过 SKAdNetworkItems 注入")
		return
	var ids = JSON.parse_string(FileAccess.get_file_as_string(src))
	if typeof(ids) != TYPE_ARRAY or ids.is_empty():
		push_error("[UniKitIOSExporter] SKAdNetworkIdentifier.json 内容异常")
		return
	var plist_path: String = _resolve_info_plist_path()
	if not FileAccess.file_exists(plist_path):
		push_error("[UniKitIOSExporter] Info.plist 不存在: %s" % plist_path)
		return
	var items: Array = []
	for id in ids:
		items.append({"SKAdNetworkIdentifier": str(id)})
	if _patch_one_key(plist_path, "SKAdNetworkItems", items):
		print("  ✓ SKAdNetworkItems 写入 %d 项" % items.size())
	else:
		push_error("[UniKitIOSExporter] SKAdNetworkItems 写入失败")


## 验证 iOS 配置资源，把 SDK 字段映射到对应的 plist 键。
func _build_ios_plist_keys(dict: Dictionary) -> bool:
	if not FileAccess.file_exists(_CONFIG_TRES):
		push_error(
			(
				"[UniKitIOSExporter] %s 不存在；请在 FileSystem 右键 New Resource → UniKitConfig 创建并填 ios 子对象"
				% _CONFIG_TRES
			)
		)
		return false
	var cfg = load(_CONFIG_TRES) as UniKitConfig
	if cfg == null:
		push_error("[UniKitIOSExporter] %s 加载失败或不是 UniKitConfig 类型" % _CONFIG_TRES)
		return false
	if cfg.ios == null:
		push_error("[UniKitIOSExporter] UniKitConfig.ios 子 Resource 未创建，无法派生 iOS 密钥")
		return false
	var errors: Array[String] = cfg.ios.validate()
	if errors.size() > 0:
		push_error(
			(
				"[UniKitIOSExporter] UniKitConfig.ios 必填缺失: %s"
				% ", ".join(errors.map(func(e): return "ios." + e))
			)
		)
		return false
	var ios: UniKitIOSConfig = cfg.ios
	for field: String in _IOS_PLIST_KEY_MAP.keys():
		dict[_IOS_PLIST_KEY_MAP[field]] = ios.get(field)
	print("  [tres] 已从 cfg.ios 派生 %d 条 key 写入 Info.plist" % _IOS_PLIST_KEY_MAP.size())
	return true


## 把承载 Objective-C 代理代码的 dummy.cpp 显式设置为 Objective-C++。
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


## 将导出工程的分发证书标识改为开发标识，以配合后续自动签名。
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


## 创建或复用权限文件，写入共享钥匙串组并校验签名配置和实际内容。
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
		"<array>%s</array>" % _value_to_plist_xml("$(AppIdentifierPrefix)com.learningsSharingGroup")
	)
	var rm_out: Array = []
	var rm_rc: int = OS.execute(
		"plutil", ["-remove", "keychain-access-groups", ent_path], rm_out, true
	)
	var ins_out: Array = []
	var ins_rc: int = OS.execute(
		"plutil", ["-insert", "keychain-access-groups", "-xml", groups_xml, ent_path], ins_out, true
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


## 按导出工程名称定位应用的 entitlements 文件。
func _resolve_entitlements_path() -> String:
	var xcodeproj_dir: String = _export_path.get_base_dir()
	var scheme: String = _export_path.get_file().get_basename()
	return xcodeproj_dir.path_join(scheme).path_join("%s.entitlements" % scheme)


## 在已有父目录下写入空的权限字典，供后续追加钥匙串权限。
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


## 工程尚无权限文件设置时，在构建配置中注册其相对路径。
func _patch_pbxproj_set_entitlements(ent_relpath: String) -> bool:
	var pbxproj_path: String = _export_path.path_join("project.pbxproj")
	if not FileAccess.file_exists(pbxproj_path):
		push_error("[UniKitIOSExporter] project.pbxproj 不存在: %s" % pbxproj_path)
		return false
	var content: String = FileAccess.get_file_as_string(pbxproj_path)

	if content.contains("CODE_SIGN_ENTITLEMENTS"):
		print("  [pbxproj] CODE_SIGN_ENTITLEMENTS 已存在 (Godot 自动生成或上次 patch 残留),跳过 pbxproj patch")
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


## 按导出工程名称定位生成的应用 Info.plist。
func _resolve_info_plist_path() -> String:
	var xcodeproj_dir: String = _export_path.get_base_dir()
	var scheme: String = _export_path.get_file().get_basename()
	return xcodeproj_dir.path_join(scheme).path_join("%s-Info.plist" % scheme)


## 调用系统 plutil 删除旧键并写入新的 XML 值，返回写入是否成功。
func _patch_one_key(plist_path: String, key: String, value: Variant) -> bool:
	var xml: String = _value_to_plist_xml(value)
	var summary: String = _summarize_value(value)

	var rm_out: Array = []
	var rm_rc: int = OS.execute("plutil", ["-remove", key, plist_path], rm_out, true)

	var ins_out: Array = []
	var ins_rc: int = OS.execute("plutil", ["-insert", key, "-xml", xml, plist_path], ins_out, true)
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


## 把 plist 转成 JSON 后读取并排序顶层键，用于检查配置结构。
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


## 通过 PlistBuddy 读取单个键，命令失败时返回空串。
func _read_plist_string(plist_path: String, key: String) -> String:
	var out: Array = []
	var rc: int = OS.execute(
		"/usr/libexec/PlistBuddy", ["-c", "Print :%s" % key, plist_path], out, true
	)
	if rc != 0:
		return ""
	return _flat_lines(out).strip_edges()


## 生成有限长度的日志摘要，数组和字典只显示大小。
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


## 把系统命令的多行输出合并成一条诊断消息。
func _flat_lines(lines: Array) -> String:
	return " | ".join(lines).strip_edges()


## 转义反斜杠与美元符号，供本导出器的 plist 字符串转换复用。
static func _shell_escape_for_argv(s: String) -> String:
	return s.replace("\\", "\\\\").replace("$", "\\$")


## 把常用 Variant 值递归转换为 plist XML 片段。
static func _value_to_plist_xml(v: Variant) -> String:
	match typeof(v):
		TYPE_STRING:
			return "<string>%s</string>" % _shell_escape_for_argv(str(v).xml_escape())
		TYPE_INT:
			return "<integer>%d</integer>" % v
		TYPE_FLOAT:
			return "<real>%f</real>" % v
		TYPE_BOOL:
			return "<true/>" if v else "<false/>"
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY:
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


## 将配置目录的 Podfile 模板复制到导出工程旁，供后续安装原生依赖。
func _copy_podfile(config_dir: String) -> void:
	var src: String = ProjectSettings.globalize_path(config_dir + "Podfile")
	if not FileAccess.file_exists(src):
		push_warning("[UniKitIOSExporter] Podfile 模板不存在: %s" % src)
		return
	var dst: String = _export_path.get_base_dir().path_join("Podfile")
	_copy_file(src, dst)
	print("  copied Podfile -> %s" % dst)


## 把 Firebase 配置注册为 iOS 应用资源，缺失时提示原生服务不可用。
func _register_google_service_plist(config_dir: String) -> void:
	var src: String = config_dir + "GoogleService-Info.plist"
	if not FileAccess.file_exists(src):
		push_warning(
			"[UniKitIOSExporter] GoogleService-Info.plist 不存在,Firebase 不可用。请从 Firebase 控制台下载,放到 config_dir(模板见 .example)"
		)
		return
	add_ios_bundle_file(src)
	print("  registered %s → Godot 将自动 cp 到 export 目录并注册到 PBXResourcesBuildPhase" % src)


## 将已有的正式和调试实验配置加入应用资源，两份都缺失时提示默认回退。
func _register_abtest_config(config_dir: String) -> void:
	var names: PackedStringArray = ["ABTest.json", "ABTest_Debug.json"]
	var registered: bool = false
	for name in names:
		var src: String = config_dir + name
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


## 将广告配置包与用户标签配置加入应用资源，缺失项分别报告。
func _register_bi_bundles(config_dir: String) -> void:
	var adcfg: String = config_dir + "adconfigs.bundle/ad_config.json"
	if FileAccess.file_exists(adcfg):
		add_ios_bundle_file(config_dir + "adconfigs.bundle")
		print("  registered adconfigs.bundle")
	else:
		push_warning("[UniKitIOSExporter] adconfigs.bundle/ad_config.json 缺失（未拉取？）")
	var usertag: String = config_dir + "UserTagLowPerfDevice.json"
	if FileAccess.file_exists(usertag):
		add_ios_bundle_file(usertag)
		print("  registered UserTagLowPerfDevice.json")
	else:
		push_warning("[UniKitIOSExporter] UserTagLowPerfDevice.json 缺失（未拉取？）")


## 把推送资源目录中的文件逐项注册进 iOS 应用包。
func _register_push_resources(config_dir: String) -> void:
	var files: PackedStringArray = _collect_push_resource_files(config_dir + "push_resources/")
	for f: String in files:
		add_ios_bundle_file(f)
		print("  registered push resource %s" % f.get_file())


## 收集并排序推送资源，排除 Godot 的导入元数据文件。
static func _collect_push_resource_files(dir: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var d: DirAccess = DirAccess.open(dir)
	if d == null:
		return out
	for f: String in d.get_files():
		if f.get_extension() == "import":
			continue
		out.append(dir + f)
	out.sort()
	return out


## 按字节保存原始文件，无法写入时记录目标路径。
func _copy_file(src: String, dst: String) -> void:
	var data: PackedByteArray = FileAccess.get_file_as_bytes(src)
	var f: FileAccess = FileAccess.open(dst, FileAccess.WRITE)
	if f == null:
		push_error("[UniKitIOSExporter] 写入失败: %s" % dst)
		return
	f.store_buffer(data)
	f.close()


## 输出导出后的人工操作提示，不在此处执行依赖安装或发布。
func _print_pod_install_hint() -> void:
	var dir: String = _export_path.get_base_dir()
	print("════════════════════════════════════════════════════════════════════")
	print("[UniKit iOS] Xcode 工程已生成,接下来手动执行:")
	print("")
	print("  cd %s" % dir)
	print("  pod install")
	print("  open *.xcworkspace")
	print("")
	print("ℹ️ pod 来源:Homebrew formula 装的 pod（实测 1.16.2）即可完成 pod install + 广告配置拉取；")
	print(
		"   若 meeviiads 拉配置报 ruby/gem LoadError,用 Homebrew ruby 跑(PATH=/opt/homebrew/opt/ruby/bin:$PATH)"
	)
	print("⚠️ 私有源需要配置 SSH:确保 ~/.ssh/config 能 ssh 到 bitbucket.org/sealcn")
	print("✅ Swift SDK 桥接由 export plugin 注入到 Xcode 工程,ObjC++ 胶水走 .gdip + xcframework 预编译")
	print("   （xcframework 产物随 addon rsync 一起带入，消费项目无需重编）")
	print("⚠️ 广告 adconfigs.bundle 需要 pod install 之后跑 meeviiads install:")
	print("   ./Pods/LearningsAdsKit/releases/LearningsAdsKit/MeeviiAdsHelper/meeviiads install \\")
	print("       <scheme> <scheme> <productionId> .  [--debug]")
	print("   (jenkins 走 CommoniOSPipeline 的 MeeviiAdsInstall stage 自动跑)")
	print("════════════════════════════════════════════════════════════════════")


const _XCFRAMEWORK_CONFIGS: Array[String] = ["debug", "release_debug", "release"]
const _PLUGINS_DIR: String = "res://addons/unikit/native/ios/plugins/"


## 确认插件描述与三种构建配置的 xcframework 都随 addon 提供。
func _verify_xcframework_artifacts() -> bool:
	if not FileAccess.file_exists(_PLUGINS_DIR + "unikit.gdip"):
		push_error("UniKit xcframework 缺失，请联系 addon 维护者重新分发完整 addon")
		return false
	for cfg in _XCFRAMEWORK_CONFIGS:
		var info_plist: String = _PLUGINS_DIR + "unikit." + cfg + ".xcframework/Info.plist"
		if not FileAccess.file_exists(info_plist):
			push_error("UniKit xcframework 缺失，请联系 addon 维护者重新分发完整 addon")
			return false
	return true
