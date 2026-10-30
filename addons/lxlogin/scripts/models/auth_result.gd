## 认证操作结果：统一成功标志、新用户标志、用户资料与失败原因。
class_name AuthResult
extends RefCounted

var success: bool = false
var user_profile: AuthUserProfile = null
var is_new_user: bool = false
var error: AuthError = null


## 读取原生回执的成功标志，供 await 调用方统一判断。
func is_ok() -> bool:
	return success


## 把原生 JSON 字段转换为脚本模型，缺失字段使用模型定义的默认值。
static func from_json(json: Dictionary) -> AuthResult:
	var result = AuthResult.new()
	result.success = json.get("success", false)
	result.is_new_user = json.get("isNewUser", false)
	if result.success and json.has("userProfile"):
		result.user_profile = AuthUserProfile.from_json(json["userProfile"])
	if not result.success and json.has("error"):
		result.error = AuthError.from_json(json["error"])
	return result


## 创建带错误信息的失败结果，用于原生调用之前的条件检查。
static func fail(error_code: String, error_message: String = "") -> AuthResult:
	var result = AuthResult.new()
	result.success = false
	result.error = AuthError.create(error_code, error_message)
	return result
