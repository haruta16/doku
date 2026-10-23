## 对照导出包压缩纹理与恢复 PNG 的原尺寸像素，记录差异并修复目标目录中的不一致项。
extends SceneTree

## 先移除 mipmaps 再解压原尺寸图像，避免低层 ASTC 对齐告警影响核查。
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 4:
		push_error("Usage: <recovered-root> <target-root> <manifest.json> <report.json>")
		quit(2)
		return
	var source_root: String = args[0]
	var target_root: String = args[1]
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[2]))
	if not parsed is Array or parsed.is_empty():
		push_error("Manifest must be a nonempty JSON array")
		quit(2)
		return
	var entries: Array = parsed
	var report: Array[Dictionary] = []
	var failures := 0
	for entry: Dictionary in entries:
		var item: Dictionary = entry.duplicate(true)
		var texture := CompressedTexture2D.new()
		var error := texture.load(source_root.path_join(entry.imported_path.trim_prefix("res://")))
		if error != OK:
			item["error"] = "Load failed: %d" % error
			failures += 1
			report.append(item)
			continue
		var original := texture.get_image()
		if original == null or original.is_empty():
			item["error"] = "No image data"
			failures += 1
			report.append(item)
			continue
		item["original_format"] = original.get_format()
		item["original_has_mipmaps"] = original.has_mipmaps()
		original.clear_mipmaps()
		if original.is_compressed() and original.decompress() != OK:
			item["error"] = "Decompression failed"
			failures += 1
			report.append(item)
			continue
		original.convert(Image.FORMAT_RGBA8)
		var source_png: String = source_root.path_join(entry.source_file.trim_prefix("res://"))
		var recovered := Image.load_from_file(source_png)
		if recovered == null or recovered.is_empty():
			item["recovered_png_matches"] = false
		else:
			recovered.convert(Image.FORMAT_RGBA8)
			item["recovered_png_matches"] = recovered.get_size() == original.get_size() and recovered.get_data() == original.get_data()
		item["size"] = [original.get_width(), original.get_height()]
		var target: String = target_root.path_join(entry.source_file.trim_prefix("res://"))
		if not item.recovered_png_matches:
			DirAccess.make_dir_recursive_absolute(target.get_base_dir())
			var save_error := original.save_png(target)
			item["repaired"] = save_error == OK
			if save_error != OK:
				item["error"] = "PNG save failed: %d" % save_error
				failures += 1
		item["status"] = "failed" if item.has("error") else ("verified" if item.recovered_png_matches else "repaired")
		report.append(item)
	var result := {"total": entries.size(), "failed": failures, "items": report}
	var file := FileAccess.open(args[3], FileAccess.WRITE)
	if file == null:
		push_error("Cannot write report: " + args[3])
		quit(2)
		return
	file.store_string(JSON.stringify(result, "\t") + "\n")
	file.close()
	print("TEXTURE_AUDIT: %d textures checked; %d failures" % [entries.size(), failures])
	quit(0 if failures == 0 else 1)
