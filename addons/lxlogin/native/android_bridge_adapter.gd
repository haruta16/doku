## Android 登录适配器：把 LoginBridge 的方法、字段和信号转换为 LXAuth 的统一协议。
class_name AndroidBridgeAdapter
extends Node

signal _init_completed(result_json: String)
signal _login_completed(result_json: String)
signal _logout_completed(result_json: String)
signal _delete_completed(result_json: String)
signal _link_completed(result_json: String)
signal _link_or_login_completed(result_json: String)
signal _unlink_completed(result_json: String)
signal _refresh_completed(result_json: String)
signal _access_token_completed(result_json: String)
signal _login_expired(info_json: String)

var _native: Object


## 注入或取得 LoginBridge，并将各类原生回调接到统一转换函数。
func _init(native: Object = null) -> void:
	_native = native if native != null else Engine.get_singleton("LoginBridge")
	_native.connect(&"init_result", _on_init_result)
	_native.connect(&"login_success", _on_login_success)
	_native.connect(&"logout_success", _on_logout_success)
	_native.connect(&"delete_user_success", _on_delete_success)
	_native.connect(&"link_success", _on_link_success)
	_native.connect(&"link_or_login_success", _on_link_or_login_success)
	_native.connect(&"unlink_success", _on_unlink_success)
	_native.connect(&"reload_success", _on_refresh_success)
	_native.connect(&"token_success", _on_token_success)
	_native.connect(&"auth_error", _on_auth_error)
	_native.connect(&"login_expired", _on_login_expired)


## 把跨平台配置名转换为 Android LoginBridge 使用的字段后初始化。
func initialize(config_json: String) -> void:
	var config := _parse_dictionary(config_json)
	(
		_native
		. initialize(
			(
				JSON
				. stringify(
					{
						"baseUrl": config.get("baseUrl", ""),
						"luid": config.get("luid", ""),
						"secret": config.get("secret", ""),
						"showLog": config.get("isLogEnabled", false),
						"facebookPermissions": config.get("facebookPermissions", []),
					}
				)
			)
		)
	)


## 游客渠道调用专门的原生接口，其余渠道按标识传入。
func login(provider: String) -> void:
	if provider == "guest":
		_native.loginAsGuest()
	else:
		_native.login(provider)


## 把绑定请求交给 Android 原生层，完成结果通过回调信号返回。
func link(provider: String) -> void:
	_native.link(provider)


## 让原生层执行绑定或登录，后续统一回执会区分实际动作。
func link_or_login(provider: String) -> void:
	_native.linkOrLogin(provider)


## 调用 Android 的解绑接口，适配其方法命名差异。
func unlink(provider: String) -> void:
	_native.unLink(provider)


## 提交令牌请求，是否强制刷新由参数传给原生层。
func get_access_token_async(force_refresh: bool) -> void:
	_native.getAccessToken(force_refresh)


## 向原生层提交登出请求，完成时再发统一信号。
func logout() -> void:
	_native.logout()


## 向原生层提交删除用户请求，等待删除结果回调。
func delete_account() -> void:
	_native.deleteUser()


## 请求原生重新加载当前账号资料。
func refresh_account() -> void:
	_native.reload()


## 直接读取 Android SDK 的登录状态。
func is_logged_in() -> bool:
	return _native.isLoggedIn()


## 直接读取 Android SDK 的游客身份状态。
func is_guest_login() -> bool:
	return _native.isGuestLogin()


## 读取原生当前登录渠道标识。
func get_current_provider_id() -> String:
	return _native.getCurrentProviderId()


## 检查原生账号是否绑定了第三方身份。
func has_linked_providers() -> bool:
	return _native.hasLinkedProviders()


## 读取原生 SDK 当前访问令牌的有效状态。
func is_access_token_valid() -> bool:
	return _native.isAccessTokenValid()


## 把 Android 用户资料 JSON 提供给跨平台模型解析层。
func get_account_json() -> String:
	return _native.getUserProfileJson()


## 读取 Android 登录 SDK 保存的设备标识。
func get_device_id() -> String:
	return _native.getDeviceId()


## 请求 Android SDK 移除设备标识并返回原生结果。
func remove_device_id() -> bool:
	return _native.removeDeviceId()


## 把整数初始化错误码包装为统一成功或失败 JSON。
func _on_init_result(code: int) -> void:
	var result := {"success": code == 0}
	if code != 0:
		result["error"] = {
			"code": str(code),
			"message": "Initialization failed with code %d" % code,
		}
	_emit_deferred(&"_init_completed", result)


## 从 Android 登录结果提取新用户标志与资料，延迟发布登录完成。
func _on_login_success(result_json: String) -> void:
	var native_result := _parse_dictionary(result_json)
	_emit_deferred(
		&"_login_completed",
		{
			"success": true,
			"isNewUser": native_result.get("isNewUser", false),
			"userProfile": native_result.get("userProfile", {}),
		}
	)


## 将无参数的原生登出回调转换为统一成功回执。
func _on_logout_success() -> void:
	_emit_deferred(&"_logout_completed", {"success": true})


## 将原生删除用户成功转换为统一成功回执。
func _on_delete_success() -> void:
	_emit_deferred(&"_delete_completed", {"success": true})


## 包装绑定后的用户资料，延迟发布绑定完成。
func _on_link_success(profile_json: String) -> void:
	_emit_deferred(
		&"_link_completed",
		{
			"success": true,
			"userProfile": _parse_dictionary(profile_json),
		}
	)


## 把 Android 动作类型转换为 login 或 link，并保留用户资料。
func _on_link_or_login_success(result_json: String) -> void:
	var native_result := _parse_dictionary(result_json)
	var action: String = "login" if native_result.get("type", "") == "LOGGED_IN" else "link"
	var login_result: Dictionary = native_result.get("loginResult", {})
	_emit_deferred(
		&"_link_or_login_completed",
		{
			"success": true,
			"action": action,
			"isNewUser": login_result.get("isNewUser", false),
			"userProfile": native_result.get("userProfile", {}),
		}
	)


## 把原生解绑成功转换为统一成功回执。
func _on_unlink_success() -> void:
	_emit_deferred(&"_unlink_completed", {"success": true})


## 把原生资料刷新成功转换为统一成功回执。
func _on_refresh_success() -> void:
	_emit_deferred(&"_refresh_completed", {"success": true})


## 将原生令牌字符串包装为统一令牌结果。
func _on_token_success(token: String) -> void:
	_emit_deferred(
		&"_access_token_completed",
		{
			"success": true,
			"accessToken": token,
		}
	)


## 按失败操作选中相应完成信号，让对应 await 能收到失败回执。
func _on_auth_error(operation: String, error_json: String) -> void:
	var signal_name: StringName
	match operation:
		"login", "loginAsGuest":
			signal_name = &"_login_completed"
		"logout":
			signal_name = &"_logout_completed"
		"deleteUser":
			signal_name = &"_delete_completed"
		"link":
			signal_name = &"_link_completed"
		"linkOrLogin":
			signal_name = &"_link_or_login_completed"
		"unLink":
			signal_name = &"_unlink_completed"
		"reload":
			signal_name = &"_refresh_completed"
		"getAccessToken":
			signal_name = &"_access_token_completed"
		_:
			push_error("[LXAuth] Unknown Android auth operation: %s" % operation)
			return
	_emit_deferred(
		signal_name,
		{
			"success": false,
			"error": _normalize_error(error_json),
		}
	)


## 统一失效用户标识与错误字段，再发布会话失效通知。
func _on_login_expired(user_id: String, error_json: String) -> void:
	_emit_deferred(
		&"_login_expired",
		{
			"expiredUserId": user_id,
			"expiredError": _normalize_error(error_json),
		}
	)


## 延迟发送 JSON 回执，让发起方有机会先进入 await 监听。
func _emit_deferred(signal_name: StringName, payload: Dictionary) -> void:
	call_deferred("emit_signal", signal_name, JSON.stringify(payload))


## 统一原生错误的 code、message 字段，兼容 msg 别名。
func _normalize_error(error_json: String) -> Dictionary:
	var error := _parse_dictionary(error_json)
	return {
		"code": str(error.get("code", "UNKNOWN")),
		"message": error.get("message", error.get("msg", "")),
	}


## 将 Android JSON 响应限制为字典，异常结构回退为空字典。
func _parse_dictionary(json: String) -> Dictionary:
	var parsed = JSON.parse_string(json)
	return parsed if parsed is Dictionary else {}
