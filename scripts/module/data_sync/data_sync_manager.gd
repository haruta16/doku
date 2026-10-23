## 云存档同步状态机：取得认证令牌，比较云端版本，合并各模块数据，再决定是否上传。
## 同一时刻只运行一条同步流程，后来的请求会合并为待办；账号切换时必须清除旧账号同步基线。

extends Node

signal data_sync_completed(changed: bool)

signal data_sync_failed(reason: String)

signal account_credential_invalid(kind: String, code: int)

const CREDENTIAL_ACCOUNT_DELETED: String = "account_deleted"

const CREDENTIAL_SESSION_EXPIRED: String = "session_expired"

const _DATA_SYNC_STATE_PATH: String = "user://data_sync_state.cfg"

const _SYNC_CHEAT_PATH: String = "user://data_sync_cheat.cfg"

const _MAX_CONFLICT_RETRY: int = 3

const _WAIT_INFLIGHT_TIMEOUT_MS: int = 30000

var _http: HttpClient

var _api: DataSyncApi

var _syncing: bool = false

var _pending_request: SyncRequest = null

var _cloud_sync_code: int = -1

var _last_cloud_root: Dictionary = {}

var _sync_enabled: bool = true

const _SRC_REL: String = "rel 恒开"

const _SRC_CHEAT: String = "cheat 覆盖"

const _SRC_BUILD_DEFAULT: String = "dev/pre 默认开"

const _SRC_EDITOR_DEFAULT: String = "editor 默认关"

var _sync_enabled_source: String = ""


func _ready() -> void:
	_http = HttpClient.new()
	_http.name = "HttpClient"
	add_child(_http)
	_api = DataSyncApi.new(_http)
	_load_cloud_snapshot()

	_sync_enabled = _resolve_sync_enabled()
	var open_hint: String = "" if _sync_enabled else "，cheat datasync on 可开"
	print(
		(
			"[Account (DataSyncManager)] sync_enabled=%s 来源=%s%s (rel=%s)"
			% [str(_sync_enabled), _sync_enabled_source, open_hint, str(OS.has_feature("rel"))]
		)
	)


## 解析运行环境与调试配置决定是否启用同步；学习编辑器环境与正式 rel 特性使用不同默认值。
func _resolve_sync_enabled() -> bool:
	if OS.has_feature("rel"):
		_sync_enabled_source = _SRC_REL
		return true
	var cfg := ConfigFile.new()
	if cfg.load(_SYNC_CHEAT_PATH) == OK and cfg.has_section_key("cheat", "sync_enabled"):
		_sync_enabled_source = _SRC_CHEAT
		return bool(cfg.get_value("cheat", "sync_enabled", false))
	if OS.has_feature("editor"):
		_sync_enabled_source = _SRC_EDITOR_DEFAULT
		return false
	_sync_enabled_source = _SRC_BUILD_DEFAULT
	return true


func set_sync_enabled(enabled: bool) -> void:
	_sync_enabled = enabled

	_sync_enabled_source = _SRC_CHEAT
	var cfg := ConfigFile.new()

	cfg.load(_SYNC_CHEAT_PATH)
	cfg.set_value("cheat", "sync_enabled", enabled)
	cfg.save(_SYNC_CHEAT_PATH)


func is_sync_enabled() -> bool:
	return _sync_enabled


const VERDICT_DEFAULT: String = ""
const VERDICT_LOCAL: String = "local"
const VERDICT_CLOUD: String = "cloud"
const VERDICT_DEFER: String = "defer"

const _VERDICTS: Array[String] = [VERDICT_DEFAULT, VERDICT_LOCAL, VERDICT_CLOUD, VERDICT_DEFER]

var _merge_arbiter: Callable = Callable()


func set_merge_arbiter(arbiter: Callable) -> void:
	_merge_arbiter = arbiter


func _ask_merge_arbiter(reason: String, cloud_root: Dictionary, allow_prompt: bool) -> String:
	if not _merge_arbiter.is_valid():
		return VERDICT_DEFAULT
	var answer: Variant = _merge_arbiter.call(reason, cloud_root, allow_prompt)
	if not (answer is String) or not _VERDICTS.has(answer):
		push_warning("[Account (DataSyncManager)] 合并裁决返回非法值（%s），按默认策略合并" % str(answer))
		return VERDICT_DEFAULT
	var verdict: String = answer
	if not verdict.is_empty():
		print("[Account (DataSyncManager)] 合并裁决（%s）→ %s" % [reason, verdict])
	return verdict


## 清除内存和磁盘中的云端版本基线；换账号后必须重新下载，不能沿用上一个账号的 sync_code。
func reset_for_account_switch() -> void:
	_cloud_sync_code = -1
	_last_cloud_root = {}
	if FileAccess.file_exists(_DATA_SYNC_STATE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_DATA_SYNC_STATE_PATH))
	print("[Account (DataSyncManager)] 已按账号切换重置: sync_code=-1，透传基线已清")


## 不等待结果的同步入口；若已有请求在执行，将这次请求合并为一个后续待办。
func request_sync(reason: String, force: String = "") -> void:
	if not _sync_enabled:
		print("[Account (DataSyncManager)] 同步已关闭（%s），跳过: %s" % [_sync_enabled_source, reason])
		return
	if _syncing:
		_merge_pending(reason, force)
		return
	_sync(reason, force, false)


## 需要结果时使用的异步入口；先限时等待在途同步，再返回这次 SyncResult。
func sync_once(reason: String, force: String = "", allow_prompt: bool = false) -> SyncResult:
	if not _sync_enabled:
		print("[Account (DataSyncManager)] 同步已关闭（%s），跳过: %s" % [_sync_enabled_source, reason])
		return SyncResult.fail("disabled")
	var wait_start: int = Time.get_ticks_msec()
	while _syncing:
		if Time.get_ticks_msec() - wait_start >= _WAIT_INFLIGHT_TIMEOUT_MS:
			push_warning(
				(
					"[Account (DataSyncManager)] 等在飞同步超时(%dms)，按失败返回: %s"
					% [_WAIT_INFLIGHT_TIMEOUT_MS, reason]
				)
			)
			return SyncResult.fail("inflight_timeout")
		await get_tree().process_frame
	return await _sync(reason, force, allow_prompt)


## 只保留一个待办同步；强制选择请求可以替换普通请求，避免连续事件造成上传队列膨胀。
func _merge_pending(reason: String, force: String) -> void:
	if _pending_request == null:
		_pending_request = SyncRequest.of(reason, force)
		return

	if not force.is_empty() and _pending_request.force.is_empty():
		_pending_request = SyncRequest.of(reason, force)


func _take_pending() -> SyncRequest:
	var request: SyncRequest = _pending_request
	_pending_request = null
	return request


## 包住一次完整同步，释放在途标记并发出结果信号；合并的待办在下一轮延迟启动，避免递归重入。
func _sync(reason: String, force: String = "", allow_prompt: bool = false) -> SyncResult:
	_syncing = true
	var result: SyncResult = await _do_sync(reason, force, allow_prompt)
	_syncing = false
	var ok: bool = result.ok

	if ok:
		DataSyncRegistry.mark_synced()
	if ok:
		data_sync_completed.emit(result.changed)
	else:
		data_sync_failed.emit(result.reason)
	print(
		(
			"[Account (DataSyncManager)] 同步结束（%s）: ok=%s reason=%s changed=%s sync_code=%d first_upload=%s"
			% [
				reason,
				str(ok),
				result.reason,
				str(result.changed),
				result.sync_code,
				str(result.is_first_upload)
			]
		)
	)

	var pending: SyncRequest = _take_pending()
	if pending != null:
		request_sync.call_deferred("coalesced:%s" % pending.reason, pending.force)
	return result


## 检查登录与网络，获取令牌并比较云端版本；合并之后仅在需要时上传本地根数据。
func _do_sync(reason: String, force: String = "", allow_prompt: bool = false) -> SyncResult:
	if not AuthManager.is_logged_in():
		push_warning("[Account (DataSyncManager)] 跳过同步（%s）——未登录，不发起同步（等会话失效回调 / 下次冷启动）" % reason)
		return SyncResult.fail("not_logged_in")

	if not UniKitManager.is_online():
		print("[Account (DataSyncManager)] 跳过同步（%s）——无网络，靠下次事件重试" % reason)
		return SyncResult.fail("offline")

	var ids: PackedStringArray = []
	for savable in DataSyncRegistry.all():
		ids.append(savable.cloud_save_id())
	if ids.is_empty():
		push_warning("[Account (DataSyncManager)] 同步时 DataSyncRegistry 为空，无任何 savable，请检查注册时序")
	else:
		print(
			(
				"[Account (DataSyncManager)] 同步开始（%s），savables=%s，cached_sync_code=%d"
				% [reason, str(ids), _cloud_sync_code]
			)
		)

	var bearer: String = await _fetch_bearer(false)
	if bearer.is_empty():
		return SyncResult.fail("no_access_token")

	var cloud_code: int = 0
	var first_upload: bool = false
	var changed: bool = false

	if _cloud_sync_code >= 0:
		var meta: ApiResponse = await _api.fetch_meta(bearer)
		if meta.code in [ApiConfig.CODE_ACCESS_TOKEN_INVALID, ApiConfig.CODE_ACCESS_TOKEN_EXPIRED]:
			bearer = await _fetch_bearer(true)
			if bearer.is_empty():
				return SyncResult.fail("token_refresh")
			meta = await _api.fetch_meta(bearer)
		if not meta.ok:
			return SyncResult.fail("meta_net")
		var meta_code: int = meta.code
		print(
			(
				"[Account (DataSyncManager)] meta 探测 code=%d（cached_sync_code=%d）"
				% [meta_code, _cloud_sync_code]
			)
		)

		if meta_code == ApiConfig.CODE_NO_SAVE:
			first_upload = true
		elif meta_code == ApiConfig.CODE_OK:
			var meta_data: Dictionary = meta.data
			var meta_sync_code: int = int(meta_data.get("sync_code", 0))
			if meta_sync_code == _cloud_sync_code:
				cloud_code = _cloud_sync_code
			else:
				var merged: DownloadMergeResult = await _download_and_merge_cloud(
					bearer, reason, force, allow_prompt
				)
				bearer = merged.bearer
				if not merged.ok:
					return SyncResult.fail(merged.reason)
				first_upload = merged.first_upload
				if not first_upload:
					cloud_code = merged.sync_code
					changed = true
		elif _report_credential_invalid(meta_code):
			return SyncResult.fail("credential_%d" % meta_code)
		else:
			return SyncResult.fail("meta_code_%d" % meta_code)
	else:
		var merged: DownloadMergeResult = await _download_and_merge_cloud(
			bearer, reason, force, allow_prompt
		)
		bearer = merged.bearer
		if not merged.ok:
			return SyncResult.fail(merged.reason)
		first_upload = merged.first_upload
		if not first_upload:
			cloud_code = merged.sync_code
			changed = true

	if first_upload and not _last_cloud_root.is_empty():
		print("[Account (DataSyncManager)] 服务端无档，清掉旧的透传基线再建档")
		_last_cloud_root = {}

	if not first_upload and _canon_root(_build_root()) == _canon_root(_last_cloud_root):
		print("[Account (DataSyncManager)] 本地与服务端快照一致，跳过上传（sync_code=%d）" % cloud_code)
		_cloud_sync_code = cloud_code
		_save_cloud_snapshot()
		return SyncResult.success(cloud_code, changed, false)

	var final_code: int = await _upload(bearer, cloud_code + 1)
	if final_code < 0:
		return SyncResult.fail("upload")
	_cloud_sync_code = final_code
	_save_cloud_snapshot()
	return SyncResult.success(final_code, changed, first_upload)


## 带云端版本号上传；遇到版本冲突按有限次数重新下载合并，避免直接覆盖他处的新进度。
func _upload(bearer: String, sync_code: int) -> int:
	var code: int = sync_code
	for _attempt in _MAX_CONFLICT_RETRY:
		var root: Dictionary = _build_root()
		print("[Account (DataSyncManager)] 上传数据（sync_code=%d）: %s" % [code, JSON.stringify(root)])
		var res: ApiResponse = await _api.upload(
			bearer, JSON.stringify(root), DataSyncConfig.SCHEMA_VERSION, code
		)
		if not res.ok:
			return -1
		var upload_code: int = res.code
		print("[Account (DataSyncManager)] 上传尝试 sync_code=%d → code=%d" % [code, upload_code])
		if upload_code == ApiConfig.CODE_OK:
			_last_cloud_root = root
			return code
		if upload_code == ApiConfig.CODE_SYNC_CODE_TOO_LOW:
			var retry_download: ApiResponse = await _api.download(bearer)
			if not retry_download.is_ok():
				return -1
			var dl_data: Dictionary = retry_download.data

			if not _merge_cloud_json(str(dl_data.get("game_data", ""))):
				return -1
			var new_cloud_code: int = int(dl_data.get("sync_code", code))
			_cloud_sync_code = new_cloud_code
			code = new_cloud_code + 1
			continue
		if (
			upload_code
			in [ApiConfig.CODE_ACCESS_TOKEN_INVALID, ApiConfig.CODE_ACCESS_TOKEN_EXPIRED]
		):
			bearer = await _fetch_bearer(true)
			if bearer.is_empty():
				return -1
			continue
		if upload_code in [ApiConfig.CODE_SIGN_INVALID, ApiConfig.CODE_TIMESTAMP_EXPIRED]:
			push_warning(
				(
					"[Account (DataSyncManager)] 上传 code=%d（签名/时间戳被拒，服务端时间校正后仍失败，疑 sign_secret/后端策略），放弃上传"
					% upload_code
				)
			)
			return -1
		if _report_credential_invalid(upload_code):
			return -1

		push_warning("[Account (DataSyncManager)] 上传 code=%d，放弃上传" % upload_code)
		return -1
	return -1


## 执行下载并处理令牌失效后的刷新重试；返回实际使用的 bearer 供后续上传继续使用。
func _send_download_request(bearer: String) -> DownloadResponse:
	var api_result: ApiResponse = await _api.download(bearer)
	if (
		api_result.code
		in [ApiConfig.CODE_ACCESS_TOKEN_INVALID, ApiConfig.CODE_ACCESS_TOKEN_EXPIRED]
	):
		bearer = await _fetch_bearer(true)
		if bearer.is_empty():
			return DownloadResponse.fail("token_refresh")
		api_result = await _api.download(bearer)
	if not api_result.ok:
		return DownloadResponse.fail("download_net", bearer)
	return DownloadResponse.success(api_result, bearer)


## 区分没有云存档、下载失败与有数据可合并；进度裁决可能使本次流程暂缓，等待玩家选择。
func _download_and_merge_cloud(
	bearer: String, reason: String, force: String = "", allow_prompt: bool = false
) -> DownloadMergeResult:
	var fetched: DownloadResponse = await _send_download_request(bearer)
	bearer = fetched.bearer
	if not fetched.ok:
		return DownloadMergeResult.fail(fetched.reason, bearer)
	var api_result: ApiResponse = fetched.api_result
	var download_code: int = api_result.code
	print("[Account (DataSyncManager)] 下载 code=%d" % download_code)
	if download_code == ApiConfig.CODE_NO_SAVE:
		return DownloadMergeResult.first_time(bearer)
	if download_code == ApiConfig.CODE_OK:
		var payload: Dictionary = api_result.data
		print("[Account (DataSyncManager)] 下载到远端 game_data: %s" % str(payload.get("game_data", "")))
		var save: CloudSaveResult = _parse_cloud_data(api_result)
		if not save.ok:
			return DownloadMergeResult.fail("download_parse", bearer)

		var cloud_root: Dictionary = save.root if save.has_cloud_data else {}
		var applied_force: String = force
		if applied_force.is_empty():
			var verdict: String = _ask_merge_arbiter(reason, cloud_root, allow_prompt)
			if verdict == VERDICT_DEFER:
				print("[Account (DataSyncManager)] 合并被裁决者挂起（%s），本次不合并、不上传" % reason)
				return DownloadMergeResult.fail("deferred_by_arbiter", bearer)
			applied_force = verdict
		_merge_cloud_root(cloud_root, applied_force)
		var cloud_sync_code: int = int(payload.get("sync_code", 0))
		_cloud_sync_code = cloud_sync_code
		return DownloadMergeResult.merged(cloud_sync_code, bearer)
	if _report_credential_invalid(download_code):
		return DownloadMergeResult.fail("credential_%d" % download_code, bearer)
	return DownloadMergeResult.fail("download_code_%d" % download_code, bearer)


## 收集已注册模块的导出结果组成云存档根对象，同时保留需要透传的云端数据。
func _build_root() -> Dictionary:
	var root: Dictionary = _last_cloud_root.duplicate(true)
	for savable in DataSyncRegistry.all():
		var id: String = savable.cloud_save_id()
		var base: Variant = root.get(id, {})
		var block: Dictionary = base.duplicate(true) if base is Dictionary else {}
		if savable.has_method("retired_cloud_keys"):
			var retired: Array[String] = savable.retired_cloud_keys()
			for key: String in retired:
				block.erase(key)
		block.merge(savable.export_cloud_data(), true)
		root[id] = block
	return root


func _merge_cloud_json(game_data: String, force: String = "") -> bool:
	print(
		"[Account (DataSyncManager)] 下载到远端 game_data（len=%d）: %s" % [game_data.length(), game_data]
	)
	var root: Dictionary = {}
	if not game_data.is_empty():
		var parsed: Variant = JSON.parse_string(game_data)
		if not (parsed is Dictionary):
			push_warning(
				(
					"[Account (DataSyncManager)] 远端 game_data 解析失败（body 损坏？len=%d），跳过合并、保留快照基线"
					% game_data.length()
				)
			)
			return false
		root = parsed
	_merge_cloud_root(root, force)
	return true


## 根据合并上下文逐个调用已注册模块；具体字段如何覆盖由各模块的 merge_cloud_data 实现。
func _merge_cloud_root(root: Dictionary, force: String = "") -> void:
	_last_cloud_root = root.duplicate(true)
	var ctx: MergeContext = _build_merge_ctx(root, force)
	for savable in DataSyncRegistry.all():
		var blob: Variant = root.get(savable.cloud_save_id(), {})
		if blob is Dictionary:
			savable.merge_cloud_data(blob, ctx)
	var merged_local: Dictionary = {}
	for savable in DataSyncRegistry.all():
		merged_local[savable.cloud_save_id()] = savable.export_cloud_data()
	print(
		(
			"[Account (DataSyncManager)] 合并后的本地存档（use_cloud=%s by_player_choice=%s）: %s"
			% [str(ctx.use_cloud), str(ctx.by_player_choice), JSON.stringify(merged_local)]
		)
	)


func _parse_cloud_data(api_result: ApiResponse) -> CloudSaveResult:
	if not api_result.ok:
		return CloudSaveResult.fail("download_net")
	if api_result.code == ApiConfig.CODE_NO_SAVE:
		return CloudSaveResult.empty()
	if api_result.code != ApiConfig.CODE_OK:
		return CloudSaveResult.fail("download_code_%d" % api_result.code)
	var payload: Dictionary = api_result.data
	var body: String = str(payload.get("game_data", ""))
	var cloud_sync_code: int = int(payload.get("sync_code", -1))
	if body.is_empty():
		return CloudSaveResult.empty(cloud_sync_code)
	var parsed: Variant = JSON.parse_string(body)
	if not (parsed is Dictionary):
		push_warning(
			"[Account (DataSyncManager)] 领取云端存档: 远端 game_data 解析失败（len=%d）" % body.length()
		)
		return CloudSaveResult.fail("parse_fail")
	return CloudSaveResult.loaded(parsed, cloud_sync_code)


func _build_merge_ctx(root: Dictionary, force: String = "") -> MergeContext:
	if force == "cloud":
		return MergeContext.from_player_choice(true)
	if force == "local":
		return MergeContext.from_player_choice(false)
	for savable in DataSyncRegistry.all():
		if savable.has_method("is_cloud_ahead"):
			var blob: Variant = root.get(savable.cloud_save_id(), {})
			return MergeContext.from_comparison(
				bool(savable.is_cloud_ahead(blob if blob is Dictionary else {}))
			)

	return MergeContext.from_comparison(false)


func _report_credential_invalid(code: int) -> bool:
	var kind: String = ""
	if code == ApiConfig.CODE_ACCOUNT_DELETED:
		kind = CREDENTIAL_ACCOUNT_DELETED
	elif (
		code == ApiConfig.CODE_REFRESH_TOKEN_INVALID or code == ApiConfig.CODE_REFRESH_TOKEN_EXPIRED
	):
		kind = CREDENTIAL_SESSION_EXPIRED
	if kind.is_empty():
		return false
	push_warning(
		"[Account (DataSyncManager)] 服务端判本会话账号/凭证失效 code=%d（%s），放弃本次同步、交账号层恢复" % [code, kind]
	)
	account_credential_invalid.emit(kind, code)
	return true


func _fetch_bearer(force_refresh: bool) -> String:
	var token_res: AccessTokenResult = await AuthManager.request_access_token(force_refresh)
	var code: int = token_res.code
	if code != 0:
		print(
			(
				"[Account (DataSyncManager)] 取 access token 失败: logged_in=%s code=%d force_refresh=%s"
				% [str(AuthManager.is_logged_in()), code, str(force_refresh)]
			)
		)
		return ""
	return token_res.token


func _canon_root(root: Dictionary) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(root)))


func _parse_game_data(game_data: String) -> Dictionary:
	if game_data.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(game_data)
	return parsed if parsed is Dictionary else {}


func _load_cloud_snapshot() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_DATA_SYNC_STATE_PATH) == OK:
		var raw: String = str(cfg.get_value("sync", "remote_root", ""))
		_last_cloud_root = _parse_game_data(raw)


## 持久化云端版本和基线，下次启动可先查询元信息，减少无变化时的完整下载。
func _save_cloud_snapshot() -> void:
	var cfg := ConfigFile.new()
	cfg.load(_DATA_SYNC_STATE_PATH)
	cfg.set_value("sync", "remote_root", JSON.stringify(_last_cloud_root))
	cfg.save(_DATA_SYNC_STATE_PATH)
