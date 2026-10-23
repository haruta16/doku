## 访问令牌结果：把令牌值与获取失败原因放在同一返回类型中。
class_name AuthTokenResult
extends RefCounted

var success: bool = false
var token: String = ""
var error: AuthError = null


## 读取原生回执的成功标志，供 await 调用方统一判断。
func is_ok() -> bool:
	return success


## 把原生 JSON 字段转换为脚本模型，缺失字段使用模型定义的默认值。
static func from_json(json: Dictionary) -> AuthTokenResult:
	var result = AuthTokenResult.new()
	result.success = json.get("success", false)
	result.token = json.get("accessToken", "")
	if not result.success and json.has("error"):
		result.error = AuthError.from_json(json["error"])
	return result


## 创建带错误信息的失败结果，用于原生调用之前的条件检查。
static func fail(error_code: String, error_message: String = "") -> AuthTokenResult:
	var result = AuthTokenResult.new()
	result.success = false
	result.error = AuthError.create(error_code, error_message)
	return result
