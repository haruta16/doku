## 独立验证 SDK 清单转换：原模板、最小字节改动、幂等性与损坏输入拒绝。
## 可在独立项目复制本脚本和 manifest_sdk.gd 运行，不需要加载游戏自动加载单例。
extends SceneTree

const SDK = preload("res://addons/recovery_android_export/manifest_sdk.gd")
const OUTPUT_GUARD = preload("res://addons/recovery_android_export/output_guard.gd")
var _failures := 0


func _initialize() -> void:
	_verify_output_guard()
	var paths := OS.get_cmdline_user_args()
	if paths.is_empty():
		push_error("Pass original Android template APK paths after --")
		quit(2)
		return
	for path in paths:
		_verify(path)
	if _failures == 0:
		print(
			(
				"ANDROID_MANIFEST_VALIDATION_OK: %d templates, min=24 target=36; malformed input rejected"
				% paths.size()
			)
		)
	quit(1 if _failures > 0 else 0)


func _verify(path: String) -> void:
	var archive := ZIPReader.new()
	if archive.open(path) != OK:
		_check(false, "open " + path)
		return
	var original := archive.read_file("AndroidManifest.xml")
	archive.close()
	var result: Dictionary = SDK.patch(original)
	_check(result.ok, "patch " + path + ": " + str(result.get("error", "")))
	if not result.ok:
		return
	var output: PackedByteArray = result.data
	_check(output.size() == original.size(), "unchanged length")
	_check(result.min_sdk == 24 and result.target_sdk == 36, "expected SDK values")
	_check(original.decode_u32(result.target_offset) == result.old_target_sdk, "input not mutated")
	for index in original.size():
		if index < result.target_offset or index >= result.target_offset + 4:
			_check(output[index] == original[index], "only target integer may change")
	var again: Dictionary = SDK.patch(output)
	_check(again.ok and again.data == output, "idempotent conversion")
	_check(not SDK.patch(original.slice(0, original.size() - 1)).ok, "reject truncation")
	var broken := original.duplicate()
	broken.encode_u32(4, 8)
	_check(not SDK.patch(broken).ok, "reject root length")
	broken = original.duplicate()
	broken[result.target_offset - 1] = 0x03
	_check(not SDK.patch(broken).ok, "reject target string type")
	broken = original.duplicate()
	broken.encode_u32(result.target_offset - 8, 0)
	_check(not SDK.patch(broken).ok, "reject target raw string")
	broken = original.duplicate()
	broken.encode_u32(result.min_offset, 23)
	_check(not SDK.patch(broken).ok, "reject unexpected min SDK")
	var output_dir := OS.get_environment("MEOWDOKU_MANIFEST_TEST_OUTPUT")
	if not output_dir.is_empty():
		var file := FileAccess.open(
			output_dir.path_join(path.get_file() + ".manifest"), FileAccess.WRITE
		)
		file.store_buffer(output)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		push_error("ANDROID_MANIFEST_VALIDATION_FAILED: " + label)


func _verify_output_guard() -> void:
	var path := OS.get_cache_dir().path_join(
		"meowdoku-export-guard-%d-%d.tmp" % [OS.get_process_id(), Time.get_ticks_usec()]
	)
	_check(not FileAccess.file_exists(path), "unique guard fixture")
	var before: Dictionary = OUTPUT_GUARD.snapshot(path)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("old valid output")
	file.close()
	var prior: Dictionary = OUTPUT_GUARD.snapshot(path)
	var kept: Dictionary = OUTPUT_GUARD.remove_changed_output(path, prior)
	_check(
		kept.ok and not kept.removed and FileAccess.get_sha256(path) == prior.sha256,
		"preserve previous unchanged output"
	)
	var unknown: Dictionary = OUTPUT_GUARD.remove_changed_output(path, {"ok": false})
	_check(
		not unknown.ok and FileAccess.file_exists(path),
		"preserve output when prior fingerprint unknown"
	)
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("new failed output")
	file.close()
	var changed: Dictionary = OUTPUT_GUARD.remove_changed_output(path, prior)
	_check(
		changed.ok and changed.removed and not FileAccess.file_exists(path),
		"remove only changed failed output"
	)
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("newly created failed output")
	file.close()
	var created: Dictionary = OUTPUT_GUARD.remove_changed_output(path, before)
	_check(
		created.ok and created.removed and not FileAccess.file_exists(path),
		"remove newly created failed output"
	)
