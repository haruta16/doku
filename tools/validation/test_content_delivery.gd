extends SceneTree

const FixtureGuard = preload("res://tools/validation/fixtures/content_fixture_guard.gd")

const Validation = preload("res://scripts/framework/content/content_validation.gd")

const Manifest = preload("res://scripts/framework/content/content_manifest.gd")
const Store = preload("res://scripts/framework/content/content_store.gd")
const RawPack = preload("res://scripts/framework/content/content_raw_pack.gd")
const Downloader = preload("res://scripts/framework/content/content_downloader.gd")
var _failures := 0
var _checks := 0
var _root: String
var _key: CryptoKey
var _public: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 1 or not FixtureGuard.allows(args[0]):
		push_error("The test requires a marked isolated content fixture project.")
		quit(2)
		return
	_root = args[0]
	_key = Crypto.new().generate_rsa(2048)
	_public = _key.save_to_string(true)
	var first := _release("r1", {"level": 1})
	var second := _release("r2", {"level": 2})
	var store := Store.new(_root.path_join("cache"), "test", "runtime-v1", _public)
	_check(store.install(first.source, first.bytes, first.signature).ok, "install verified r1")
	_check(store.install(second.source, second.bytes, second.signature).ok, "install verified r2")
	var bad_signature: PackedByteArray = first.signature.duplicate()
	bad_signature[0] ^= 1
	_check(not store.verify_manifest(first.bytes, bad_signature).ok, "reject altered signature")
	var bad_manifest: Dictionary = JSON.parse_string(first.bytes.get_string_from_utf8())
	bad_manifest.files[0].path = "../escape.json"
	_check(not Manifest.validate(bad_manifest, "test", "runtime-v1").ok, "reject traversal")
	bad_manifest = JSON.parse_string(first.bytes.get_string_from_utf8())
	bad_manifest.files[0].bytes = true
	_check(not Manifest.validate(bad_manifest, "test", "runtime-v1").ok, "reject boolean size")
	_check(not Manifest.parse_verified(first.bytes, first.signature, _public, "test", "wrong-runtime").ok, "reject incompatible runtime")
	_check(store.stage("r1").ok, "stage r1")
	var activated: Dictionary = store.activate_data()
	_check(activated.ok, "activate data immediately")
	var old_catalog: RefCounted = activated.catalog
	_check(store.stage("r2").ok and store.activate_data().ok, "activate r2")
	_check(old_catalog.read_json("levels").value.level == 1, "old snapshot survives new activation")
	var copy: Dictionary = old_catalog.read_json("levels").value
	copy.level = 99
	_check(old_catalog.read_json("levels").value.level == 1, "catalog does not expose mutable cache")
	var restored := Store.new(_root.path_join("cache"), "test", "runtime-v1", _public)
	_check(restored.state_snapshot().active == "r2", "activation durable")
	var changed := _release("r1", {"level": 7}, "different-r1")
	_check(not restored.install(changed.source, changed.bytes, changed.signature).ok, "same release cannot change")
	Store._write_bytes(restored.release_directory("r2").path_join("data/levels.json"), "{}".to_utf8_buffer())
	var fallback: Dictionary = restored.begin_cold_start()
	_check(fallback.ok and fallback.catalog.release_id() == "r1", "damaged active falls back")
	_check(restored.state_snapshot().active == "r1", "fallback repairs durable active pointer")
	var pruned: Dictionary = restored.prune_unreferenced()
	_check(pruned.ok and "r2" in pruned.removed and restored.verify_release("r1").ok, "cleanup retains working fallback")
	var quota_store := Store.new(_root.path_join("quota-cache"), "test", "runtime-v1", _public, 1)
	_check(not quota_store.install(first.source, first.bytes, first.signature).ok, "cache quota enforced before install")
	var bad_hash := _release("bad-hash", {"level": 3})
	Store._write_bytes(bad_hash.source.path_join("data/levels.json"), "{}".to_utf8_buffer())
	_check(not store.install(bad_hash.source, bad_hash.bytes, bad_hash.signature).ok, "altered payload cannot install")
	var failed_state := Store.new(_root.path_join("failed-state"), "test", "runtime-v1", _public)
	_check(failed_state.install(first.source, first.bytes, first.signature).ok, "prepare metadata write failure")
	DirAccess.make_dir_recursive_absolute(_root.path_join("failed-state/activation_1.json"))
	_check(not failed_state.stage("r1").ok and failed_state.state_snapshot().pending.is_empty(), "failed activation write never publishes state")
	var trial_store := Store.new(_root.path_join("trial-cache"), "test", "runtime-v1", _public)
	_check(trial_store.install(first.source, first.bytes, first.signature).ok and trial_store.stage("r1").ok, "prepare trial")
	_check(trial_store.begin_cold_start().trial, "trial marker written before use")
	_check(not trial_store.begin_cold_start().ok, "cold-start API cannot be repeated")
	var next_boot := Store.new(_root.path_join("trial-cache"), "test", "runtime-v1", _public)
	var interrupted: Dictionary = next_boot.begin_cold_start()
	_check(interrupted.ok and interrupted.builtin and interrupted.fallback_reason == "trial_incomplete", "incomplete trial conservatively falls back")
	var rejected := _release("invalid-schema", {"level": -1})
	_check(not store.install(rejected.source, rejected.bytes, rejected.signature, Validation.new(func(_id: String, value: Variant) -> Dictionary: return {"ok": int(value.level) > 0, "error": "invalid_level"})).ok, "gameplay validator rejects invalid data")
	_test_damaged_pending(first, second)
	_test_large_configuration()
	_test_pack()
	if args.size() > 1:
		await _test_http(args[1])
	print("CONTENT_TESTS checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_damaged_pending(first: Dictionary, second: Dictionary) -> void:
	var path := _root.path_join("damaged-pending-cache")
	var store := Store.new(path, "test", "runtime-v1", _public)
	_check(store.install(first.source, first.bytes, first.signature).ok and store.stage("r1").ok and store.activate_data().ok, "prepare active data before damaged candidate")
	_check(store.install(second.source, second.bytes, second.signature).ok and store.stage("r2").ok, "prepare candidate before local payload damage")
	Store._write_bytes(store.release_directory("r2").path_join("data/levels.json"), "{}".to_utf8_buffer())
	var result: Dictionary = store.activate_data()
	_check(not result.ok and store.state_snapshot().active == "r1", "invalid candidate never replaces active data")
	_check(store.state_snapshot().pending.is_empty() and store.state_snapshot().rejected == "r2", "invalid candidate is quarantined rather than retried at every new round")
	var reopened := Store.new(path, "test", "runtime-v1", _public)
	var resumed: Dictionary = reopened.begin_cold_start()
	_check(resumed.ok and resumed.catalog.release_id() == "r1" and not resumed.trial, "candidate rejection survives restart without disturbing available data")
	_check("r2" in reopened.prune_unreferenced().removed, "quarantined candidate no longer pins corrupt cache files")


func _test_large_configuration() -> void:
	# 通用内容层不能依赖关卡字段；用较大的主题配置验证真实文件校验、解析和只读边界。
	var entries: Array = []
	for index in 12000:
		entries.append({"id": "theme_%d" % index, "label": "description_".repeat(8), "weight": index % 100})
	var release := _release("large-config", {"schema": 1, "themes": entries})
	var manifest: Dictionary = JSON.parse_string(release.bytes.get_string_from_utf8())
	manifest.files[0].id = "presentation/themes"
	release.bytes = JSON.stringify(manifest).to_utf8_buffer()
	release.signature = Crypto.new().sign(HashingContext.HASH_SHA256, Manifest.digest(release.bytes), _key)
	_check(manifest.files[0].bytes > 1024 * 1024, "configuration fixture exercises more than one MiB of JSON")
	var validator := Validation.new(func(id: String, value: Variant) -> Dictionary:
		return {"ok": id == "presentation/themes" and value is Dictionary and value.get("schema") == 1 and value.get("themes") is Array and value.themes.size() == 12000, "error": "theme_schema"}
	)
	var store := Store.new(_root.path_join("large-config-cache"), "test", "runtime-v1", _public)
	_check(store.install(release.source, release.bytes, release.signature, validator).ok and store.stage("large-config").ok, "arbitrary logical configuration ID passes injected product validator")
	var active: Dictionary = store.activate_data()
	_check(active.ok, "large configuration activates through the normal store")
	if not active.ok:
		return
	var loaded: Dictionary = active.catalog.read_json("presentation/themes")
	_check(loaded.ok and loaded.value.themes[11999].id == "theme_11999", "large configuration is consumed intact after signature and file verification")
	loaded.value.themes[11999].weight = -1
	_check(active.catalog.read_json("presentation/themes").value.themes[11999].weight == 99, "nested configuration mutations cannot change the published cache")
	_check(active.catalog.read_json("presentation/unknown").error == "unknown_content", "unknown content remains distinguishable from malformed configured data")


func _test_pack() -> void:
	var source := _root.path_join("raw.json")
	Store._write_bytes(source, "{\"ok\":true}".to_utf8_buffer())
	var invalid := _root.path_join("invalid.pck")
	var pack := PCKPacker.new()
	pack.pck_start(invalid)
	pack.add_file("res://scripts/injected.gd", source)
	pack.flush()
	_check(not RawPack.inspect(invalid, "test", "raw").ok, "pack rejects script/core path")
	var raw_release := _root.path_join("raw-release")
	DirAccess.make_dir_recursive_absolute(raw_release)
	var path := raw_release.path_join("assets.pck")
	var png := raw_release.path_join("pixel.png")
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.CORNFLOWER_BLUE)
	image.save_png(png)
	var wav := raw_release.path_join("tone.wav")
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = 8000
	var audio_bytes := PackedByteArray()
	audio_bytes.resize(80)
	stream.data = audio_bytes
	stream.save_to_wav(wav)
	pack = PCKPacker.new()
	pack.pck_start(path)
	pack.add_file("res://content/test/raw/example.json", source)
	pack.add_file("res://content/test/raw/pixel.png", png)
	pack.add_file("res://content/test/raw/tone.wav", wav)
	pack.flush()
	_check(RawPack.inspect(path, "test", "raw").ok, "raw PCK validates before mounting")
	var manifest := {"format": 1, "product": "test", "release": "raw", "runtime": "runtime-v1", "files": [{"id": "raw-assets", "path": "assets.pck", "kind": "raw_pck", "bytes": FileAccess.get_file_as_bytes(path).size(), "sha256": FileAccess.get_sha256(path)}]}
	var bytes := JSON.stringify(manifest).to_utf8_buffer()
	var signature := Crypto.new().sign(HashingContext.HASH_SHA256, Manifest.digest(bytes), _key)
	var store := Store.new(_root.path_join("raw-cache"), "test", "runtime-v1", _public)
	_check(store.install(raw_release, bytes, signature).ok and store.stage("raw").ok, "install raw resource release")
	_check(not store.activate_data().ok, "resource pack requires cold start")
	var candidate: Dictionary = store.begin_cold_start()
	_check(candidate.ok and candidate.trial, "cold-start trial mounts allowed pack")
	_check(FileAccess.get_file_as_string("res://content/test/raw/example.json") == "{\"ok\":true}", "mounted raw content is readable")
	_check(candidate.catalog.load_image("pixel.png").ok, "downloadable PCK image decodes without import cache")
	_check(candidate.catalog.load_audio("tone.wav").ok, "downloadable PCK audio decodes without import cache")
	_check(not candidate.catalog.raw_asset_path("../r1/example.json").ok, "catalog cannot escape its resource generation")
	_check(store.confirm_healthy("raw").ok, "confirm successful trial")


func _test_http(url: String) -> void:
	var node := Downloader.new()
	get_root().add_child(node)
	var public_key := FileAccess.get_file_as_string(_root.path_join("http-public.pem"))
	var store := Store.new(_root.path_join("http-cache"), "test", "runtime-v1", public_key)
	var blocked: Dictionary = await node.download_release(store, url, _root.path_join("downloads"))
	_check(not blocked.ok, "HTTP requires explicit localhost development opt-in")
	var downloaded: Dictionary = await node.download_release(store, url, _root.path_join("downloads"), null, true)
	_check(downloaded.ok, "localhost download + OpenSSL signature + install")
	if downloaded.ok:
		_check(store.stage("http").ok and store.activate_data().ok, "downloaded data activates")
	var missing: Dictionary = await node.download_release(store, url + "/missing", _root.path_join("downloads"), null, true)
	_check(not missing.ok and store.state_snapshot().active == "http", "HTTP failure preserves active release")
	node.queue_free()


func _release(release: String, value: Dictionary, directory_name: String = "") -> Dictionary:
	var source := _root.path_join(directory_name if not directory_name.is_empty() else release)
	DirAccess.make_dir_recursive_absolute(source.path_join("data"))
	var data := JSON.stringify(value).to_utf8_buffer()
	Store._write_bytes(source.path_join("data/levels.json"), data)
	var manifest := {"format": 1, "product": "test", "release": release, "runtime": "runtime-v1", "files": [{"id": "levels", "path": "data/levels.json", "kind": "json", "bytes": data.size(), "sha256": Manifest.digest(data).hex_encode()}]}
	var bytes := JSON.stringify(manifest).to_utf8_buffer()
	return {"source": source, "bytes": bytes, "signature": Crypto.new().sign(HashingContext.HASH_SHA256, Manifest.digest(bytes), _key)}


func _check(passed: bool, label: String) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		push_error("FAIL: " + label)
