## 独立内容夹具：签名频道、重试/取消、缓存命中与维护；没有产品 Autoload。
extends SceneTree

const FixtureGuard = preload("res://tools/validation/fixtures/content_fixture_guard.gd")

const Manifest = preload("res://scripts/framework/content/content_manifest.gd")
const Channel = preload("res://scripts/framework/content/content_channel.gd")
const Store = preload("res://scripts/framework/content/content_store.gd")
const Downloader = preload("res://scripts/framework/content/content_downloader.gd")
var _work: String
var _url: String
var _key: CryptoKey
var _public: String
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or not FixtureGuard.allows(args[0]):
		quit(2)
		return
	_work = args[0]
	_url = args[1]
	_key = CryptoKey.new()
	_key.load(_work.path_join("private.pem"))
	_public = _key.save_to_string(true)
	_test_channel_contract()
	_test_maintenance()
	await _test_http_delivery()
	print("CONTENT_UPDATE_TESTS checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_channel_contract() -> void:
	var bytes := FileAccess.get_file_as_bytes(_work.path_join("channel/channel.json"))
	var signature := FileAccess.get_file_as_bytes(_work.path_join("channel/channel.sig"))
	var checked := Channel.parse_verified(bytes, signature, _public, "test", "stable", "runtime-v1", true)
	_check(checked.ok and checked.value.release == "http", "publisher channel signature interoperates with Godot")
	_check(not Channel.parse_verified(bytes, signature, _public, "test", "stable", "runtime-v1").ok, "development HTTP is not accepted by production channel")
	_check(Channel.parse_verified(bytes, signature, _public, "test", "stable", "other", true).error == "channel_no_compatible_release", "unknown runtime is not assigned a release")
	_check(not Channel.parse_verified(bytes, signature, _public, "other", "stable", "runtime-v1", true).ok, "channel product must match")
	_check(not Channel.parse_verified(bytes, signature, _public, "test", "beta", "runtime-v1", true).ok, "channel name must match")
	var broken := signature.duplicate()
	broken[0] ^= 1
	_check(not Channel.parse_verified(bytes, broken, _public, "test", "stable", "runtime-v1", true).ok, "channel signature cannot be modified")
	var value: Dictionary = JSON.parse_string(bytes.get_string_from_utf8())
	var invalid := value.duplicate(true)
	invalid.revision = true
	_check(not Channel.validate(invalid, "test", "stable", "runtime-v1", true).ok, "channel rejects boolean revision")
	invalid = value.duplicate(true)
	invalid.targets.append(invalid.targets[0].duplicate(true))
	_check(not Channel.validate(invalid, "test", "stable", "runtime-v1", true).ok, "channel rejects ambiguous runtime targets")
	var multiple := value.duplicate(true)
	var other: Dictionary = multiple.targets[0].duplicate(true)
	other.runtime = "runtime-v2"
	other.release = "http-next"
	multiple.targets.append(other)
	_check(Channel.validate(multiple, "test", "stable", "runtime-v2", true).value.release == "http-next", "channel selects the exact compatible runtime target")
	for bad_url: String in ["http://example.org/releases/r1", "https://user@example.org/r1", "https://example.org/r1?key=x", "https:///r1", "https://example.org/r1\n"]:
		_check(not Channel.allowed_url(bad_url, true), "reject unsafe or unsupported URL")
	var store := Store.new(_work.path_join("channel-watermark"), "test", "runtime-v1", _public)
	_check(store.accept_channel(bytes, signature, "stable", true).ok, "channel acceptance persists watermark")
	var reopened := Store.new(_work.path_join("channel-watermark"), "test", "runtime-v1", _public)
	_check(reopened.state_snapshot().channel.revision == 2, "channel watermark survives restart")
	_check(reopened.accept_channel(bytes, signature, "stable", true).ok, "same signed channel is retryable")
	value.revision = 1
	_check(_accept(reopened, value).error == "channel_stale", "older signed channel cannot override accepted choice")
	value.revision = 2
	value.targets[0].url = _url + "/http-next"
	_check(_accept(reopened, value).error == "channel_revision_collision", "same revision cannot change content")
	value.revision = 3
	value.targets[0].release = "http-next"
	_check(_accept(reopened, value).ok, "higher revision may select a different release URL")
	value.revision = 4
	value.targets[0].release = "http"
	value.targets[0].url = _url + "/http"
	_check(_accept(reopened, value).ok, "higher channel revision may intentionally select an older release")
	var failed_path := _work.path_join("failed-channel-watermark")
	DirAccess.make_dir_recursive_absolute(failed_path.path_join("activation_1.json"))
	var failed := Store.new(failed_path, "test", "runtime-v1", _public)
	_check(not failed.accept_channel(bytes, signature, "stable", true).ok and failed.state_snapshot().channel.is_empty(), "channel write failure does not publish accepted revision")


func _test_maintenance() -> void:
	var path := _work.path_join("maintenance")
	var store := Store.new(path, "test", "runtime-v1", _public)
	DirAccess.make_dir_recursive_absolute(path.path_join("downloads/download_interrupted"))
	DirAccess.make_dir_recursive_absolute(path.path_join("downloads/unrelated"))
	DirAccess.make_dir_recursive_absolute(path.path_join("incoming_http"))
	Store._write_bytes(path.path_join("downloads/download_interrupted/part"), "half".to_utf8_buffer())
	_check(store.cleanup_interrupted().removed.size() == 2, "startup removes only owned temporary download/install directories")
	_check(DirAccess.dir_exists_absolute(path.path_join("downloads/unrelated")), "startup cleanup leaves unrelated entries intact")
	_check(store.begin_cold_start().ok and not store.cleanup_interrupted().ok, "temporary cleanup cannot run during active process")
	var manifest := FileAccess.get_file_as_bytes(_work.path_join("http/manifest.json"))
	var signature := FileAccess.get_file_as_bytes(_work.path_join("http/manifest.sig"))
	_check(store.install(_work.path_join("http"), manifest, signature).ok and store.stage("http").ok, "prepare referenced release")
	DirAccess.make_dir_recursive_absolute(path.path_join("releases/orphan"))
	var pruned: Dictionary = store.prune_unreferenced()
	_check(pruned.ok and "orphan" in pruned.removed and store.verify_release("http").ok, "maintenance keeps pending and removes orphan release")
	var legacy_path := _work.path_join("legacy-content-state")
	DirAccess.make_dir_recursive_absolute(legacy_path)
	var legacy := {"active": "", "pending": "", "last_good": "", "trial": "", "rejected": "", "media_active": "", "media_last_good": ""}
	var payload := JSON.stringify({"generation": 7, "state": legacy})
	Store._write_bytes(legacy_path.path_join("activation_1.json"), JSON.stringify({"payload": payload, "sha256": payload.sha256_text()}).to_utf8_buffer())
	var migrated := Store.new(legacy_path, "test", "runtime-v1", _public)
	_check(migrated._generation == 7 and migrated.state_snapshot().channel.is_empty(), "pre-channel metadata loads without resetting generation")


func _test_http_delivery() -> void:
	var downloader := Downloader.new()
	downloader.retry_delay_seconds = 0.01
	root.add_child(downloader)
	var path := _work.path_join("update-cache")
	var store := Store.new(path, "test", "runtime-v1", _public)
	var progress: Array = []
	downloader.progress_changed.connect(func(value: Dictionary) -> void: progress.append(value))
	var installed: Dictionary = await downloader.download_from_channel(store, _url + "/channel", "stable", path.path_join("downloads"), null, true)
	_check(installed.ok and installed.release == "http" and installed.channel_revision == 2, "stable channel discovers, verifies and installs release")
	_check(store.state_snapshot().pending.is_empty(), "downloader does not activate or stage by itself")
	_check(store.stage("http").ok and store.activate_data().ok, "caller stages and activates verified data")
	var payload_requests := _request_count("/http/data/levels.json")
	installed = await downloader.download_from_channel(store, _url + "/channel", "stable", path.path_join("downloads"), null, true)
	_check(installed.ok and installed.already_installed, "repeat check reports installed release")
	_check(_request_count("/http/data/levels.json") == payload_requests, "repeat check does not redownload payload")
	_check(store.stage("http").unchanged and store.state_snapshot().pending.is_empty(), "repeat staging does not manufacture a new pending/trial")
	_check(progress.any(func(value: Dictionary) -> bool: return value.phase == "downloading") and downloader.progress_snapshot().phase == "complete", "progress exposes transfer and terminal phases")
	await _test_fixed_identity(downloader, store, path)
	var flaky := Store.new(_work.path_join("flaky-cache"), "test", "runtime-v1", _public)
	var retried: Dictionary = await downloader.download_release(flaky, _url + "/flaky/http", _work.path_join("flaky-downloads"), null, true)
	_check(retried.ok and _request_count("/flaky/http/data/levels.json") == 3, "transient HTTP failures are retried with a finite attempt count")
	var missing: Dictionary = await downloader.download_release(store, _url + "/missing", path.path_join("downloads"), null, true)
	_check(not missing.ok and _request_count("/missing/manifest.json") == 1, "permanent 404 is not retried")
	var unavailable: Dictionary = await downloader.download_release(store, _url + "/unavailable", path.path_join("downloads"), null, true)
	_check(not unavailable.ok and unavailable.attempts == 3 and _request_count("/unavailable/manifest.json") == 3, "temporary service failure stops after configured limit")
	_check(store.state_snapshot().active == "http", "network failures keep active release")
	var source_channel: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_work.path_join("channel/channel.json")))
	source_channel.revision = 3
	source_channel.targets[0].manifest_sha256 = "0".repeat(64)
	_write_channel("bad-channel", source_channel)
	var mismatched: Dictionary = await downloader.download_from_channel(store, _url + "/bad-channel", "stable", path.path_join("downloads"), null, true)
	_check(mismatched.error == "channel_release_mismatch" and store.state_snapshot().active == "http", "signed channel target must match actual manifest bytes")
	var cancel_store := Store.new(_work.path_join("cancel-cache"), "test", "runtime-v1", _public)
	var cancel_callback := func(value: Dictionary) -> void:
		if value.phase == "downloading":
			create_timer(0.03).timeout.connect(downloader.cancel, CONNECT_ONE_SHOT)
	downloader.progress_changed.connect(cancel_callback)
	var cancelled: Dictionary = await downloader.download_release(cancel_store, _url + "/slow/http", _work.path_join("cancel-downloads"), null, true)
	downloader.progress_changed.disconnect(cancel_callback)
	_check(cancelled.get("cancelled", false) and not downloader.is_busy(), "active request can cancel without hanging await")
	_check(cancel_store.verify_release("http").error == "release_missing" and cancel_store.state_snapshot().pending.is_empty(), "cancelled payload cannot install or stage")
	_check(DirAccess.get_directories_at(_work.path_join("cancel-downloads")).is_empty(), "cancel removes partial work directory")
	var after_cancel: Dictionary = await downloader.download_release(cancel_store, _url + "/http", _work.path_join("cancel-downloads"), null, true)
	_check(after_cancel.ok, "downloader remains reusable after cancellation")
	var install_cancel_store := Store.new(_work.path_join("install-cancel-cache"), "test", "runtime-v1", _public)
	var install_cancel_callback := func(value: Dictionary) -> void:
		if value.phase == "installing":
			downloader.cancel()
	downloader.progress_changed.connect(install_cancel_callback)
	var cancelled_before_install: Dictionary = await downloader.download_release(install_cancel_store, _url + "/http", _work.path_join("install-cancel-downloads"), null, true)
	downloader.progress_changed.disconnect(install_cancel_callback)
	_check(cancelled_before_install.get("cancelled", false) and not downloader.is_busy(), "cancellation at installation boundary is honored")
	_check(install_cancel_store.verify_release("http").error == "release_missing" and DirAccess.get_directories_at(_work.path_join("install-cancel-downloads")).is_empty(), "cancel before installation leaves neither release nor staging files")
	var rejected_store := Store.new(_work.path_join("rejected-cache"), "test", "runtime-v1", _public)
	var rejected_state: Dictionary = rejected_store.state_snapshot()
	rejected_state.rejected = "http"
	rejected_store._commit_state(rejected_state)
	var rejected: Dictionary = await downloader.download_from_channel(rejected_store, _url + "/channel", "stable", _work.path_join("rejected-downloads"), null, true)
	_check(rejected.error == "release_rejected", "automatic checks do not retry rejected startup content forever")
	var requests_before_rejected := _request_count("/http/data/levels.json")
	rejected = await downloader.download_release(rejected_store, _url + "/http", _work.path_join("rejected-downloads"), null, true)
	_check(not rejected.ok and rejected.get("error") == "release_rejected", "fixed release URL also refuses rejected startup content")
	_check(_request_count("/http/data/levels.json") == requests_before_rejected and rejected_store.state_snapshot().pending.is_empty(), "rejected fixed URL cannot download payload or create another trial")
	downloader.queue_free()


func _test_fixed_identity(downloader: Node, store: RefCounted, path: String) -> void:
	var manifest_hash := FileAccess.get_sha256(_work.path_join("http/manifest.json"))
	var metadata_requests := _request_count("/http/manifest.json")
	for pair: Array in [["http", ""], ["", manifest_hash], ["../http", manifest_hash], ["http", "invalid"]]:
		var invalid: Dictionary = await downloader.download_release(store, _url + "/http", path.path_join("downloads"), null, true, pair[0], pair[1])
		_check(invalid.get("error") == "release_identity_invalid", "fixed identity requires a valid release and hash together")
	_check(_request_count("/http/manifest.json") == metadata_requests, "invalid fixed identity is rejected before network access")
	var payload_requests := _request_count("/http/data/levels.json")
	var wrong_release: Dictionary = await downloader.download_release(store, _url + "/http", path.path_join("downloads"), null, true, "expected-newer", manifest_hash)
	_check(wrong_release.get("error") == "release_identity_mismatch", "valid signed older release cannot replace the caller's pinned release")
	var wrong_hash: Dictionary = await downloader.download_release(store, _url + "/http", path.path_join("downloads"), null, true, "http", "0".repeat(64))
	_check(wrong_hash.get("error") == "release_identity_mismatch", "matching release ID still requires the pinned manifest bytes")
	_check(_request_count("/http/data/levels.json") == payload_requests and store.state_snapshot().active == "http" and store.state_snapshot().pending.is_empty(), "identity mismatch neither downloads payload nor changes active or pending content")
	var correct: Dictionary = await downloader.download_release(store, _url + "/http", path.path_join("downloads"), null, true, "http", manifest_hash)
	_check(correct.ok and correct.get("already_installed", false), "matching pinned identity retains verified cache reuse")


func _accept(store: RefCounted, value: Dictionary) -> Dictionary:
	var bytes := JSON.stringify(value).to_utf8_buffer()
	return store.accept_channel(bytes, Crypto.new().sign(HashingContext.HASH_SHA256, Manifest.digest(bytes), _key), "stable", true)


func _write_channel(name: String, value: Dictionary) -> void:
	var path := _work.path_join(name)
	DirAccess.make_dir_recursive_absolute(path)
	var bytes := JSON.stringify(value).to_utf8_buffer()
	Store._write_bytes(path.path_join("channel.json"), bytes)
	Store._write_bytes(path.path_join("channel.sig"), Crypto.new().sign(HashingContext.HASH_SHA256, Manifest.digest(bytes), _key))


func _request_count(path: String) -> int:
	return FileAccess.get_file_as_string(_work.path_join("http-requests.log")).split("\n").count(path)


func _check(passed: bool, label: String) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		push_error("TEST_FAILED: " + label)
