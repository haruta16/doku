## 由 validate_content_product.py 在无 Autoload 的独立工程执行。
extends SceneTree


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1:
		quit(2)
		return
	var folder: String = args[0]
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("manifest.json")))
	if not manifest is Dictionary:
		_fail("invalid_manifest")
		return
	var catalog := ContentCatalog.new(folder, manifest)
	var result: Dictionary = catalog.validate_all(DokuContentValidator.validation())
	if not result.get("ok", false):
		_fail(JSON.stringify(result))
		return
	for entry: Dictionary in manifest.get("files", []):
		if entry.kind in ["raw_pck", "spine_pck"]:
			result = ContentRawPack.mount_once(folder.path_join(entry.path), str(manifest.product), str(manifest.release), str(entry.kind))
			if not result.get("ok", false):
				_fail(JSON.stringify(result))
				return
	result = catalog.validate_registered_media()
	if not result.get("ok", false):
		_fail(JSON.stringify(result))
		return
	print("PRODUCT_VALIDATED: ", manifest.release)
	quit(0)


func _fail(error: String) -> void:
	printerr("PRODUCT_VALIDATION_FAILED: ", error)
	quit(1)
