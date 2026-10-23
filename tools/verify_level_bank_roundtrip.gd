## 在临时目录运行真正的编辑器加密逻辑，再用发布包解码器逐份回读；不覆盖项目题库。
extends SceneTree

const ENCODER = preload("res://addons/level_bank_encryptor/bank_file_encoder.gd")
const SUPPORT = preload("res://tools/recovery_level_support.gd")


func _initialize() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/recovery/1.22.0/runtime_manifest.json"))
	var output := OS.get_cache_dir().path_join("meowdoku-bank-roundtrip-%s" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(output)
	var count := 0
	for bank in manifest["banks"]:
		var source: String = "res://" + bank["editor_path"]
		var destination: String = output.path_join(String(bank["runtime_path"]).get_file())
		if not ENCODER.encrypt_file(source, destination):
			push_error("Encrypt failed: " + source)
			quit(1)
			return
		var editor_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(source))
		var runtime_data: Variant = SUPPORT.materialize(SUPPORT.read_runtime(destination))
		if editor_data != runtime_data:
			push_error("Re-encoded data differs from editable JSON: " + source)
			quit(1)
			return
		DirAccess.remove_absolute(destination)
		count += 1
	DirAccess.remove_absolute(output)
	print("ENCRYPTOR_ROUNDTRIP_OK: %d files" % count)
	quit()
