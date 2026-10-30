## 在隔离的空工程中运行。输入为 {output, files:[{source,path}]}；不自动包含导入缓存。
extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		quit(2)
		return
	var spec: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not spec is Dictionary:
		quit(2)
		return
	var packer := PCKPacker.new()
	if packer.pck_start(spec.output) != OK:
		quit(3)
		return
	for entry: Dictionary in spec.files:
		if packer.add_file(entry.path, entry.source) != OK:
			quit(4)
			return
	quit(0 if packer.flush() == OK else 5)
