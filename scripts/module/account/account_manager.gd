## 账号流程的总协调器：把原生认证、云存档同步、进度选择和页面跳转串成状态机。
## 登录成功并不等于进度已同步；观察 flow_state_changed 与最终结果信号，才能区分两个阶段。

extends Node

enum State {
	IDLE,
	CHECKING_NET,
	AUTHING,
	SYNCING,
	DONE,
	FAILED,
}

const KIND_OK: String = "ok"

const KIND_NETWORK: String = "network"

const KIND_CANCELLED: String = "cancelled"

const KIND_FAIL: String = "fail"

const _CLOUD_BLOCK_CORE: String = "core"

const CHOICE_LOCAL: String = "local"

const CHOICE_CLOUD: String = "cloud"

signal login_flow_finished(ok: bool, channel: String, kind: String, code: int)

signal logout_flow_finished(ok: bool, kind: String, code: int)

signal delete_flow_finished(ok: bool, kind: String, code: int)

signal flow_state_changed(busy: bool)

signal progress_select_required

signal account_deleted_notice_required

signal page_reload_requested

signal reload_presentation_requested

signal reload_route_requested

var _state: int = State.IDLE

var _channel: String = ""

const _REASON_STARTUP: String = "startup"
const _REASON_LOGIN: String = "login"
const _REASON_LOGOUT_GUEST: String = "logout_guest"
const _REASON_SESSION_RESTORED: String = "session_restored"
const _REASON_PROGRESS_CHOICE: String = "progress_choice"

const _REASON_LEVEL_WON: String = "level_won"
const _REASON_LEVEL_FAILED: String = "level_failed"
const _REASON_PROFILE_SAVE: String = "profile_save"

const _LEVEL_SYNC_INTERVAL: int = 10

var _pending_conflict: ProgressConflict = null

var _levels_since_sync: int = 0

var _credential_recovery_tried: bool = false

var _pending_account_deleted: bool = false

var _guest_reset_tried: bool = false

var _startup_sync_started: bool = false

var _startup_settled: bool = false

var _pending_result: AccountFlowResult = null

var _splash_presenting: bool = false

var _account_data: AccountData = AccountData.new()


## 读入账号流程记录，接好认证与存档信号，并向同步管理器注册进度冲突裁决。
## 没有原生认证能力时直接结束启动等待，保留本地游戏运行路径。
func _ready() -> void:
	_account_data.load_data()

	GameState.all_data_reset.connect(_account_data.clear)

	AuthManager.login_expired.connect(_on_login_expired)

	GameState.level_settled.connect(_on_level_settled)
	ProfileService.profile_saved.connect(_on_profile_saved)

	DataSyncRegistry.set_late_handler(_on_savable_late_registered)
	DataSyncManager.set_merge_arbiter(_arbitrate_merge)

	if not AuthManager.is_available():
		_startup_settled = true
		print("[Account (AccountManager)] 无原生 auth 插件（editor / 无插件包），跳过启动登录与同步")
		return
	AuthManager.session_ready.connect(_on_session_ready)

	AuthManager.session_login_failed.connect(_on_session_login_failed)
	AuthManager.account_switched.connect(_on_account_switched)

	DataSyncManager.account_credential_invalid.connect(_on_account_credential_invalid)

	if AuthManager.is_auth_gate_ready():
		AuthManager.start_bootstrap()
	else:
		AuthManager.auth_gate_ready.connect(AuthManager.start_bootstrap, CONNECT_ONE_SHOT)


## 取出并清空一次性结果；页面反复显示时不会重复弹出同一次登录结果。
func take_pending_result() -> AccountFlowResult:
	var result: AccountFlowResult = _pending_result
	_pending_result = null
	return result


func is_login_feature_enabled() -> bool:
	return ABTestManager.app_login.is_login_enabled()


func is_delete_account_enabled() -> bool:
	return true


func is_progress_select_enabled() -> bool:
	return ABTestManager.app_login.is_progress_select_enabled()


func get_progress_conflict() -> ProgressConflict:
	return _pending_conflict


## 重新采样本地进度并与已下载的云端快照比较；两者一致时取消冲突，否则更新建议项。
func refresh_progress_conflict() -> ProgressConflict:
	if _pending_conflict == null:
		return null
	var before: ProgressSnapshot = _pending_conflict.local
	var local_level: int = GameState.get_current_level()
	var local_items: int = _local_items()
	_pending_conflict = conflict_of(_pending_conflict.cloud, local_level, local_items)
	if _pending_conflict == null:
		print(
			(
				"[Account (AccountManager)] 进度选择：本地已追平云端(lv=%d items=%d)，消掉未决态"
				% [local_level, local_items]
			)
		)
	elif (
		_pending_conflict.local.level != before.level
		or _pending_conflict.local.items != before.items
	):
		print(
			(
				"[Account (AccountManager)] 进度选择：本地进度已变，刷新摘要 lv %d→%d items %d→%d suggested=%s"
				% [
					before.level,
					_pending_conflict.local.level,
					before.items,
					_pending_conflict.local.items,
					_pending_conflict.suggested
				]
			)
		)
	return _pending_conflict


func is_progress_select_pending() -> bool:
	return _pending_conflict != null


## 检查待处理冲突和玩家选择；通过后开始带过渡页的异步合并，选择云端时仍要求在线。
func apply_progress_choice(choice: String) -> bool:
	if _pending_conflict == null:
		push_warning("[Account (AccountManager)] 应用进度选择: 当前无待决冲突，忽略")
		return false
	if choice != CHOICE_LOCAL and choice != CHOICE_CLOUD:
		push_error("[Account (AccountManager)] 应用进度选择: 非法选择 %s" % choice)
		return false

	if choice == CHOICE_CLOUD and not UniKitManager.is_online():
		print("[Account (AccountManager)] 应用进度选择：选云端但无网络，保留未决态、不受理")
		return false

	_pending_conflict = null

	if not _splash_presenting:
		_present_splash()
	_apply_progress_choice_async(choice)
	return true


## 按玩家选择强制执行本地或云端同步，完成后通过页面重载重新建立一致的界面状态。
func _apply_progress_choice_async(choice: String) -> void:
	var force: String = choice
	_set_state(State.SYNCING)
	await _run_sync(_REASON_PROGRESS_CHOICE, force)
	print("[Account (AccountManager)] 进度选择 %s → force=%s" % [choice, force])
	_set_state(State.IDLE)

	if not _channel.is_empty():
		_pending_result = AccountFlowResult.login_success(_channel)
	else:
		print("[Account (AccountManager)] 无刚登录渠道（登出侧 / 冷启动补弹），只软重载、不弹登录成功弹窗")

	_route_after_splash()


func _present_splash() -> void:
	_splash_presenting = true
	print("[Account (AccountManager)] 请求软重载·前半段（splash 表现，本层遮罩让位）")
	reload_presentation_requested.emit()
	_render_progress_mask()


func _route_after_splash() -> void:
	_splash_presenting = false
	print("[Account (AccountManager)] 请求软重载·后半段（走完 splash 表现并路由）")
	reload_route_requested.emit()


func is_busy() -> bool:
	return _state == State.CHECKING_NET or _state == State.AUTHING or _state == State.SYNCING


func is_logged_in() -> bool:
	return not get_signed_in_channel().is_empty()


func get_signed_in_channel() -> String:
	return _account_data.get_signed_in_channel()


func current_channel() -> String:
	return AuthManager.get_provider_id()


func available_channels() -> Array:
	return AccountDefine.available_channels()


## 登录入口：拦截并发操作，检查渠道与网络，等待认证，再同步进度并处理可能出现的选择页。
func start_login(channel: String) -> void:
	if is_busy():
		print("[Account (AccountManager)] 发起登录被忽略：流程进行中 state=%s" % _state_name(_state))
		return
	if not AccountDefine.is_valid_channel(channel):
		push_error("[Account (AccountManager)] 发起登录: 非法渠道 %s" % channel)
		_finish_login(false, channel, KIND_FAIL, AuthManager.ERR_PARAM)
		return
	print("[Account (AccountManager)] 发起登录 ch=%s" % channel)
	_channel = channel

	_set_state(State.CHECKING_NET)

	if not UniKitManager.is_online():
		_finish_login(false, channel, KIND_NETWORK, AuthManager.ERR_NETWORK)
		return

	_set_state(State.AUTHING)
	var login: AuthFlowOutcome = await _await_login(channel)
	if not login.ok:
		_finish_login(false, channel, _classify(login.code), login.code)
		return

	_set_state(State.SYNCING)
	await _sync_after_login()

	_finish_login(true, channel, KIND_OK, 0, _pending_conflict != null)


## 退出当前账号，清除该账号的同步基线与手动登录记录，再建立游客会话。
## 退出流程不直接等价于清空游戏进度；后续游客同步仍可能需要进度选择。
func start_logout() -> void:
	if is_busy():
		print("[Account (AccountManager)] 发起登出被忽略：流程进行中 state=%s" % _state_name(_state))
		return

	_channel = current_channel()
	print("[Account (AccountManager)] 发起登出 会话渠道=%s" % _channel)

	_set_state(State.CHECKING_NET)

	if not UniKitManager.is_online():
		print("[Account (AccountManager)] 登出前置检查：无网络，不执行登出")
		_set_state(State.FAILED)
		logout_flow_finished.emit(false, KIND_NETWORK, AuthManager.ERR_NETWORK)
		_set_state(State.IDLE)
		return

	_set_state(State.AUTHING)
	var outcome := AuthFlowOutcome.new()

	var cb := func(code: int, _msg: String) -> void:
		if code == 0:
			DataSyncManager.reset_for_account_switch()
		outcome.done = true
		outcome.ok = code == 0
		outcome.code = code
	AuthManager.logout_completed.connect(cb, CONNECT_ONE_SHOT)
	AuthManager.logout()
	await _wait_flag(outcome, _WAIT_OP_MS)
	if AuthManager.logout_completed.is_connected(cb):
		AuthManager.logout_completed.disconnect(cb)
	var ok: bool = outcome.ok
	if ok:
		_account_data.clear_signed_in_channel()
		print("[Account (AccountManager)] 已清空本机手动登录记录,登录页恢复为未登录态")

		_discard_progress_select("登出")

		_channel = ""

	if not ok:
		_set_state(State.FAILED)

		logout_flow_finished.emit(false, _classify(outcome.code), outcome.code)
		_set_state(State.IDLE)
		return

	_set_state(State.SYNCING)
	logout_flow_finished.emit(true, KIND_OK, 0)

	if not await _relogin_guest():
		print("[Account (AccountManager)] 登出后 guest 重登失败（本地档照常玩，下次冷启动补）")
		_set_state(State.IDLE)
		page_reload_requested.emit()
		return

	await _run_sync(_REASON_LOGOUT_GUEST, "", true)
	if _pending_conflict != null:
		_set_state(State.IDLE)
		progress_select_required.emit()
		return

	_set_state(State.IDLE)
	page_reload_requested.emit()


## 临时接管认证完成信号并等待游客登录；结束后断开临时回调并恢复原会话监听，避免重复同步。
func _relogin_guest() -> bool:
	var had_session_handler: bool = AuthManager.session_ready.is_connected(_on_session_ready)
	if had_session_handler:
		AuthManager.session_ready.disconnect(_on_session_ready)
	var outcome := AuthFlowOutcome.new()
	var on_ok := func(_user_profile: AccountProfile) -> void: outcome.finish_ok()
	var on_fail := func(code: int, msg: String) -> void: outcome.finish_fail(code, msg)
	AuthManager.session_ready.connect(on_ok, CONNECT_ONE_SHOT)
	AuthManager.session_login_failed.connect(on_fail, CONNECT_ONE_SHOT)
	AuthManager.login_as_guest()

	await _wait_flag(outcome, _WAIT_OP_MS)
	if AuthManager.session_ready.is_connected(on_ok):
		AuthManager.session_ready.disconnect(on_ok)
	if AuthManager.session_login_failed.is_connected(on_fail):
		AuthManager.session_login_failed.disconnect(on_fail)
	if had_session_handler:
		AuthManager.session_ready.connect(_on_session_ready)
	return outcome.ok


## 执行原生删号并等待回调；仅在确认删除成功后进入本地清理与游客重建。
func start_delete_account() -> void:
	if is_busy():
		print("[Account (AccountManager)] 发起删号被忽略：流程进行中 state=%s" % _state_name(_state))
		return

	_channel = current_channel()
	print("[Account (AccountManager)] 发起删号 会话渠道=%s" % _channel)

	_set_state(State.CHECKING_NET)

	if not UniKitManager.is_online():
		print("[Account (AccountManager)] 删号前置检查：无网络，不执行删号")
		_set_state(State.FAILED)
		delete_flow_finished.emit(false, KIND_NETWORK, AuthManager.ERR_NETWORK)
		_set_state(State.IDLE)
		return

	_set_state(State.AUTHING)
	var outcome := AuthFlowOutcome.new()
	outcome.code = AuthManager.ERR_UNKNOWN_GUARD
	var cb := func(deleted: bool, code: int, msg: String) -> void:
		if deleted:
			outcome.finish_ok()
			outcome.code = code
		else:
			outcome.finish_fail(code, msg)
	AuthManager.delete_account_completed.connect(cb, CONNECT_ONE_SHOT)
	AuthManager.delete_account()

	await _wait_flag(outcome, _WAIT_OP_MS)
	if AuthManager.delete_account_completed.is_connected(cb):
		AuthManager.delete_account_completed.disconnect(cb)
	var ok: bool = outcome.ok
	if ok:
		await _wipe_local_and_recreate_guest()

	if ok:
		_account_data.clear()

		_discard_progress_select("删号")

	var code: int = outcome.code
	_set_state(State.DONE if ok else State.FAILED)
	print(
		"[Account (AccountManager)] 删号流程结束 ok=%s kind=%s code=%d" % [str(ok), _classify(code), code]
	)
	delete_flow_finished.emit(ok, _classify(code), code)

	_set_state(State.IDLE)


## 删除账号成功后的破坏性步骤：重置本地游戏数据和云同步基线，再创建新的游客会话。
func _wipe_local_and_recreate_guest() -> void:
	GameState.reset_for_account_delete()
	DataSyncManager.reset_for_account_switch()
	print("[Account (AccountManager)] 删号：本地已清 + 同步基线已清，开始建新匿名账号")
	var outcome := AuthFlowOutcome.new()

	var ok_cb := func(user_profile: AccountProfile) -> void:
		outcome.finish_ok()
		outcome.user_id = user_profile.user_id
	var fail_cb := func(code: int, msg: String) -> void: outcome.finish_fail(code, msg)
	AuthManager.session_ready.connect(ok_cb)
	AuthManager.session_login_failed.connect(fail_cb)
	AuthManager.login_as_guest()
	await _wait_flag(outcome, _WAIT_OP_MS)
	if AuthManager.session_ready.is_connected(ok_cb):
		AuthManager.session_ready.disconnect(ok_cb)
	if AuthManager.session_login_failed.is_connected(fail_cb):
		AuthManager.session_login_failed.disconnect(fail_cb)
	print(
		"[Account (AccountManager)] 删号后新匿名账号: user_id=%s code=%d" % [outcome.user_id, outcome.code]
	)


func restart_app() -> void:
	print("[Account (AccountManager)] 删号后重载（原 set_restart_on_exit 在移动端无效，改走软重载）")
	page_reload_requested.emit()


## 累计关卡结算次数，到批次门槛才请求同步，避免每一局都上传一次存档。
func _on_level_settled(won: bool) -> void:
	_levels_since_sync += 1
	if _levels_since_sync < _LEVEL_SYNC_INTERVAL:
		print(
			(
				"[Account (AccountManager)] 关卡结算 %d/%d，攒着不同步"
				% [_levels_since_sync, _LEVEL_SYNC_INTERVAL]
			)
		)
		return
	_levels_since_sync = 0
	DataSyncManager.request_sync(_REASON_LEVEL_WON if won else _REASON_LEVEL_FAILED)


## 资料保存后请求云同步；实际是否发送由同步开关、登录与网络状态共同决定。
func _on_profile_saved() -> void:
	DataSyncManager.request_sync(_REASON_PROFILE_SAVE)


func _on_savable_late_registered(savable: Object) -> void:
	var id: String = savable.cloud_save_id() if savable.has_method("cloud_save_id") else "?"
	DataSyncManager.request_sync("late_savable_%s" % id)


## 让依赖账号初始化的流程等待启动阶段结束；启动完成与是否成功登录是不同状态。
func await_startup_settled(timeout_ms: int) -> bool:
	var started_ms: int = Time.get_ticks_msec()
	while not _startup_settled and Time.get_ticks_msec() - started_ms < timeout_ms:
		await get_tree().process_frame
	return _startup_settled


func _on_account_credential_invalid(kind: String, code: int) -> void:
	if kind == DataSyncManager.CREDENTIAL_ACCOUNT_DELETED:
		if _pending_account_deleted:
			print("[Account (AccountManager)] 账号已销毁(code=%d)：告知弹窗已挂起，跳过" % code)
			return
	elif _credential_recovery_tried:
		print("[Account (AccountManager)] 凭证失效(%s code=%d)：本会话已试过恢复，跳过" % [kind, code])
		return
	if is_busy():
		print("[Account (AccountManager)] 凭证失效(%s code=%d)：有流程在跑，本次不插手" % [kind, code])
		return

	if kind == DataSyncManager.CREDENTIAL_SESSION_EXPIRED and not AuthManager.is_guest_login():
		push_warning(
			(
				"[Account (AccountManager)] 凭证失效(%s code=%d)：当前是三方会话，不静默切回匿名账号；等 SDK 会话失效回调 / 下次冷启动"
				% [kind, code]
			)
		)
		return
	_credential_recovery_tried = true
	if kind == DataSyncManager.CREDENTIAL_ACCOUNT_DELETED:
		DataSyncManager.reset_for_account_switch()

		_pending_account_deleted = true
		print("[Account (AccountManager)] 账号已销毁(code=%d)：同步基线已清，挂起告知弹窗，等玩家确认后清本地 + 退出进程" % code)
		account_deleted_notice_required.emit()
		return
	print(
		(
			"[Account (AccountManager)] 凭证失效(%s code=%d)：重新 guest 登录（同 device_id，服务端会给一个可用的匿名账号）"
			% [kind, code]
		)
	)

	AuthManager.login_as_guest()


func has_pending_account_deleted() -> bool:
	return _pending_account_deleted


func confirm_account_deleted() -> void:
	if not _pending_account_deleted:
		push_warning("[Account (AccountManager)] 确认账号已销毁：无待处理的告知，忽略")
		return
	_pending_account_deleted = false

	UniKitManager.log_exception(
		"Account deleted by server, wiping local save",
		(
			"signed_in=%s session=%s level=%d"
			% [get_signed_in_channel(), current_channel(), GameState.get_current_level()]
		)
	)

	GameState.reset_for_account_delete()
	DataSyncManager.reset_for_account_switch()

	_account_data.clear()

	_account_data.set_guest_reset_pending(true)
	await _drop_sdk_session()
	print("[Account (AccountManager)] 账号已销毁：本地已清，退出进程（下次冷启动落到新的匿名账号）")

	if OS.has_feature("ios"):
		OS.kill(OS.get_process_id())
	else:
		get_tree().quit()


func _drop_sdk_session() -> void:
	if not AuthManager.is_available():
		return
	var outcome := AuthFlowOutcome.new()
	var cb := func(code: int, _msg: String) -> void:
		outcome.done = true
		outcome.ok = code == 0
		outcome.code = code
	AuthManager.logout_completed.connect(cb, CONNECT_ONE_SHOT)
	AuthManager.logout()
	await _wait_flag(outcome, _WAIT_SESSION_DROP_MS)
	if AuthManager.logout_completed.is_connected(cb):
		AuthManager.logout_completed.disconnect(cb)
	print(
		(
			"[Account (AccountManager)] 账号已销毁：清 SDK 本地会话 ok=%s code=%d（失败则由下次冷启动的兜底切匿名）"
			% [str(outcome.ok), outcome.code]
		)
	)


func _on_session_ready(_user_profile: AccountProfile) -> void:
	if _account_data.is_guest_reset_pending():
		if not AuthManager.is_guest_login():
			if _guest_reset_tried:
				push_warning(
					(
						"[Account (AccountManager)] 切回匿名后会话仍非匿名(provider=%s)，本会话放弃同步（本地档已是清空态）"
						% AuthManager.get_provider_id()
					)
				)
				_startup_settled = true
				return
			_guest_reset_tried = true
			push_warning(
				(
					"[Account (AccountManager)] 已销毁账号的会话被 SDK 恢复出来(provider=%s)：不拿它同步，切回匿名账号"
					% AuthManager.get_provider_id()
				)
			)
			AuthManager.login_as_guest()
			return
		_account_data.set_guest_reset_pending(false)
		print("[Account (AccountManager)] 已落到匿名会话，作废「切回匿名」待办")
	if not _startup_sync_started:
		_startup_sync_started = true
		await _run_sync(_REASON_STARTUP, "", true)

		if _pending_conflict != null:
			progress_select_required.emit()
		_startup_settled = true
		return
	await _run_sync(_REASON_SESSION_RESTORED, "")


func _on_session_login_failed(code: int, msg: String) -> void:
	push_warning("[Account (AccountManager)] 会话登录失败 code=%d msg=%s，用本地存档" % [code, msg])
	_startup_settled = true


func _on_account_switched(user_profile: AccountProfile, _is_new_user: bool) -> void:
	DataSyncManager.reset_for_account_switch()

	var provider: String = user_profile.provider_id
	if AccountDefine.is_valid_channel(provider):
		_account_data.set_signed_in_channel(provider)
	else:
		push_warning("[Account (AccountManager)] 换号对账：provider_id='%s' 不是已知渠道，跳过写入显示判据" % provider)
	print("[Account (AccountManager)] 换号对账：已清同步基线，signed_in_channel='%s'" % get_signed_in_channel())


func _sync_after_login() -> void:
	DataSyncManager.reset_for_account_switch()
	await _run_sync(_REASON_LOGIN, "", true)


## 在云存档覆盖本地之前决定默认合并、明确选择或暂缓；已有待处理冲突时不会再次开一个选择流程。
func _arbitrate_merge(reason: String, cloud_root: Dictionary, allow_prompt: bool) -> String:
	if _pending_account_deleted:
		print("[Account (AccountManager)] 合并裁决(%s)：账号已销毁待确认，挂起本次合并与上传" % reason)
		return DataSyncManager.VERDICT_DEFER

	if _pending_conflict != null:
		print("[Account (AccountManager)] 合并裁决(%s)：进度选择未决，挂起本次合并" % reason)
		return DataSyncManager.VERDICT_DEFER

	if not allow_prompt:
		return DataSyncManager.VERDICT_DEFAULT

	if not is_progress_select_enabled():
		return DataSyncManager.VERDICT_DEFAULT
	var conflict: ProgressConflict = _build_conflict(cloud_root)
	if conflict == null:
		return DataSyncManager.VERDICT_DEFAULT
	_pending_conflict = conflict
	print(
		(
			"[Account (AccountManager)] 合并裁决(%s)：检测到进度冲突，等玩家选择 local=%d/%d cloud=%d/%d suggested=%s"
			% [
				reason,
				conflict.local.level,
				conflict.local.items,
				conflict.cloud.level,
				conflict.cloud.items,
				conflict.suggested
			]
		)
	)
	return DataSyncManager.VERDICT_DEFER


func _discard_progress_select(reason: String) -> void:
	if _pending_conflict == null:
		return
	print("[Account (AccountManager)] 作废未决的进度选择(%s)" % reason)
	_pending_conflict = null


func _run_sync(reason: String, force: String, allow_prompt: bool = false) -> void:
	if not DataSyncManager.is_sync_enabled():
		print("[Account (AccountManager)] 同步未启用，跳过 %s 同步" % reason)
		return
	var result: SyncResult = await DataSyncManager.sync_once(reason, force, allow_prompt)
	print(
		(
			"[Account (AccountManager)] %s 同步: force='%s' ok=%s changed=%s reason=%s"
			% [reason, force, str(result.ok), str(result.changed), result.reason]
		)
	)


func _build_conflict(cloud_root: Dictionary) -> ProgressConflict:
	var cloud_core: Dictionary = cloud_root.get(_CLOUD_BLOCK_CORE, {})
	if cloud_core.is_empty():
		return null
	var local_level: int = GameState.get_current_level()
	var local_items: int = _local_items()
	var cloud_level: int = int(cloud_core.get("current_level", 0))
	var cloud_items: int = _cloud_items(cloud_core)
	print(
		(
			"[Account (AccountManager)] 探冲突：本地 lv=%d items=%d / 云端 lv=%d items=%d → %s"
			% [
				local_level,
				local_items,
				cloud_level,
				cloud_items,
				"一致(不弹)" if (cloud_level == local_level and cloud_items == local_items) else "有差异"
			]
		)
	)
	return conflict_of(ProgressSnapshot.of(cloud_level, cloud_items), local_level, local_items)


## 比较两份关卡与道具快照；只有确实不同才构造冲突，建议项优先采用关卡进度更高的一侧。
static func conflict_of(
	cloud: ProgressSnapshot, local_level: int, local_items: int
) -> ProgressConflict:
	if cloud == null:
		return null
	if cloud.level == local_level and cloud.items == local_items:
		return null

	return ProgressConflict.of(
		ProgressSnapshot.of(local_level, local_items),
		cloud,
		CHOICE_CLOUD if cloud.level > local_level else CHOICE_LOCAL
	)


func _local_items() -> int:
	var total: int = 0
	for kind: String in GameState.CLOUD_TOOL_KINDS:
		total += GameState.get_tool_count(kind)
	return total


func _cloud_items(cloud_core: Dictionary) -> int:
	var total: int = 0
	for kind: String in GameState.CLOUD_TOOL_KINDS:
		total += int(cloud_core.get("tool_" + kind, GameState.get_tool_count(kind)))
	return total


func _classify(code: int) -> String:
	if code == 0:
		return KIND_OK
	if code == AuthManager.ERR_NETWORK:
		return KIND_NETWORK
	if code == AuthManager.ERR_USER_CANCELED:
		return KIND_CANCELLED
	return KIND_FAIL


func _finish_login(
	ok: bool, channel: String, kind: String, code: int, defer_reload: bool = false
) -> void:
	if ok:
		_account_data.set_signed_in_channel(channel)

	_set_state(State.DONE if ok else State.FAILED)
	print(
		(
			"[Account (AccountManager)] 登录流程结束 ok=%s channel=%s kind=%s code=%d"
			% [str(ok), channel, kind, code]
		)
	)
	login_flow_finished.emit(ok, channel, kind, code)

	_set_state(State.IDLE)

	if ok and not defer_reload:
		_pending_result = AccountFlowResult.login_success(channel, code)
		page_reload_requested.emit()


func _await_login(channel: String) -> AuthFlowOutcome:
	var outcome := AuthFlowOutcome.new()
	var ok_cb := func(user_profile: AccountProfile, _is_new_user: bool) -> void:
		outcome.finish_ok()
		outcome.user_id = user_profile.user_id
	var fail_cb := func(code: int, msg: String) -> void: outcome.finish_fail(code, msg)
	AuthManager.account_switched.connect(ok_cb)

	AuthManager.account_switch_failed.connect(fail_cb)
	AuthManager.login_with(channel)

	await _wait_flag(outcome, _WAIT_LOGIN_MS)
	if AuthManager.account_switched.is_connected(ok_cb):
		AuthManager.account_switched.disconnect(ok_cb)
	if AuthManager.account_switch_failed.is_connected(fail_cb):
		AuthManager.account_switch_failed.disconnect(fail_cb)
	return outcome


const _WAIT_LOGIN_MS: int = 195000

const _WAIT_OP_MS: int = 30000

const _WAIT_SESSION_DROP_MS: int = 3000


func _wait_flag(outcome: AuthFlowOutcome, timeout_ms: int) -> void:
	var started_ms: int = Time.get_ticks_msec()
	while not outcome.done and Time.get_ticks_msec() - started_ms < timeout_ms:
		await get_tree().process_frame
	if not outcome.done:
		push_warning("[Account (AccountManager)] 等待流程结果超时(%dms)，按失败收尾" % timeout_ms)

		outcome.finish_fail(AuthManager.ERR_TIMEOUT, "wait timeout")


func _render_progress_mask() -> void:
	if is_busy() and not _splash_presenting:
		UIManager.show_ui(UiName.COMMON_LOADING)
	else:
		UIManager.hide_ui(UiName.COMMON_LOADING)


func _state_name(state: int) -> String:
	return State.keys()[state] if state >= 0 and state < State.size() else "UNKNOWN(%d)" % state


## 统一更新流程状态与交互遮罩，并发送状态变化，避免页面各自猜测当前是否忙碌。
func _set_state(next: int) -> void:
	if _state == next:
		return
	var was_busy: bool = is_busy()

	print("[Account (AccountManager)] 状态 %s → %s" % [_state_name(_state), _state_name(next)])
	_state = next
	var now_busy: bool = is_busy()
	if was_busy != now_busy:
		flow_state_changed.emit(now_busy)

	_render_progress_mask()


func _on_login_expired() -> void:
	if is_busy():
		print("[Account (AccountManager)] 会话失效：有流程在跑(%s)，交由该流程自己收尾" % _state_name(_state))
		return
	print("[Account (AccountManager)] 会话失效 → 状态机复位")
	_set_state(State.IDLE)
