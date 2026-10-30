extends SceneTree

const Pack = preload("res://scripts/framework/content/content_raw_pack.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 4:
		quit(2)
		return
	var verified: Dictionary = Pack.mount_once(args[0], args[1], args[2], args[3])
	if not verified.ok:
		push_error("PACK_VALIDATION_FAILED: " + str(verified.error))
		quit(3)
		return
	if args[3] == "spine_pck":
		for entry: Dictionary in verified.value:
			if entry.path.ends_with(".tres"):
				var resource: Resource = load(entry.path)
				if resource == null or resource.get_class() != "SpineSkeletonDataResource" or resource.get("atlas_res") == null or resource.get("skeleton_file_res") == null:
					push_error("PACK_VALIDATION_FAILED: spine dependency")
					quit(4)
					return
	print("PACK_VALIDATED ", args[3])
	quit(0)
