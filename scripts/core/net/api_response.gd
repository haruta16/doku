## HTTP 请求结果：分别保存传输结果、业务状态、数据和本次签名采用的时差。
class_name ApiResponse
extends RefCounted

var ok: bool = false

var http_status: int = 0

var code: int = -1

var message: String = ""

var data: Dictionary = {}

var sign_offset_sec: int = 0


## 同时检查已收到响应和业务成功码；不能只凭 HTTP 请求完成就判业务成功。
func is_ok() -> bool:
	return ok and code == ApiConfig.CODE_OK


## 构造未收到有效响应的结果，保留可读原因供上层处理。
static func net_fail(reason: String) -> ApiResponse:
	var response := ApiResponse.new()
	response.message = reason
	return response


## 封装收到的响应及签名时差，业务是否成功由 is_ok 再判断。
static func received(
	status_code: int,
	business_code: int,
	business_message: String,
	payload: Dictionary,
	offset_used: int
) -> ApiResponse:
	var response := ApiResponse.new()
	response.ok = true
	response.http_status = status_code
	response.code = business_code
	response.message = business_message
	response.data = payload
	response.sign_offset_sec = offset_used
	return response
