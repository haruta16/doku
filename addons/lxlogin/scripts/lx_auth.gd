## 跨平台认证门面：把原生登录回调转换为可 await 的结果对象，避免并发账号操作。
extends Node

const AndroidBridgeAdapterScript = preload("../native/android_bridge_adapter.gd")

enum Provider {
	APPLE,
	GOOGLE,
	FACEBOOK,
	GAME_CENTER,
	GUEST,
	CUSTOM_TOKEN,
	PLAYGAMES,
}

enum Platform {
	UNSUPPORTED,
	IOS,
	ANDROID,
}

signal login_expired(info: AuthExpiredInfo)

var is_logged_in: bool:
	get:
		return _get_bool("is_logged_in")

var is_guest_login: bool:
	get:
		return _get_bool("is_guest_login")

var current_user: AuthUserProfile:
	get:
		return _get_current_user()

var current_provider_id: String:
	get:
		return _get_string("get_current_provider_id")

var has_linked_providers: bool:
	get:
		return _get_bool("has_linked_providers")

var is_access_token_valid: bool:
	get:
		return _get_bool("is_access_token_valid")

var device_id: String:
	get:
		return _get_string("get_device_id")

var _plugin: Object = null
var _platform: Platform = Platform.UNSUPPORTED
var _initialized: bool = false
var _operation_in_progress: bool = false

const _PROVIDER_MAP_IOS: Dictionary = {
	Provider.APPLE: "apple",
	Provider.GOOGLE: "google",
	Provider.FACEBOOK: "facebook",
	Provider.GAME_CENTER: "gameCenter",
	Provider.GUEST: "guest",
}
const _PROVIDER_MAP_ANDROID: Dictionary = {
	Provider.GOOGLE: "google",
	Provider.FACEBOOK: "facebook",
	Provider.PLAYGAMES: "playgames",
	Provider.GUEST: "guest",
}


## 选择 iOS 原生单例或 Android 适配器，并连接会话失效通知。
func _ready() -> void:
	if Engine.has_singleton("LXAuthPlugin"):
		_plugin = Engine.get_singleton("LXAuthPlugin")
		_platform = Platform.IOS
	elif Engine.has_singleton("LoginBridge"):
		_plugin = AndroidBridgeAdapterScript.new()
		add_child(_plugin)
		_platform = Platform.ANDROID
	if _plugin != null:
		_plugin.connect("_login_expired", _on_login_expired)


## 转换配置字段并等待原生初始化回执；重复成功初始化直接返回成功。
func initialize(config: Dictionary) -> AuthResult:
	if _plugin == null:
		return AuthResult.fail(AuthError.PLATFORM_NOT_SUPPORTED, "Native plugin not available")
	if _initialized:
		return _make_success_result()
	if _operation_in_progress:
		return AuthResult.fail(AuthError.OPERATION_IN_PROGRESS, "Another operation in progress")

	_operation_in_progress = true
	var config_json = (
		JSON
		. stringify(
			{
				"baseUrl": config.get("base_url", ""),
				"secret": config.get("secret", ""),
				"luid": config.get("luid", ""),
				"isLogEnabled": config.get("is_log_enabled", false),
				"isKeychainSyncEnabled": config.get("is_keychain_sync_enabled", false),
				"facebookPermissions": config.get("facebook_permissions", []),
			}
		)
	)
	_plugin.initialize(config_json)
	var result_json: String = await _plugin._init_completed
	_operation_in_progress = false
	var result = _parse_auth_result(result_json)
	if result.is_ok():
		_initialized = true
	return result


## 校验操作条件和平台渠道，等待原生登录完成后解析用户资料。
func login_async(provider: Provider) -> AuthResult:
	var guard_result = _guard_operation()
	if guard_result != null:
		return guard_result
	var provider_id := _get_provider_id(provider)
	if provider_id.is_empty():
		return AuthResult.fail(
			AuthError.PLATFORM_NOT_SUPPORTED, "Provider not supported on this platform"
		)
	_operation_in_progress = true
	_plugin.login(provider_id)
	var result_json: String = await _plugin._login_completed
	_operation_in_progress = false
	return _parse_auth_result(result_json)


## 复用统一登录流程，以游客渠道发起认证。
func guest_login_async() -> AuthResult:
	return await login_async(Provider.GUEST)


## 仅在 iOS 发送自定义令牌登录请求，并等待登录回执。
func custom_login_async(token_json: String) -> AuthResult:
	var guard_result = _guard_operation()
	if guard_result != null:
		return guard_result
	if _platform != Platform.IOS:
		return AuthResult.fail(
			AuthError.PLATFORM_NOT_SUPPORTED, "Custom token login is not supported on this platform"
		)
	_operation_in_progress = true
	_plugin.custom_login(token_json)
	var result_json: String = await _plugin._login_completed
	_operation_in_progress = false
	return _parse_auth_result(result_json)


## 把第三方身份绑定到当前账号，并等待绑定结果。
func link_async(provider: Provider) -> AuthResult:
	var guard_result = _guard_operation()
	if guard_result != null:
		return guard_result
	var provider_id := _get_provider_id(provider)
	if provider_id.is_empty():
		return AuthResult.fail(
			AuthError.PLATFORM_NOT_SUPPORTED, "Provider not supported on this platform"
		)
	_operation_in_progress = true
	_plugin.link(provider_id)
	var result_json: String = await _plugin._link_completed
	_operation_in_progress = false
	return _parse_auth_result(result_json)


## 请求原生层决定绑定或切换登录，结果中保留实际执行的动作。
func link_or_login_async(provider: Provider) -> AuthLinkOrLoginResult:
	if _plugin == null:
		return AuthLinkOrLoginResult.fail(AuthError.PLATFORM_NOT_SUPPORTED)
	if not _initialized:
		return AuthLinkOrLoginResult.fail(AuthError.NOT_INITIALIZED)
	if _operation_in_progress:
		return AuthLinkOrLoginResult.fail(AuthError.OPERATION_IN_PROGRESS)
	var provider_id := _get_provider_id(provider)
	if provider_id.is_empty():
		return AuthLinkOrLoginResult.fail(
			AuthError.PLATFORM_NOT_SUPPORTED, "Provider not supported on this platform"
		)
	_operation_in_progress = true
	_plugin.link_or_login(provider_id)
	var result_json: String = await _plugin._link_or_login_completed
	_operation_in_progress = false
	var parsed = _parse_json(result_json)
	if parsed.is_empty() and not result_json.is_empty():
		return AuthLinkOrLoginResult.fail(AuthError.UNKNOWN, "Failed to parse response")
	return AuthLinkOrLoginResult.from_json(parsed)


## 解除指定渠道绑定，操作完成前占用认证串行门。
func unlink_async(provider: Provider) -> AuthResult:
	var guard_result = _guard_operation()
	if guard_result != null:
		return guard_result
	var provider_id := _get_provider_id(provider)
	if provider_id.is_empty():
		return AuthResult.fail(
			AuthError.PLATFORM_NOT_SUPPORTED, "Provider not supported on this platform"
		)
	_operation_in_progress = true
	_plugin.unlink(provider_id)
	var result_json: String = await _plugin._unlink_completed
	_operation_in_progress = false
	return _parse_auth_result(result_json)


## 按是否强制刷新取得访问令牌，结果独立于用户资料对象。
func get_access_token_async(force_refresh: bool) -> AuthTokenResult:
	if _plugin == null:
		return AuthTokenResult.fail(AuthError.PLATFORM_NOT_SUPPORTED)
	if not _initialized:
		return AuthTokenResult.fail(AuthError.NOT_INITIALIZED)
	if _operation_in_progress:
		return AuthTokenResult.fail(AuthError.OPERATION_IN_PROGRESS)
	_operation_in_progress = true
	_plugin.get_access_token_async(force_refresh)
	var result_json: String = await _plugin._access_token_completed
	_operation_in_progress = false
	var parsed = _parse_json(result_json)
	if parsed.is_empty() and not result_json.is_empty():
		return AuthTokenResult.fail(AuthError.UNKNOWN, "Failed to parse response")
	return AuthTokenResult.from_json(parsed)


## 请求原生清除登录会话，并等待登出完成信号。
func logout_async() -> AuthResult:
	var guard_result = _guard_operation()
	if guard_result != null:
		return guard_result
	_operation_in_progress = true
	_plugin.logout()
	var result_json: String = await _plugin._logout_completed
	_operation_in_progress = false
	return _parse_auth_result(result_json)


## 请求删除当前账号，并把原生结果转换为认证结果对象。
func delete_account_async() -> AuthResult:
	var guard_result = _guard_operation()
	if guard_result != null:
		return guard_result
	_operation_in_progress = true
	_plugin.delete_account()
	var result_json: String = await _plugin._delete_completed
	_operation_in_progress = false
	return _parse_auth_result(result_json)


## 重新从原生 SDK 刷新账号资料，期间阻止其他认证操作。
func refresh_account_async() -> AuthResult:
	var guard_result = _guard_operation()
	if guard_result != null:
		return guard_result
	_operation_in_progress = true
	_plugin.refresh_account()
	var result_json: String = await _plugin._refresh_completed
	_operation_in_progress = false
	return _parse_auth_result(result_json)


## 把统一渠道枚举映射为当前原生平台接受的字符串。
func _get_provider_id(provider: Provider) -> String:
	var providers := _PROVIDER_MAP_IOS if _platform == Platform.IOS else _PROVIDER_MAP_ANDROID
	return providers.get(provider, "")


## 统一检查插件存在、已初始化且没有并发操作；通过时返回空。
func _guard_operation() -> AuthResult:
	if _plugin == null:
		return AuthResult.fail(AuthError.PLATFORM_NOT_SUPPORTED, "Native plugin not available")
	if not _initialized:
		return AuthResult.fail(AuthError.NOT_INITIALIZED, "Call initialize() first")
	if _operation_in_progress:
		return AuthResult.fail(AuthError.OPERATION_IN_PROGRESS, "Another operation is in progress")
	return null


## 只接受字典型原生响应，格式异常时记录错误并返回空字典。
func _parse_json(json_str: String) -> Dictionary:
	if json_str.is_empty():
		return {}
	var parsed = JSON.parse_string(json_str)
	if parsed is Dictionary:
		return parsed
	push_error("[LXAuth] Failed to parse JSON response: %s" % json_str.left(100))
	return {}


## 把 JSON 解析失败和原生业务失败分别转为 AuthResult。
func _parse_auth_result(json_str: String) -> AuthResult:
	var parsed = _parse_json(json_str)
	if parsed.is_empty() and not json_str.is_empty():
		return AuthResult.fail(AuthError.UNKNOWN, "Failed to parse response")
	return AuthResult.from_json(parsed)


## 请求原生层移除持久化设备标识，返回是否成功。
func remove_device_id() -> bool:
	if _plugin == null:
		return false
	return _plugin.call("remove_device_id")


## 为已初始化等无需原生调用的路径创建成功结果。
func _make_success_result() -> AuthResult:
	var result = AuthResult.new()
	result.success = true
	return result


## 在插件已初始化时读取布尔状态，其余情况返回 false。
func _get_bool(method: String) -> bool:
	if _plugin == null or not _initialized:
		return false
	return _plugin.call(method)


## 在插件已初始化时读取字符串状态，其余情况返回空串。
func _get_string(method: String) -> String:
	if _plugin == null or not _initialized:
		return ""
	return _plugin.call(method)


## 读取原生用户 JSON 并构建用户模型，没有有效资料时返回空。
func _get_current_user() -> AuthUserProfile:
	if _plugin == null or not _initialized:
		return null
	var json_str: String = _plugin.get_account_json()
	if json_str.is_empty() or json_str == "null":
		return null
	var parsed = JSON.parse_string(json_str)
	if not (parsed is Dictionary):
		push_error("[LXAuth] Failed to parse account JSON: %s" % json_str.left(100))
		return null
	return AuthUserProfile.from_json(parsed)


## 解析原生会话失效数据，向业务发送类型明确的失效通知。
func _on_login_expired(info_json: String) -> void:
	var parsed = JSON.parse_string(info_json)
	if parsed is Dictionary:
		var info = AuthExpiredInfo.from_json(parsed)
		login_expired.emit(info)
