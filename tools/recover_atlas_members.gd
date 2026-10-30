## 从恢复的图集 PNG 按原 AtlasTexture 区域还原成员图片，保留资源 UID。
extends SceneTree

## 清单必须已核实没有 margin、旋转或其他额外变换；裁切过程不缩放或有损编码。
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
	var atlases: Dictionary = {}
	var failures := 0
	for entry: Dictionary in entries:
		var item: Dictionary = entry.duplicate(true)
		var atlas_path: String = entry.atlas_path
		if not atlases.has(atlas_path):
			atlases[atlas_path] = Image.load_from_file(source_root.path_join(atlas_path.trim_prefix("res://")))
		var atlas: Image = atlases[atlas_path]
		if atlas == null or atlas.is_empty():
			item["error"] = "Atlas image failed to load"
			failures += 1
			report.append(item)
			continue
		var coords: Array = entry.region
		var rect := Rect2i(int(coords[0]), int(coords[1]), int(coords[2]), int(coords[3]))
		if not Rect2i(Vector2i.ZERO, atlas.get_size()).encloses(rect):
			item["error"] = "Atlas region extends outside image"
			failures += 1
			report.append(item)
			continue
		var member: Image = atlas.get_region(rect)
		var relative_path: String = entry.source_file.trim_prefix("res://")
		var output: String = target_root.path_join(relative_path)
		DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		var save_error := member.save_png(output)
		if save_error != OK:
			item["error"] = "PNG save failed: %d" % save_error
			failures += 1
			report.append(item)
			continue
		var reloaded := Image.load_from_file(output)
		if reloaded == null or reloaded.get_size() != member.get_size() or reloaded.get_data() != member.get_data():
			item["error"] = "PNG reload pixels differ from recovered region"
			failures += 1
			report.append(item)
			continue
		var import_config := ConfigFile.new()
		var source_file: String = entry.source_file
		var import_target := "res://.godot/imported/%s-%s.ctex" % [source_file.get_file(), source_file.md5_text()]
		import_config.set_value("remap", "importer", "texture")
		import_config.set_value("remap", "type", "CompressedTexture2D")
		import_config.set_value("remap", "uid", entry.uid)
		import_config.set_value("remap", "path", import_target)
		import_config.set_value("remap", "metadata", {"vram_texture": false})
		import_config.set_value("deps", "source_file", source_file)
		import_config.set_value("deps", "dest_files", [import_target])
		import_config.set_value("params", "compress/mode", 0)
		import_config.set_value("params", "compress/high_quality", false)
		import_config.set_value("params", "compress/lossy_quality", 1.0)
		import_config.set_value("params", "compress/hdr_compression", 1)
		import_config.set_value("params", "compress/normal_map", 0)
		import_config.set_value("params", "compress/channel_pack", 0)
		import_config.set_value("params", "mipmaps/generate", false)
		import_config.set_value("params", "mipmaps/limit", -1)
		import_config.set_value("params", "roughness/mode", 0)
		import_config.set_value("params", "roughness/src_normal", "")
		import_config.set_value("params", "process/fix_alpha_border", false)
		import_config.set_value("params", "process/premult_alpha", false)
		import_config.set_value("params", "process/normal_map_invert_y", false)
		import_config.set_value("params", "process/hdr_as_srgb", false)
		import_config.set_value("params", "process/hdr_clamp_exposure", false)
		import_config.set_value("params", "process/size_limit", 0)
		import_config.set_value("params", "detect_3d/compress_to", 1)
		if import_config.save(output + ".import") != OK:
			item["error"] = "Import configuration save failed"
			failures += 1
		else:
			item["status"] = "restored"
			item["pixel_sha256"] = _sha256(member.get_data())
			item["png_sha256"] = FileAccess.get_sha256(output)
		report.append(item)
	var result := {"total": entries.size(), "restored": entries.size() - failures, "failed": failures, "atlas_count": atlases.size(), "items": report}
	var file := FileAccess.open(args[3], FileAccess.WRITE)
	if file == null:
		push_error("Cannot write report: " + args[3])
		quit(2)
		return
	file.store_string(JSON.stringify(result, "\t") + "\n")
	file.close()
	print("ATLAS_RECOVERY: %d/%d restored from %d atlases; %d failed" % [entries.size() - failures, entries.size(), atlases.size(), failures])
	quit(0 if failures == 0 else 1)


## 对解码后的像素取摘要，供恢复报告验证内容而非 PNG 编码差异。
func _sha256(data: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(data)
	return hash.finish().hex_encode()
