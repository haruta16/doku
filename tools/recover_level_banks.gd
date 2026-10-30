## 从独立解包目录恢复编辑题库；所有预期值取自原包，绝不从待验收工程反推。
## --manifest=绝对路径 --package-root=解包的assets目录 --output=明文目录 --report=报告路径
extends SceneTree

const SUPPORT = preload("res://tools/recovery_level_support.gd")


func _initialize() -> void:
	var options: Dictionary = {}
	for argument in OS.get_cmdline_user_args():
		var parts := argument.trim_prefix("--").split("=", true, 1)
		if parts.size() == 2:
			options[parts[0]] = parts[1]
	for required in ["manifest", "package-root", "output", "report"]:
		if not options.has(required):
			push_error("Missing --%s" % required)
			quit(1)
			return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(options["manifest"]))
	var report := {"schema": 1, "package_sha256": manifest["package_sha256"], "banks": []}
	DirAccess.make_dir_recursive_absolute(options["output"])
	var failures: Array[String] = []
	for item in manifest["level_banks"]:
		var source: String = options["package-root"].path_join(item["path"])
		if FileAccess.get_sha256(source) != item["sha256"]:
			failures.append("Original package hash mismatch: " + source)
			continue
		var raw: Variant = SUPPORT.read_runtime(source)
		if raw == null:
			failures.append("Cannot decode original bank: " + source)
			continue
		var data: Variant = SUPPORT.materialize(raw)
		var filename: String = source.get_file()
		if filename.ends_with(".bin"):
			filename = filename.get_basename() + ".json"
		var text := JSON.stringify(data, "\t", true, true) + "\n"
		var reparsed: Variant = JSON.parse_string(text)
		var comparison: Dictionary = SUPPORT.compare_data(reparsed, data)
		if not comparison["equal"]:
			failures.append("JSON roundtrip differs: " + source)
			continue
		var destination: String = options["output"].path_join(filename)
		var file := FileAccess.open(destination, FileAccess.WRITE)
		if file == null:
			failures.append("Cannot write editor bank: " + destination)
			continue
		file.store_string(text)
		file.close()
		var result: Dictionary = SUPPORT.statistics(data)
		result["runtime_path"] = item["path"]
		result["editor_path"] = "assets/editor/levels/" + filename
		result["runtime_sha256"] = item["sha256"]
		result["editor_sha256"] = FileAccess.get_sha256(destination)
		result["json_roundtrip"] = comparison
		report["banks"].append(result)
		print("RECOVERED_BANK: %s (%d records)" % [filename, result["records"]])
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(String(options["report"]).get_base_dir())
	var report_file := FileAccess.open(options["report"], FileAccess.WRITE)
	report_file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	report_file.close()
	print("RECOVERED_LEVEL_BANKS_OK: %d" % report["banks"].size())
	quit()
