## 故意发布不可解码的 PNG，必须在已挂载后要求重启；第二进程才回退。
extends SceneTree

const FixtureGuard = preload("res://tools/validation/fixtures/content_fixture_guard.gd")

const Store = preload("res://scripts/framework/content/content_store.gd")
const Manifest = preload("res://scripts/framework/content/content_manifest.gd")
const RawPack = preload("res://scripts/framework/content/content_raw_pack.gd")
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or not FixtureGuard.allows(args[0]):
		quit(2)
		return
	var root := args[0].path_join("decode-failure")
	if args.size() > 1 and args[1] == "resume":
		var reopened := Store.new(root.path_join("cache"), "test", "runtime-v1", FileAccess.get_file_as_string(root.path_join("public.pem")))
		var recovered: Dictionary = reopened.begin_cold_start()
		if not _check(recovered.ok and recovered.get("builtin", false) and recovered.get("fallback_reason") == "trial_incomplete" and RawPack.mounted_path().is_empty() and reopened.state_snapshot().rejected == "broken-image"):
			push_error("TEST_FAILED: next process must roll back without mounting broken candidate")
			quit(1)
			return
		print("CONTENT_BOOT_FAILURE_COLD_RECOVERY checks=%d failures=%d" % [_checks, _failures])
		quit(0)
		return
	var source := root.path_join("source")
	DirAccess.make_dir_recursive_absolute(source)
	var key := Crypto.new().generate_rsa(2048)
	Store._write_bytes(root.path_join("public.pem"), key.save_to_string(true).to_utf8_buffer())
	Store._write_bytes(source.path_join("broken.png"), "intentional-invalid-image".to_utf8_buffer())
	Store._write_bytes(source.path_join("media.json"), '{"textures":{"ui/home/daily_paw_dim":"broken.png"}}'.to_utf8_buffer())
	var pack := PCKPacker.new()
	pack.pck_start(source.path_join("assets.pck"))
	pack.add_file("res://content/test/broken-image/broken.png", source.path_join("broken.png"))
	pack.flush()
	var entries: Array = []
	for item: Dictionary in [{"id": "media", "path": "media.json", "kind": "json"}, {"id": "raw-assets", "path": "assets.pck", "kind": "raw_pck"}]:
		item["bytes"] = FileAccess.get_file_as_bytes(source.path_join(item.path)).size()
		item["sha256"] = FileAccess.get_sha256(source.path_join(item.path))
		entries.append(item)
	var bytes := JSON.stringify({"format": 1, "product": "test", "runtime": "runtime-v1", "release": "broken-image", "files": entries}).to_utf8_buffer()
	var signature := Crypto.new().sign(HashingContext.HASH_SHA256, Manifest.digest(bytes), key)
	var store := Store.new(root.path_join("cache"), "test", "runtime-v1", key.save_to_string(true))
	if not _check(store.install(source, bytes, signature).ok and store.stage("broken-image").ok):
		push_error("TEST_FAILED: signed fixture must pass structural checks before decoding")
		quit(1)
		return
	var failed: Dictionary = store.begin_cold_start()
	if not _check(not failed.ok and failed.get("error") == "image_decode" and failed.get("restart_required", false) and not RawPack.mounted_path().is_empty() and store.state_snapshot().trial == "broken-image" and not store.confirm_healthy("broken-image").ok):
		push_error("TEST_FAILED: post-mount failure must block this process and retain unconfirmed trial")
		quit(1)
		return
	print("CONTENT_BOOT_FAILURE checks=%d failures=%d" % [_checks, _failures])
	quit(0)


func _check(passed: bool) -> bool:
	_checks += 1
	if not passed:
		_failures += 1
	return passed
