## 绑定或登录结果：在用户资料之外保留实际执行的动作。
class_name AuthLinkOrLoginResult
extends RefCounted

var success: bool = false
var action: String = ""
var user_profile: AuthUserProfile = null
var is_new_user: bool = false
var error: AuthError = null


## 读取原生回执的成功标志，供 await 调用方统一判断。
func is_ok() -> bool:
	return success


## 把原生 JSON 字段转换为脚本模型，缺失字段使用模型定义的默认值。
static func from_json(json: Dictionary) -> AuthLinkOrLoginResult:
	var result = AuthLinkOrLoginResult.new()
	result.success = json.get("success", false)
	result.action = json.get("action", "")
	result.is_new_user = json.get("isNewUser", false)
	if result.success and json.has("userProfile"):
		result.user_profile = AuthUserProfile.from_json(json["userProfile"])
	if not result.success and json.has("error"):
		result.error = AuthError.from_json(json["error"])
	return result


## 创建带错误信息的失败结果，用于原生调用之前的条件检查。
static func fail(error_code: String, error_message: String = "") -> AuthLinkOrLoginResult:
	var result = AuthLinkOrLoginResult.new()
	result.success = false
	result.error = AuthError.create(error_code, error_message)
	return result
