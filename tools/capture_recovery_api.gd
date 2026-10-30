## 仅在独立原包恢复工程上运行，为运行验收提供业务 API 的预期结果。
extends SceneTree

const SUPPORT = preload("res://tools/recovery_level_support.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("Usage: --script res://tools/capture_recovery_api.gd -- <runtime_manifest.json>")
		quit(1)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	manifest["bank_api"] = SUPPORT.bank_api_snapshot()
	var file := FileAccess.open(args[0], FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t", true, true) + "\n")
	file.close()
	print("CAPTURED_BANK_API: " + JSON.stringify(manifest["bank_api"]))
	quit()
