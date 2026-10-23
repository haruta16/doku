## 认证错误模型：保留跨平台字符串错误码与可读原因。
class_name AuthError
extends RefCounted

const NOT_INITIALIZED = "NOT_INITIALIZED"
const NOT_LOGGED_IN = "NOT_LOGGED_IN"
const USER_CANCELLED = "USER_CANCELLED"
const NETWORK_ERROR = "NETWORK_ERROR"
const PLATFORM_NOT_SUPPORTED = "PLATFORM_NOT_SUPPORTED"
const OPERATION_IN_PROGRESS = "OPERATION_IN_PROGRESS"
const UNKNOWN = "UNKNOWN"

var code: String = ""
var message: String = ""


## 把原生 JSON 字段转换为脚本模型，缺失字段使用模型定义的默认值。
static func from_json(json: Dictionary) -> AuthError:
	var err = AuthError.new()
	err.code = str(json.get("code", UNKNOWN))
	err.message = json.get("message", json.get("msg", ""))
	return err


## 用错误码和说明创建错误对象，供失败结果复用。
static func create(error_code: String, error_message: String = "") -> AuthError:
	var err = AuthError.new()
	err.code = error_code
	err.message = error_message
	return err
