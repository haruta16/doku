## 内容交付的持久化目录。root 必须显式传入；不访问玩家存档或 GameState。
class_name ContentStore
extends RefCounted

const Validation = preload("res://scripts/framework/content/content_validation.gd")

const Manifest = preload("res://scripts/framework/content/content_manifest.gd")
const Catalog = preload("res://scripts/framework/content/content_catalog.gd")
const RawPack = preload("res://scripts/framework/content/content_raw_pack.gd")
const MediaMap = preload("res://scripts/framework/content/content_media_map.gd")
const Channel = preload("res://scripts/framework/content/content_channel.gd")
const DEFAULT_QUOTA := 768 * 1024 * 1024
const RELEASE_POINTERS := ["active", "pending", "last_good", "trial", "rejected", "media_active", "media_last_good"]

var _root: String
var _product: String
var _runtime: String
var _public_key: String
var _state: Dictionary
var _generation := 0
var _quota: int
var _boot_started := false
var _trial_started_release: String = ""
var _validator: Validation


func _init(root: String, product: String, runtime: String, public_key_pem: String, quota_bytes: int = DEFAULT_QUOTA) -> void:
	_root = root.trim_suffix("/")
	_product = product
	_runtime = runtime
	_public_key = public_key_pem
	_quota = quota_bytes
	_state = {"active": "", "pending": "", "last_good": "", "trial": "", "rejected": "", "media_active": "", "media_last_good": "", "channel": {}}
	_load_state()


func state_snapshot() -> Dictionary:
	return _state.duplicate(true)


func release_directory(release: String) -> String:
	return _root.path_join("releases").path_join(release)


func verify_manifest(bytes: PackedByteArray, signature: PackedByteArray) -> Dictionary:
	return Manifest.parse_verified(bytes, signature, _public_key, _product, _runtime)


## 在下载文件之前核对已安装的不可变版本；每次仍重验本地字节，不能仅凭目录存在跳过。
func check_installed(bytes: PackedByteArray, signature: PackedByteArray, validator: Validation = null) -> Dictionary:
	var parsed := verify_manifest(bytes, signature)
	if not parsed.ok:
		return parsed
	var release: String = parsed.value.release
	var directory := release_directory(release)
	if not DirAccess.dir_exists_absolute(directory):
		return {"ok": true, "installed": false, "release": release, "error": ""}
	if FileAccess.get_file_as_bytes(directory.path_join("manifest.json")) != bytes:
		return Manifest.failure("release_immutable")
	var verified := verify_release(release, validator)
	if not verified.ok:
		return verified
	return {"ok": true, "installed": true, "release": release, "error": ""}


## 先持久化频道水位，再开始下载；失败可重试同一签名版本，旧入口不能撤回新选择。
func accept_channel(bytes: PackedByteArray, signature: PackedByteArray, channel: String, allow_local_http: bool = false) -> Dictionary:
	var checked := Channel.parse_verified(bytes, signature, _public_key, _product, channel, _runtime, allow_local_http)
	if not checked.ok:
		return checked
	var previous: Dictionary = _state.channel
	if not previous.is_empty() and previous.id == channel:
		if checked.revision < int(previous.revision):
			return Manifest.failure("channel_stale")
		if checked.revision == int(previous.revision):
			if checked.sha256 != previous.sha256:
				return Manifest.failure("channel_revision_collision")
			return checked
	var next := _state.duplicate(true)
	next.channel = {"id": channel, "revision": checked.revision, "sha256": checked.sha256}
	var committed := _commit_state(next)
	return checked if committed.ok else committed


## 只在冷启动前调用：没有正在运行的下载任务，才允许删除上次中断留下的暂存目录。
func cleanup_interrupted() -> Dictionary:
	if _boot_started:
		return Manifest.failure("cleanup_requires_startup")
	var removed: Array[String] = []
	for location: Dictionary in [{"path": _root, "prefix": "incoming_"}, {"path": _root.path_join("downloads"), "prefix": "download_"}]:
		var directory := DirAccess.open(location.path)
		if directory == null:
			continue
		for name: String in directory.get_directories():
			if not name.begins_with(location.prefix) or directory.is_link(name):
				continue
			var path: String = str(location.path).path_join(name)
			_remove_tree(path)
			if DirAccess.dir_exists_absolute(path):
				return Manifest.failure("cache_cleanup")
			removed.append(name)
	return {"ok": true, "removed": removed, "error": ""}


## 源目录是下载暂存区或本地发布目录，manifest/sig 原始字节一并持久化以便每次启动重验。
func install(source: String, manifest_bytes: PackedByteArray, signature: PackedByteArray, validator: Validation = null) -> Dictionary:
	if validator != null:
		_validator = validator
	else:
		validator = _validator
	var parsed: Dictionary = Manifest.parse_verified(manifest_bytes, signature, _public_key, _product, _runtime)
	if not parsed.ok:
		return parsed
	var manifest: Dictionary = parsed.value
	var final_path := release_directory(manifest.release)
	if DirAccess.dir_exists_absolute(final_path):
		if FileAccess.get_file_as_bytes(final_path.path_join("manifest.json")) != manifest_bytes:
			return Manifest.failure("release_immutable")
		return verify_release(manifest.release, validator)
	var total := _directory_bytes(_root)
	for entry: Dictionary in manifest.files:
		total += int(entry.bytes)
	if total > _quota:
		return Manifest.failure("cache_quota")
	var checked := _verify_directory(source, manifest, validator)
	if not checked.ok:
		return checked
	var staging := _root.path_join("incoming_" + str(manifest.release))
	if DirAccess.dir_exists_absolute(staging):
		_remove_tree(staging)
	if DirAccess.make_dir_recursive_absolute(staging) != OK:
		return Manifest.failure("cache_directory")
	for entry: Dictionary in manifest.files:
		var target := staging.path_join(entry.path)
		if DirAccess.make_dir_recursive_absolute(target.get_base_dir()) != OK or DirAccess.copy_absolute(source.path_join(entry.path), target) != OK:
			_remove_tree(staging)
			return Manifest.failure("file_copy")
	if not _write_bytes(staging.path_join("manifest.json"), manifest_bytes) or not _write_bytes(staging.path_join("manifest.sig"), signature):
		_remove_tree(staging)
		return Manifest.failure("manifest_write")
	checked = _verify_directory(staging, manifest, validator)
	if not checked.ok:
		_remove_tree(staging)
		return checked
	if DirAccess.make_dir_recursive_absolute(final_path.get_base_dir()) != OK or DirAccess.rename_absolute(staging, final_path) != OK:
		return Manifest.failure("install_commit")
	return {"ok": true, "release": manifest.release, "error": ""}


func verify_release(release: String, validator: Validation = null) -> Dictionary:
	if validator != null:
		_validator = validator
	else:
		validator = _validator
	if not Manifest.identifier(release):
		return Manifest.failure("release_id")
	var directory := release_directory(release)
	if not FileAccess.file_exists(directory.path_join("manifest.json")) or not FileAccess.file_exists(directory.path_join("manifest.sig")):
		return Manifest.failure("release_missing")
	var parsed: Dictionary = Manifest.parse_verified(FileAccess.get_file_as_bytes(directory.path_join("manifest.json")), FileAccess.get_file_as_bytes(directory.path_join("manifest.sig")), _public_key, _product, _runtime)
	if not parsed.ok:
		return parsed
	if parsed.value.release != release:
		return Manifest.failure("release_mismatch")
	var checked := _verify_directory(directory, parsed.value, validator)
	if not checked.ok:
		return checked
	return {"ok": true, "release": release, "value": parsed.value, "catalog": Catalog.new(directory, parsed.value, validator), "error": ""}


func stage(release: String, validator: Validation = null) -> Dictionary:
	var checked := verify_release(release, validator)
	if not checked.ok:
		return checked
	if not _state.trial.is_empty():
		return Manifest.failure("trial_in_progress")
	if _state.pending == release or (_state.active == release and _state.pending.is_empty()):
		return {"ok": true, "release": release, "unchanged": true, "error": ""}
	var next := _state.duplicate(true)
	# 已活动的版本再次被选择时，只取消其他候选，不制造重复试运行/回退水位。
	next.pending = "" if next.active == release else release
	next.rejected = ""
	var committed := _commit_state(next)
	if committed.ok:
		committed["release"] = release
	return committed


## 纯 JSON 可以在局间激活；PCK 必须走 begin_cold_start + confirm_healthy。
func activate_data(validator: Validation = null) -> Dictionary:
	if not _state.trial.is_empty():
		return Manifest.failure("trial_in_progress")
	if _state.pending.is_empty():
		return Manifest.failure("no_pending")
	var checked := verify_release(_state.pending, validator)
	if not checked.ok:
		# 下载完成后文件仍可能损坏。保持已发布内容，并持久隔离坏候选；
		# 否则每次新局都会重验同一坏文件，也无法正常回收它占用的缓存。
		var rejected := _state.duplicate(true)
		rejected.rejected = rejected.pending
		rejected.pending = ""
		var recorded := _commit_state(rejected)
		if not recorded.ok:
			checked["state_error"] = recorded.error
		return checked
	for entry: Dictionary in checked.value.files:
		if entry.kind in ["raw_pck", "spine_pck"]:
			return Manifest.failure("pack_requires_cold_start")
	var next := _state.duplicate(true)
	next.last_good = next.active
	next.active = next.pending
	next.pending = ""
	var committed := _commit_state(next)
	if not committed.ok:
		return committed
	return checked


## 未完成试运行保守回退，并标注 trial_incomplete；不声称判断出了“资源导致崩溃”。
func begin_cold_start(validator: Validation = null) -> Dictionary:
	if _boot_started:
		return Manifest.failure("boot_already_started")
	if validator != null:
		_validator = validator
	_boot_started = true
	var next := _state.duplicate(true)
	if not next.trial.is_empty():
		next.rejected = next.trial
		next.trial = ""
		next.pending = ""
		var reverted := _commit_state(next)
		if not reverted.ok:
			return reverted
		return _active_or_fallback(validator, "trial_incomplete")
	if not next.pending.is_empty():
		var candidate := verify_release(next.pending, validator)
		if candidate.ok:
			next.trial = next.pending
			var recorded := _commit_state(next)
			if not recorded.ok:
				return recorded
			var mounted := _mount(candidate.value)
			if mounted.ok and _has_pack(candidate.value):
				mounted = candidate.catalog.validate_registered_media()
				if not mounted.ok:
					mounted["restart_required"] = true
			if mounted.ok and not _has_pack(candidate.value):
				mounted = _mount_current_media()
			if mounted.ok:
				if _has_pack(candidate.value):
					candidate["resource_catalog"] = candidate.catalog
				elif mounted.has("resource_catalog"):
					candidate["resource_catalog"] = mounted.resource_catalog
				candidate["trial"] = true
				_trial_started_release = str(candidate.value.release)
				return candidate
			# 挂载失败后不在当前进程尝试另一个包。
			return mounted
		next.rejected = next.pending
		next.pending = ""
		var rejected := _commit_state(next)
		if not rejected.ok:
			return rejected
	return _active_or_fallback(validator)


func confirm_healthy(release: String) -> Dictionary:
	if _state.trial != release or release.is_empty() or _trial_started_release != release:
		return Manifest.failure("trial_mismatch")
	var checked := verify_release(release)
	if not checked.ok:
		return checked
	var next := _state.duplicate(true)
	next.last_good = next.active
	next.active = release
	if _has_pack(checked.value):
		next.media_last_good = next.media_active
		next.media_active = release
	next.pending = ""
	next.trial = ""
	return _commit_state(next)


## 清理仅删除自有 release 目录；活动/待激活/回退/试运行与调用方仍引用的版本保留。
## 不删除当前进程已经挂载的 PCK 文件。
func prune_unreferenced(protected_releases: Array[String] = []) -> Dictionary:
	var retained := protected_releases.duplicate()
	for key: String in ["active", "pending", "last_good", "trial", "media_active", "media_last_good"]:
		retained.append(_state[key])
	var directory := DirAccess.open(_root.path_join("releases"))
	if directory == null:
		return {"ok": true, "removed": [], "error": ""}
	var removed: Array[String] = []
	for release: String in directory.get_directories():
		if release in retained or not Manifest.identifier(release) or directory.is_link(release):
			continue
		var path := release_directory(release)
		if RawPack.mounted_path().begins_with(path + "/"):
			continue
		_remove_tree(path)
		if DirAccess.dir_exists_absolute(path):
			return Manifest.failure("cache_cleanup")
		removed.append(release)
	return {"ok": true, "removed": removed, "error": ""}


func _active_or_fallback(validator: Validation, reason: String = "") -> Dictionary:
	for release: String in [_state.active, _state.last_good]:
		if release.is_empty():
			continue
		var checked := verify_release(release, validator)
		if not checked.ok:
			continue
		# 数据与表现资源可以来自不同的、各自经过签名校验的发布版本。
		var mounted := _mount_current_media()
		if not mounted.ok:
			return mounted
		if release != _state.active:
			var repaired := _state.duplicate(true)
			repaired.active = release
			repaired.last_good = ""
			var committed := _commit_state(repaired)
			if not committed.ok:
				committed["restart_required"] = not RawPack.mounted_path().is_empty()
				return committed
			if reason.is_empty():
				reason = "active_invalid"
		checked["fallback_reason"] = reason
		checked["trial"] = false
		if mounted.has("resource_catalog"):
			checked["resource_catalog"] = mounted.resource_catalog
		return checked
	if not _state.active.is_empty() or not _state.last_good.is_empty():
		var repaired := _state.duplicate(true)
		repaired.active = ""
		repaired.last_good = ""
		var committed := _commit_state(repaired)
		if not committed.ok:
			return committed
		if reason.is_empty():
			reason = "active_invalid"
	var builtin_result := {"ok": true, "builtin": true, "trial": false, "fallback_reason": reason, "error": ""}
	var media := _mount_current_media()
	if not media.ok:
		return media
	if media.has("resource_catalog"):
		builtin_result["resource_catalog"] = media.resource_catalog
	return builtin_result


func _mount_current_media() -> Dictionary:
	for release: String in [_state.media_active, _state.media_last_good]:
		if release.is_empty():
			continue
		var checked := verify_release(release)
		if not checked.ok or not _has_pack(checked.value):
			continue
		var mounted := _mount(checked.value)
		if not mounted.ok:
			return mounted
		var media_check: Dictionary = checked.catalog.validate_registered_media()
		if not media_check.ok:
			# 当前进程已经挂载，下一次进程才应用回退，不能在这里改装成“内置启动成功”。
			var rejected := _state.duplicate(true)
			rejected.rejected = release
			rejected.media_active = rejected.media_last_good if release == rejected.media_active else ""
			rejected.media_last_good = ""
			var recorded := _commit_state(rejected)
			if not recorded.ok:
				media_check["state_error"] = recorded.error
			media_check["restart_required"] = true
			return media_check
		if release != _state.media_active:
			var repaired := _state.duplicate(true)
			repaired.media_active = release
			repaired.media_last_good = ""
			var committed := _commit_state(repaired)
			if not committed.ok:
				committed["restart_required"] = true
				return committed
		return {"ok": true, "resource_catalog": checked.catalog, "error": ""}
	if not _state.media_active.is_empty() or not _state.media_last_good.is_empty():
		var repaired := _state.duplicate(true)
		repaired.media_active = ""
		repaired.media_last_good = ""
		var committed := _commit_state(repaired)
		if not committed.ok:
			return committed
	return {"ok": true, "error": ""}


static func _has_pack(manifest: Dictionary) -> bool:
	for entry: Dictionary in manifest.files:
		if entry.kind in ["raw_pck", "spine_pck"]:
			return true
	return false


func _mount(manifest: Dictionary) -> Dictionary:
	for entry: Dictionary in manifest.files:
		if entry.kind in ["raw_pck", "spine_pck"]:
			return RawPack.mount_once(release_directory(manifest.release).path_join(entry.path), _product, manifest.release, entry.kind)
	return {"ok": true, "error": ""}


func _verify_directory(directory: String, manifest: Dictionary, validator: Validation) -> Dictionary:
	var packed_paths: Dictionary = {}
	var has_media := false
	for entry: Dictionary in manifest.files:
		if entry.id == "media":
			has_media = true
		var checked: Dictionary = Manifest.verify_file(directory.path_join(entry.path), entry)
		if not checked.ok:
			return checked
		if entry.kind in ["raw_pck", "spine_pck"]:
			checked = RawPack.inspect(directory.path_join(entry.path), _product, manifest.release, entry.kind)
			if not checked.ok:
				return checked
			for resource: Dictionary in checked.value:
				packed_paths[resource.path] = true
	var catalog := Catalog.new(directory, manifest)
	var validated := catalog.validate_all(validator)
	if not validated.ok:
		return validated
	if has_media:
		var mapping: Dictionary = catalog.read_json("media")
		if not mapping.ok or not MediaMap.validate(mapping.value):
			return Manifest.failure("media_schema")
		var prefix := "res://content/%s/%s/" % [_product, manifest.release]
		for kind: String in mapping.value:
			for relative: String in mapping.value[kind].values():
				if not packed_paths.has(prefix + relative) and not (kind == "textures" and packed_paths.has(prefix + relative + ".import")):
					return Manifest.failure("media_dependency")
	return {"ok": true, "error": ""}


func _commit_state(next: Dictionary) -> Dictionary:
	if DirAccess.make_dir_recursive_absolute(_root) != OK:
		return Manifest.failure("state_directory")
	var revision := _generation + 1
	var payload := JSON.stringify({"generation": revision, "state": next})
	var bytes := JSON.stringify({"payload": payload, "sha256": payload.sha256_text()}).to_utf8_buffer()
	var target := _root.path_join("activation_%d.json" % (revision % 2))
	if not _write_bytes(target + ".tmp", bytes):
		return Manifest.failure("state_write")
	if FileAccess.get_file_as_bytes(target + ".tmp") != bytes or DirAccess.rename_absolute(target + ".tmp", target) != OK:
		return Manifest.failure("state_commit")
	_state = next.duplicate(true)
	_generation = revision
	return {"ok": true, "error": ""}


func _load_state() -> void:
	for slot in 2:
		var path := _root.path_join("activation_%d.json" % slot)
		if not FileAccess.file_exists(path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary or not Manifest.exact_keys(parsed, ["payload", "sha256"]) or not parsed.payload is String or not parsed.sha256 is String:
			continue
		if parsed.payload.sha256_text() != parsed.sha256:
			continue
		var payload: Variant = JSON.parse_string(parsed.payload)
		if not payload is Dictionary or not Manifest.exact_keys(payload, ["generation", "state"]) or not Manifest.integer(payload.generation) or int(payload.generation) <= _generation or not payload.state is Dictionary:
			continue
		# v1 元数据没有 channel；仅为它补空水位，不改动原内容指针。
		var pointer_keys: Array = RELEASE_POINTERS.duplicate()
		if payload.state.has("channel"):
			pointer_keys.append("channel")
		if not Manifest.exact_keys(payload.state, pointer_keys):
			continue
		var valid := true
		for pointer: String in RELEASE_POINTERS:
			var value: Variant = payload.state[pointer]
			if not value is String or (not value.is_empty() and not Manifest.identifier(value)):
				valid = false
		var channel: Variant = payload.state.get("channel", {})
		if not channel is Dictionary or not _valid_channel_state(channel):
			valid = false
		if valid:
			_generation = int(payload.generation)
			_state = payload.state.duplicate(true)
			_state["channel"] = channel.duplicate(true)


static func _valid_channel_state(channel: Dictionary) -> bool:
	if channel.is_empty():
		return true
	if not Manifest.exact_keys(channel, ["id", "revision", "sha256"]):
		return false
	return (
		channel.id is String and Manifest.identifier(channel.id)
		and Manifest.integer(channel.revision) and channel.revision >= 1
		and channel.revision <= Channel.MAX_REVISION
		and channel.sha256 is String and Manifest.is_sha256(channel.sha256)
	)


static func _write_bytes(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	var success := file.get_error() == OK
	file.close()
	return success


static func _directory_bytes(path: String) -> int:
	var directory := DirAccess.open(path)
	if directory == null:
		return 0
	var total := 0
	for filename: String in directory.get_files():
		var file := FileAccess.open(path.path_join(filename), FileAccess.READ)
		if file != null:
			total += file.get_length()
	for dirname: String in directory.get_directories():
		if not directory.is_link(dirname):
			total += _directory_bytes(path.path_join(dirname))
	return total


static func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for filename: String in directory.get_files():
		directory.remove(filename)
	for dirname: String in directory.get_directories():
		if directory.is_link(dirname):
			directory.remove(dirname)
		else:
			_remove_tree(path.path_join(dirname))
	DirAccess.remove_absolute(path)
