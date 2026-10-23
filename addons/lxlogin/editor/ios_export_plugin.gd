## iOS 登录导出器：注入应用代理与 Swift 桥接源码，补齐 Xcode 编译设置。
@tool
class_name LXAuthIOSExportPlugin
extends EditorExportPlugin

const _BRIDGE_SWIFT_DIR: String = "res://addons/lxlogin/native/ios/bridge/swift/"
const _SWIFT_FILES: Array[String] = ["LXAuthGodotSwift.swift"]
const _APP_DELEGATE_PATH: String = "res://addons/lxlogin/native/ios/app_delegate/LXAuthAppDelegate.mm"

var _export_path: String = ""
var _is_ios_export: bool = false


## 提供登录 SDK 的 iOS 导出插件标识。
func _get_name() -> String:
	return "LXAuthIOSExporter"


## 只参与 iOS 平台的导出流程。
func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformIOS


## 记录 iOS 导出位置，并把登录应用代理注入 Godot 原生代码。
func _export_begin(features: PackedStringArray, is_debug: bool, path: String, flags: int) -> void:
	_is_ios_export = get_export_platform() is EditorExportPlatformIOS
	if not _is_ios_export:
		return
	_export_path = path
	print("[LXAuthIOSExporter] _export_begin path=%s" % path)
	_inject_app_delegate_hook()


## 导出完成后修正 Objective-C++ 类型，再接入 Swift 桥接源码。
func _export_end() -> void:
	if not _is_ios_export:
		return
	_is_ios_export = false
	if _export_path.is_empty():
		push_error("[LXAuthIOSExporter] export path 为空，跳过 Swift 注入")
		return
	_patch_dummy_cpp_filetype()
	_inject_swift_bridge_files()
	_export_path = ""
	print("[LXAuthIOSExporter] _export_end completed")


## 复制 Swift 桥接源码到导出工程，并注册编译文件与 Swift 版本。
func _inject_swift_bridge_files() -> void:
	var xcodeproj_dir: String = _export_path.get_base_dir()
	var scheme: String = _export_path.get_file().get_basename()
	var dst_dir: String = xcodeproj_dir.path_join(scheme).path_join("LXAuth")
	DirAccess.make_dir_recursive_absolute(dst_dir)
	var copied: Array[String] = []
	for fname in _SWIFT_FILES:
		var src: String = _BRIDGE_SWIFT_DIR + fname
		var dst: String = dst_dir.path_join(fname)
		if not FileAccess.file_exists(src):
			push_error("[LXAuthIOSExporter] Swift 源缺失: %s" % src)
			continue
		_copy_file(src, dst)
		copied.append(fname)
	if copied.is_empty():
		push_error("[LXAuthIOSExporter] 没有 Swift 文件被拷贝")
		return
	_patch_pbxproj_add_swift_files(copied, scheme)
	_patch_pbxproj_set_swift_version()
	print("  injected %d Swift files into Xcode project: %s" % [copied.size(), str(copied)])


## 按字节复制原生源码，写入失败时报告目标路径。
func _copy_file(src: String, dst: String) -> void:
	var content: PackedByteArray = FileAccess.get_file_as_bytes(src)
	var f: FileAccess = FileAccess.open(dst, FileAccess.WRITE)
	if f:
		f.store_buffer(content)
		f.close()


## 从稳定种子生成 Xcode 文件标识，避免重复导出时反复追加同一文件。
func _pbx_uuid(seed: String) -> String:
	var h1: int = abs(seed.hash())
	var h2: int = abs((seed + "_ref").hash())
	var h3: int = abs((seed + "_build").hash())
	return "%08X%08X%08X" % [h1, h2, h3]


## 向 Xcode 工程补文件引用和 Sources 条目，已存在的标识不重复写入。
func _patch_pbxproj_add_swift_files(files: Array, scheme: String) -> bool:
	var pbxproj_path: String = _export_path.path_join("project.pbxproj")
	if not FileAccess.file_exists(pbxproj_path):
		push_error("[LXAuthIOSExporter] project.pbxproj 不存在: %s" % pbxproj_path)
		return false
	var content: String = FileAccess.get_file_as_string(pbxproj_path)

	var changed: bool = false
	for fname in files:
		var file_uuid: String = _pbx_uuid("LXAuth_Swift_" + fname + "_ref")
		var build_uuid: String = _pbx_uuid("LXAuth_Swift_" + fname + "_build")
		if content.contains(file_uuid):
			print("  [pbxproj] %s 已注入，跳过" % fname)
			continue

		var rel_path: String = "%s/LXAuth/%s" % [scheme, fname]
		var ref_line: String = (
			'\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = "%s"; path = "%s"; sourceTree = SOURCE_ROOT; };\n'
			% [file_uuid, fname, fname, rel_path]
		)
		var anchor_ref: String = "/* End PBXFileReference section */"
		if not content.contains(anchor_ref):
			push_error("[LXAuthIOSExporter] pbxproj 找不到 PBXFileReference 段尾锚点")
			return false
		content = content.replace(anchor_ref, ref_line + anchor_ref)

		var build_line: String = (
			"\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };\n"
			% [build_uuid, fname, file_uuid, fname]
		)
		var anchor_build: String = "/* End PBXBuildFile section */"
		if not content.contains(anchor_build):
			push_error("[LXAuthIOSExporter] pbxproj 找不到 PBXBuildFile 段尾锚点")
			return false
		content = content.replace(anchor_build, build_line + anchor_build)

		var src_phase_anchor_re := RegEx.new()
		src_phase_anchor_re.compile(
			"(isa = PBXSourcesBuildPhase;[\\s\\S]*?files = \\([\\s\\S]*?)(\\s*\\);)"
		)
		var m: RegExMatch = src_phase_anchor_re.search(content)
		if m == null:
			push_error("[LXAuthIOSExporter] pbxproj 找不到 PBXSourcesBuildPhase files anchor")
			return false
		var insert: String = "\t\t\t\t%s /* %s in Sources */,\n" % [build_uuid, fname]
		var before: String = content.substr(0, m.get_end(1))
		var after: String = content.substr(m.get_end(1))
		content = before + insert + after
		changed = true
		print("  [pbxproj] 注入 %s (ref=%s build=%s)" % [fname, file_uuid, build_uuid])

	if not changed:
		return true
	var f: FileAccess = FileAccess.open(pbxproj_path, FileAccess.WRITE)
	if f == null:
		push_error("[LXAuthIOSExporter] 写 pbxproj 失败")
		return false
	f.store_string(content)
	f.close()
	return true


## 在导出工程尚未指定 Swift 版本时补为 5.0。
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
		push_error("[LXAuthIOSExporter] pbxproj 找不到 INFOPLIST_FILE 锚点")
		return false
	var append_str: String = "\n\t\t\t\tSWIFT_VERSION = 5.0;"
	for i in range(matches.size() - 1, -1, -1):
		var m: RegExMatch = matches[i]
		content = content.substr(0, m.get_end()) + append_str + content.substr(m.get_end())
	var f: FileAccess = FileAccess.open(pbxproj_path, FileAccess.WRITE)
	if f == null:
		push_error("[LXAuthIOSExporter] 写 pbxproj 失败（SWIFT_VERSION）")
		return false
	f.store_string(content)
	f.close()
	print("  [pbxproj] 追加 SWIFT_VERSION = 5.0")
	return true


## 读取登录应用代理实现，交给 Godot 合并进导出的原生入口。
func _inject_app_delegate_hook() -> void:
	if not FileAccess.file_exists(_APP_DELEGATE_PATH):
		push_warning("[LXAuthIOSExporter] AppDelegate hook 不存在: %s" % _APP_DELEGATE_PATH)
		return
	var content: String = FileAccess.get_file_as_string(_APP_DELEGATE_PATH)
	add_ios_cpp_code(content)
	print("  injected AppDelegate hook (LXAuthAppDelegate.mm → GDTApplicationDelegate addService)")


## 把承载代理代码的 dummy.cpp 标记为 Objective-C++，允许编译原生桥接语法。
func _patch_dummy_cpp_filetype() -> void:
	var pbxproj_path: String = _export_path.path_join("project.pbxproj")
	if not FileAccess.file_exists(pbxproj_path):
		push_warning("[LXAuthIOSExporter] project.pbxproj 不存在，跳过 dummy.cpp filetype patch")
		return
	var content: String = FileAccess.get_file_as_string(pbxproj_path)
	var old_str: String = "lastKnownFileType = sourcecode.cpp.cpp; path = dummy.cpp;"
	var new_str: String = "explicitFileType = sourcecode.cpp.objcpp; path = dummy.cpp;"
	if content.contains(new_str):
		print("  [pbxproj] dummy.cpp filetype 已为 objcpp，跳过")
		return
	if not content.contains(old_str):
		push_warning(
			"[LXAuthIOSExporter] pbxproj 中找不到 dummy.cpp 的 lastKnownFileType=sourcecode.cpp.cpp"
		)
		return
	content = content.replace(old_str, new_str)
	var f: FileAccess = FileAccess.open(pbxproj_path, FileAccess.WRITE)
	if f == null:
		push_error("[LXAuthIOSExporter] 写 pbxproj 失败（dummy.cpp filetype）")
		return
	f.store_string(content)
	f.close()
	print("  [pbxproj] patched dummy.cpp → explicitFileType=sourcecode.cpp.objcpp")
