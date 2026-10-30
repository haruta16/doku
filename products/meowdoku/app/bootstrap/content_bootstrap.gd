# 固定启动入口：在其他 Autoload 读取内容前选定本机可用版本；离线内置内容始终可用。
extends Node

const Validation = preload("res://scripts/framework/content/content_validation.gd")

const Store = preload("res://scripts/framework/content/content_store.gd")
const Downloader = preload("res://scripts/framework/content/content_downloader.gd")

signal catalog_changed(release: String)
signal update_finished(result: Dictionary)
signal update_progress(progress: Dictionary)

var _store: RefCounted
var _catalog: RefCounted
var _media_catalog: RefCounted
var _validator: Validation
var _trial: bool = false
var _generation: int = 0
var _last_result: Dictionary = {"ok": true, "builtin": true}
var _downloader: Node
var _restart_required: bool = false
var _updating: bool = false
var _cancel_requested: bool = false
var _maintenance: Dictionary = {}
var _initial_check_scheduled: bool = false


func _init() -> void:
	var validator_path: String = str(ProjectSettings.get_setting("content/validator_script", ""))
	if not validator_path.is_empty():
		var validator_script: Script = load(validator_path)
		if validator_script == null or not validator_script.has_method("validation"):
			_last_result = {"ok": false, "error": "content_validator_contract", "builtin": true}
			return
		var validation: Variant = validator_script.call("validation")
		if not validation is Validation:
			_last_result = {"ok": false, "error": "content_validator_contract", "builtin": true}
			return
		_validator = validation
	var key_path: String = str(ProjectSettings.get_setting("content/public_key_path", ""))
	if key_path.is_empty():
		return
	if not FileAccess.file_exists(key_path):
		_last_result = {"ok": false, "error": "public_key_missing", "builtin": true}
		return
	var key: String = FileAccess.get_file_as_string(key_path)
	var public_key := CryptoKey.new()
	if public_key.load_from_string(key, true) != OK:
		_last_result = {"ok": false, "error": "public_key", "builtin": true}
		return
	_store = Store.new("user://content", str(ProjectSettings.get_setting("content/product", "meowdoku")), runtime_id(), key)
	_maintenance["interrupted"] = _store.cleanup_interrupted()
	_last_result = _store.begin_cold_start(_validator)
	_restart_required = bool(_last_result.get("restart_required", false))
	if bool(_last_result.get("ok", false)):
		_catalog = _last_result.get("catalog")
		_media_catalog = _last_result.get("resource_catalog")
		_trial = bool(_last_result.get("trial", false))
		_generation += 1
		ContentContext.publish(_catalog, _media_catalog)
		_maintenance["pruned"] = _store.prune_unreferenced()


func _ready() -> void:
	if _restart_required:
		return
	_downloader = Downloader.new()
	add_child(_downloader)
	_downloader.progress_changed.connect(func(progress: Dictionary) -> void: update_progress.emit(progress))
	_schedule_initial_check()


func _schedule_initial_check() -> void:
	if _initial_check_scheduled or _trial or _restart_required or _store == null or _downloader == null:
		return
	var configured := not str(ProjectSettings.get_setting("content/channel_url", "")).is_empty() or not str(ProjectSettings.get_setting("content/release_url", "")).is_empty()
	if configured:
		_initial_check_scheduled = true
		check_for_updates.call_deferred()


func runtime_id() -> String:
	return str(ProjectSettings.get_setting("content/runtime_id", "godot-4.6.1-spine-4.2-data-v2"))


func generation() -> int:
	return _generation


func release_id() -> String:
	return _catalog.release_id() if _catalog != null else "builtin"


func diagnostics() -> Dictionary:
	return {
		"release": release_id(), "media_release": ContentContext.media_release_id(),
		"content_error": ContentContext.content_error(), "runtime": runtime_id(),
		"trial": _trial, "last_result": _last_result.duplicate(true),
		"configured": _store != null, "updating": _updating,
		"progress": _downloader.progress_snapshot() if _downloader != null else {},
		"maintenance": _maintenance.duplicate(true),
	}


# 返回无覆盖时的明确状态；调用方可以继续读取同一客户端内置内容。
func read_json(logical_id: String) -> Dictionary:
	if _catalog == null:
		return {"ok": false, "error": "unknown_content"}
	return _catalog.read_json(logical_id)


# 下载只登记候选；不在异步回调中切换进行中的玩法配置。
func download_and_stage(url: String, expected_release: String = "", expected_manifest_sha256: String = "") -> Dictionary:
	return await _run_update(url, false, expected_release, expected_manifest_sha256)


## 稳定频道优先；为空时兼容固定发布地址。两者均空不会联网。
func check_for_updates() -> Dictionary:
	var channel_url: String = str(ProjectSettings.get_setting("content/channel_url", ""))
	if not channel_url.is_empty():
		return await _run_update(channel_url, true)
	var release_url: String = str(ProjectSettings.get_setting("content/release_url", ""))
	if release_url.is_empty():
		return {"ok": false, "error": "update_source_not_configured"}
	var release: String = str(ProjectSettings.get_setting("content/release_id", ""))
	var manifest_sha256: String = str(ProjectSettings.get_setting("content/release_manifest_sha256", ""))
	var identity := Downloader.release_identity(release, manifest_sha256, true)
	if not identity.ok:
		_last_result = identity
		return identity
	return await _run_update(release_url, false, release, manifest_sha256)


func cancel_update() -> void:
	if _updating:
		_cancel_requested = true
		_downloader.cancel()


func _run_update(url: String, use_channel: bool, expected_release: String = "", expected_manifest_sha256: String = "") -> Dictionary:
	if not use_channel:
		var identity := Downloader.release_identity(expected_release, expected_manifest_sha256)
		if not identity.ok:
			return identity
	if _restart_required:
		return _last_result.duplicate(true)
	if _store == null or _downloader == null:
		return {"ok": false, "error": "content_not_configured"}
	if _updating:
		return {"ok": false, "error": "download_busy"}
	_updating = true
	_cancel_requested = false
	_maintenance["pruned"] = _store.prune_unreferenced()
	var local_allowed: bool = OS.is_debug_build() and bool(ProjectSettings.get_setting("content/allow_local_http", false))
	var result: Dictionary
	if use_channel:
		result = await _downloader.download_from_channel(_store, url, str(ProjectSettings.get_setting("content/channel", "stable")), "user://content/downloads", _validator, local_allowed)
	else:
		result = await _downloader.download_release(_store, url, "user://content/downloads", _validator, local_allowed, expected_release, expected_manifest_sha256)
	if _cancel_requested:
		result = {"ok": false, "error": "download_cancelled", "cancelled": true}
	if bool(result.get("ok", false)):
		var staged: Dictionary = _store.stage(str(result.release), _validator)
		if staged.ok:
			result.merge(staged, true)
			_maintenance["pruned"] = _store.prune_unreferenced()
		else:
			result = staged
	_last_result = result
	_updating = false
	update_finished.emit(result.duplicate(true))
	return result


# 只在新局入口调用。需要 PCK 的候选会返回 pack_requires_cold_start 并继续使用旧版本。
func activate_for_new_round() -> Dictionary:
	if _restart_required:
		return _last_result.duplicate(true)
	if _store == null or _trial:
		return {"ok": true, "release": release_id(), "changed": false}
	var state: Dictionary = _store.state_snapshot()
	if str(state.get("pending", "")).is_empty():
		return {"ok": true, "release": release_id(), "changed": false}
	var result: Dictionary = _store.activate_data(_validator)
	if bool(result.get("ok", false)):
		_catalog = result.catalog
		_generation += 1
		ContentContext.publish(_catalog, _media_catalog)
		catalog_changed.emit(release_id())
		# 完成进度通知可同步开启新局；下载结果此时已安装、尚未登记 pending。
		# 更新任务会在 stage 后清理，不能在这个交接间隙删掉新版本。
		if not _updating:
			_maintenance["pruned"] = _store.prune_unreferenced()
	_last_result = result
	return result


# 启动器完成关键入口初始化后确认；不把“挂载成功”当成完整启动成功。
func confirm_boot_healthy() -> Dictionary:
	if _restart_required:
		return _last_result.duplicate(true)
	if not _trial or _store == null:
		return {"ok": true}
	var result: Dictionary = _store.confirm_healthy(release_id())
	if bool(result.get("ok", false)):
		_trial = false
		if not _updating:
			_maintenance["pruned"] = _store.prune_unreferenced()
		_schedule_initial_check()
	_last_result = result
	return result
