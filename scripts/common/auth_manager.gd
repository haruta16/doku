## 账号业务入口：等待统计标识就绪后启动认证，串行执行登录操作并统一结果信号。
extends Node

signal session_ready(user_profile: AccountProfile)

signal account_switched(user_profile: AccountProfile, is_new_user: bool)

signal session_login_failed(code: int, msg: String)

signal account_switch_failed(code: int, msg: String)

signal login_expired

signal access_token_ready(token: String, code: int, msg: String)

signal logout_completed(code: int, msg: String)

signal delete_account_completed(ok: bool, code: int, msg: String)

signal auth_gate_ready

const ERR_NOT_SUPPORT: int = -1

const ERR_NETWORK: int = 1001

const ERR_PARAM: int = 1002

const ERR_PROVIDER: int = 2000

const ERR_TOKEN_INVALID: int = 2001

const ERR_USER_CANCELED: int = 2002

const ERR_IN_PROGRESS: int = 2003

const ERR_INTERNAL: int = 2004

const ERR_FIREBASE: int = 3000

const ERR_USER_NOT_LOGIN: int = 3001

const ERR_USER_TOKEN_EXPIRED: int = 3002

const ERR_INVALID_USER: int = 3003

const ERR_PROVIDER_ALREADY_LINKED: int = 3004

const ERR_CREDENTIAL_ALREADY_IN_USE: int = 3005

const ERR_UNLINK_ALREADY_LOGIN_PROVIDER: int = 3006

const ERR_ACCOUNT_EXISTS_DIFF_CREDENTIAL: int = 3007

const ERR_SERVER: int = 4000

const ERR_SERVER_EMPTY_DATA: int = 4001

const ERR_SERVER_PARSE_FAIL: int = 4002

const ERR_SERVER_ACCESS_TOKEN_INVALID: int = 4003

const ERR_SERVER_ACCESS_TOKEN_EXPIRED: int = 4004

const ERR_SERVER_REFRESH_TOKEN_INVALID: int = 4005

const ERR_SERVER_REFRESH_TOKEN_EXPIRED: int = 4006

const ERR_SERVER_ACCOUNT_NOT_FOUND: int = 4007

const ERR_SERVER_ACCOUNT_DELETED: int = 4008

const ERR_SERVER_SIGN_INVALID: int = 4009

const ERR_SERVER_TIMESTAMP_EXPIRED: int = 4010

const ERR_FIREBASE_TOKEN_INVALID: int = 4011

const ERR_PLUGIN_UNAVAILABLE: int = -100

const ERR_NOT_INITIALIZED: int = -102

const ERR_OPERATION_IN_PROGRESS: int = -103

const ERR_UNKNOWN_GUARD: int = -104

const ERR_BUSY: int = -105

const ERR_TIMEOUT: int = -106

const _TOKEN_TIMEOUT_MS: int = 12000

const _OP_TIMEOUT_MS: int = 20000

const _LUID_STALL_WARN_SEC: float = 15.0

const _LOGIN_TIMEOUT_MS: int = 180000

const _GUARD_CODE_MAP: Dictionary = {
	"PLATFORM_NOT_SUPPORTED": ERR_PLUGIN_UNAVAILABLE,
	"NOT_INITIALIZED": ERR_NOT_INITIALIZED,
	"OPERATION_IN_PROGRESS": ERR_OPERATION_IN_PROGRESS,
	"UNKNOWN": ERR_UNKNOWN_GUARD,
	"USER_CANCELLED": ERR_USER_CANCELED,
	"NETWORK_ERROR": ERR_NETWORK,
	"NOT_LOGGED_IN": ERR_USER_NOT_LOGIN,
}

const _CHANNEL_TO_PROVIDER: Dictionary = {
	AccountDefine.CHANNEL_GOOGLE: LXAuth.Provider.GOOGLE,
	AccountDefine.CHANNEL_FACEBOOK: LXAuth.Provider.FACEBOOK,
	AccountDefine.CHANNEL_APPLE: LXAuth.Provider.APPLE,
}

const _IDLE_WAIT_MS: int = 5000

const _INIT_WAIT_MS: int = 5000

var _auth: Object = null

var _initialized: bool = false

var _busy: bool = false

var _luid_ready: bool = false

var _auth_started: bool = false

var _bootstrap_done: bool = false

const _RELOGIN_MIN_INTERVAL_MS: int = 60000

const _RELOGIN_MAX_CONSECUTIVE: int = 5

var _relogin_count: int = 0

var _last_relogin_ms: int = 0


## 连接 LXAuth 会话失效和 UniKit 标识就绪信号，并启动卡住检查。
func _ready() -> void:
	_auth = LXAuth

	_auth.login_expired.connect(_on_lx_login_expired)

	UniKitManager.luid_ready.connect(_on_luid_ready)

	_warn_if_luid_stalled()


## 仅把非编辑器的 Android、iOS 构建视为登录 SDK 支持平台。
func _is_lx_available() -> bool:
	return not OS.has_feature("editor") and (OS.has_feature("ios") or OS.has_feature("android"))


## 标记统计用户标识已就绪，再检查认证启动条件。
func _on_luid_ready(_luid: String) -> void:
	_luid_ready = true
	_notify_gate_ready()


## 在尚未发起认证且用户标识已就绪时通知启动流程。
func _notify_gate_ready() -> void:
	if _auth_started:
		return
	if not _luid_ready:
		return
	auth_gate_ready.emit()


## 提供认证前置条件状态，供启动流程决定何时开始登录。
func is_auth_gate_ready() -> bool:
	return _luid_ready


## 等待 15 秒后检查统计标识，缺失时记录本次会话无法登录同步的原因。
func _warn_if_luid_stalled() -> void:
	await get_tree().create_timer(_LUID_STALL_WARN_SEC).timeout
	if not _luid_ready:
		var message: String = (
			"[Account (AuthManager)] 等 luid_ready 超过 %ds 仍未就绪：本会话不会登录、不会同步"
			% int(_LUID_STALL_WARN_SEC)
		)
		# 只调整不支持原生认证平台的日志等级，等待时长和登录门槛保持不变。
		if _is_lx_available():
			push_warning(message)
		else:
			print("[学习工程] " + message)


## 只启动一次冷启动认证；前置标识未就绪时不抢先初始化。
func start_bootstrap() -> void:
	if _auth_started:
		return
	if not is_auth_gate_ready():
		print("[Account (AuthManager)] 发起冷启动登录被忽略：前置条件未就绪")
		return
	_auth_started = true
	_bootstrap()


## 逐帧等待异步操作并限制毫秒时长，超时返回空以释放业务串行门。
func _await_bounded(op: Callable, timeout_ms: int, label: String) -> Variant:
	var state := {"done": false, "value": null}
	var runner := func() -> void:
		var res: Variant = await op.call()
		state.value = res
		state.done = true
	runner.call()
	var started_ms: int = Time.get_ticks_msec()
	while not bool(state.done) and Time.get_ticks_msec() - started_ms < timeout_ms:
		await get_tree().process_frame
	if not bool(state.done):
		push_warning("[Account (AuthManager)] %s 超时(%dms)：原生未回调，按失败收尾并释放串行化门" % [label, timeout_ms])
		return null
	return state.value


## 初始化 SDK 后复用已恢复会话，否则发起游客登录并结束启动等待。
func _bootstrap() -> void:
	if OS.is_debug_build():
		print(
			(
				"[Account (AuthManager)] 引导开始: base_url=%s luid=%s keychain_sync=false log=%s"
				% [ApiConfig.base_url(), ApiConfig.luid(), str(OS.is_debug_build())]
			)
		)
	var code: int = await init_sdk(
		{
			"base_url": ApiConfig.base_url(),
			"secret": ApiConfig.sign_secret(),
			"luid": ApiConfig.luid(),
			"is_log_enabled": OS.is_debug_build(),
			"is_keychain_sync_enabled": false,
			"facebook_permissions": ["public_profile", "email"],
		}
	)

	if OS.is_debug_build():
		print("[Account (AuthManager)] 初始化完成 code=%d device_id=%s" % [code, get_device_id()])

	if code != 0 and code != ERR_PLUGIN_UNAVAILABLE:
		push_warning("[Account (AuthManager)] 初始化失败 code=%d，跳过本次登录" % code)
		_bootstrap_done = true
		return

	if _auth.is_logged_in:
		var prof: AccountProfile = _to_account_profile(_auth.current_user)
		if OS.is_debug_build():
			print(
				(
					"[Account (AuthManager)] 会话已由 SDK 恢复，跳过 guest 登录: provider=%s user_id=%s"
					% [get_provider_id(), prof.user_id]
				)
			)

		session_ready.emit(prof)
		_bootstrap_done = true
		return
	await login_as_guest()
	_bootstrap_done = true


## 向业务暴露当前构建是否属于登录 SDK 支持平台。
func is_available() -> bool:
	return _is_lx_available()


## 查询认证 SDK 是否已完成成功初始化。
func is_initialized() -> bool:
	return _initialized


## 等待空闲后初始化 SDK，以超时保护避免原生无回调导致业务永久繁忙。
func init_sdk(config: Dictionary) -> int:
	if _initialized:
		return 0
	if not await _await_idle(_IDLE_WAIT_MS):
		return ERR_BUSY
	_busy = true
	var res: AuthResult = await _await_bounded(
		func() -> AuthResult: return await _auth.initialize(config), _OP_TIMEOUT_MS, "初始化"
	)
	_busy = false
	if res != null and res.is_ok():
		_initialized = true
		return 0
	var failure: AuthFailure = _norm_error(res)

	if failure.code != ERR_PLUGIN_UNAVAILABLE:
		push_warning(
			"[Account (AuthManager)] 初始化 SDK 失败 code=%d msg=%s" % [failure.code, failure.message]
		)
	return failure.code


## 通过统一登录流程恢复或创建游客会话。
func login_as_guest() -> void:
	await _do_login(LXAuth.Provider.GUEST, "guest")


## 验证第三方渠道并等待初始化，随后进入统一的串行登录流程。
func login_with(channel: String) -> void:
	if not AccountDefine.is_valid_channel(channel):
		push_error("[Account (AuthManager)] 三方登录: 非法渠道 %s" % channel)
		account_switch_failed.emit.call_deferred(ERR_PARAM, "invalid channel: %s" % channel)
		return

	if not await _await_initialized(_INIT_WAIT_MS):
		account_switch_failed.emit.call_deferred(ERR_PLUGIN_UNAVAILABLE, "LXAuth unavailable")
		return
	await _do_login(int(_CHANNEL_TO_PROVIDER[channel]), channel)


## 限制并发与等待时长，把游客登录和主动换号分别发布到对应信号。
func _do_login(provider: int, label: String) -> void:
	var is_guest: bool = provider == int(LXAuth.Provider.GUEST)
	if not _initialized:
		_emit_login_failed(is_guest, ERR_PLUGIN_UNAVAILABLE, "LXAuth unavailable", true)
		return
	if not await _await_idle(_IDLE_WAIT_MS):
		_emit_login_failed(is_guest, ERR_BUSY, "another auth operation in progress", false)
		return
	_busy = true

	var started_ms: int = Time.get_ticks_msec()
	print("[Account (AuthManager)] 登录发起(%s) provider=%d" % [label, provider])
	var res: AuthResult = await _await_bounded(
		func() -> AuthResult: return await _auth.login_async(provider),
		_LOGIN_TIMEOUT_MS,
		"登录(%s)" % label
	)
	_busy = false
	var cost_ms: int = Time.get_ticks_msec() - started_ms
	if res != null and res.is_ok():
		var prof: AccountProfile = _to_account_profile(res.user_profile)
		_relogin_count = 0

		print(
			(
				"[Account (AuthManager)] 登录成功(%s) 结果=%s is_new_user=%s cost=%dms"
				% [label, "会话就绪" if is_guest else "换号", str(res.is_new_user), cost_ms]
			)
		)

		if OS.is_debug_build():
			print("[Account (AuthManager)] 登录成功(%s) user_id=%s" % [label, prof.user_id])

		if is_guest:
			session_ready.emit(prof)
		else:
			account_switched.emit(prof, res.is_new_user)
		return
	var failure: AuthFailure = _norm_error(res)
	print(
		(
			"[Account (AuthManager)] 登录失败(%s) code=%d msg=%s cost=%dms"
			% [label, failure.code, failure.message, cost_ms]
		)
	)
	_emit_login_failed(is_guest, failure.code, failure.message, false)


## 按游客会话或主动换号选择失败信号，必要时延迟发送。
func _emit_login_failed(is_guest: bool, code: int, msg: String, deferred: bool) -> void:
	var failed_signal: Signal = session_login_failed if is_guest else account_switch_failed
	if deferred:
		failed_signal.emit.call_deferred(code, msg)
	else:
		failed_signal.emit(code, msg)


## 串行请求原生登出并发布结果，成功后清理自动重登计数。
func logout() -> void:
	if not _initialized:
		logout_completed.emit.call_deferred(ERR_PLUGIN_UNAVAILABLE, "LXAuth unavailable")
		return
	if not await _await_idle(_IDLE_WAIT_MS):
		logout_completed.emit(ERR_BUSY, "another auth operation in progress")
		return
	_busy = true
	var res: AuthResult = await _await_bounded(
		func() -> AuthResult: return await _auth.logout_async(), _OP_TIMEOUT_MS, "登出"
	)
	_busy = false
	var failure: AuthFailure = _norm_error(res)
	var code: int = 0 if (res != null and res.is_ok()) else failure.code
	print("[Account (AuthManager)] 登出完成 code=%d msg=%s" % [code, failure.message])
	logout_completed.emit(code, failure.message)

	if code == 0:
		_relogin_count = 0


## 请求原生删除账号并发布结果，由调用方处理成功后的业务状态。
func delete_account() -> void:
	if not _initialized:
		delete_account_completed.emit.call_deferred(
			false, ERR_PLUGIN_UNAVAILABLE, "LXAuth unavailable"
		)
		return
	if not await _await_idle(_IDLE_WAIT_MS):
		delete_account_completed.emit(false, ERR_BUSY, "another auth operation in progress")
		return
	_busy = true
	var res: AuthResult = await _await_bounded(
		func() -> AuthResult: return await _auth.delete_account_async(), _OP_TIMEOUT_MS, "删号"
	)
	_busy = false
	var ok: bool = res != null and res.is_ok()
	var failure: AuthFailure = _norm_error(res)
	var code: int = 0 if ok else failure.code
	print("[Account (AuthManager)] 删号完成 code=%d msg=%s" % [code, failure.message])
	delete_account_completed.emit(ok, code, failure.message)


## 读取当前登录提供方标识，供账号界面区分登录渠道。
func get_provider_id() -> String:
	return _auth.current_provider_id


## 以 12 秒超时获取访问令牌，同时返回结果对象并发出完成信号。
func request_access_token(force_refresh: bool = false) -> AccessTokenResult:
	if not _initialized:
		access_token_ready.emit.call_deferred("", ERR_PLUGIN_UNAVAILABLE, "LXAuth unavailable")
		return AccessTokenResult.fail(ERR_PLUGIN_UNAVAILABLE, "LXAuth unavailable")
	if _busy:
		return AccessTokenResult.fail(ERR_BUSY, "another auth operation in progress")
	_busy = true
	var res: AuthTokenResult = await _await_bounded(
		func() -> AuthTokenResult: return await _auth.get_access_token_async(force_refresh),
		_TOKEN_TIMEOUT_MS,
		"取 access token"
	)
	_busy = false
	var result: AccessTokenResult = null
	if res != null and res.is_ok():
		result = AccessTokenResult.success(res.token)
	else:
		var failure: AuthFailure = _norm_error(res)
		result = AccessTokenResult.fail(failure.code, failure.message)
	print(
		(
			"[Account (AuthManager)] 取 access token 完成 code=%d token_len=%d"
			% [result.code, result.token.length()]
		)
	)
	access_token_ready.emit(result.token, result.code, result.message)
	return result


## 读取认证设备标识；认证节点尚未取得时返回空串。
func get_device_id() -> String:
	if _auth == null:
		return ""
	return str(_auth.device_id)


## 查询 LXAuth 当前是否存在有效登录会话。
func is_logged_in() -> bool:
	return _auth.is_logged_in


## 查询当前会话是否为游客身份。
func is_guest_login() -> bool:
	return _auth.is_guest_login


## 将 SDK 用户资料转换为游戏自己的 AccountProfile。
func get_user_profile() -> AccountProfile:
	return _to_account_profile(_auth.current_user)


## 通知会话失效，再按最短 60 秒间隔与连续 5 次上限尝试游客重登。
func _on_lx_login_expired(info: AuthExpiredInfo) -> void:
	var uid: String = "" if info == null else info.expired_user_id

	if OS.is_debug_build():
		print("[Account (AuthManager)] 会话失效 expired_user_id=%s" % uid)
	else:
		print("[Account (AuthManager)] 会话失效")
	login_expired.emit()
	var now: int = Time.get_ticks_msec()
	if _last_relogin_ms > 0 and (now - _last_relogin_ms) < _RELOGIN_MIN_INTERVAL_MS:
		print(
			"[Account (AuthManager)] 距上次重登 <%ds，跳过本次自动重登（防抖）" % int(_RELOGIN_MIN_INTERVAL_MS / 1000)
		)
		return
	if _relogin_count >= _RELOGIN_MAX_CONSECUTIVE:
		push_warning(
			"[Account (AuthManager)] 连续自动重登达上限 %d，本次会话放弃重登（下次冷启动恢复）" % _RELOGIN_MAX_CONSECUTIVE
		)
		return
	_relogin_count += 1
	_last_relogin_ms = now
	print("[Account (AuthManager)] 会话失效 → 重新 guest 登录（第 %d 次）" % _relogin_count)
	await login_as_guest()


## 逐帧等待初始化；启动流程已结束或超过毫秒上限时停止等待。
func _await_initialized(timeout_ms: int) -> bool:
	if _initialized:
		return true
	if _bootstrap_done:
		return false
	var t0: int = Time.get_ticks_msec()
	while not _initialized and not _bootstrap_done and Time.get_ticks_msec() - t0 < timeout_ms:
		await get_tree().process_frame
	var waited: int = Time.get_ticks_msec() - t0
	if not _initialized:
		push_warning(
			(
				"[Account (AuthManager)] 等初始化超时/落空 %dms（bootstrap_done=%s），本次登录放弃"
				% [waited, str(_bootstrap_done)]
			)
		)
		return false
	print("[Account (AuthManager)] 登录前等初始化完成，等了 %dms" % waited)
	return true


## 等待另一项账号操作结束，超过毫秒上限时让调用方返回繁忙错误。
func _await_idle(timeout_ms: int) -> bool:
	if not _busy:
		return true
	var t0: int = Time.get_ticks_msec()
	while _busy and Time.get_ticks_msec() - t0 < timeout_ms:
		await get_tree().process_frame
	return not _busy


## 统一 SDK 字符串错误与业务整数错误码，空结果按超时处理。
func _norm_error(res: Object) -> AuthFailure:
	if res == null:
		return AuthFailure.of(ERR_TIMEOUT, "await timed out or coroutine aborted")
	var err: AuthError = res.error
	if err == null:
		return AuthFailure.of(ERR_UNKNOWN_GUARD, "no error detail")
	var raw: String = err.code
	if _GUARD_CODE_MAP.has(raw):
		return AuthFailure.of(int(_GUARD_CODE_MAP[raw]), err.message)

	if raw.is_valid_int():
		return AuthFailure.of(int(raw), err.message)
	if raw.is_valid_float():
		return AuthFailure.of(int(float(raw)), err.message)
	return AuthFailure.of(ERR_UNKNOWN_GUARD, "%s: %s" % [raw, err.message])


## 复制业务需要的用户资料，避免其他模块直接依赖 SDK 数据类型。
func _to_account_profile(source: AuthUserProfile) -> AccountProfile:
	if source == null:
		return AccountProfile.empty()
	var profile := AccountProfile.new()
	profile.user_id = source.user_id
	profile.firebase_uid = source.firebase_uid
	profile.user_name = source.user_name
	profile.provider_id = source.provider_id
	profile.email = source.email
	profile.photo_url = source.photo_url
	return profile
