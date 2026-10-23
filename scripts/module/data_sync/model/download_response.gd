## 下载请求的包装结果；除原始 API 响应外也返回当前 bearer，保留刷新令牌后的状态。

class_name DownloadResponse
extends RefCounted

var ok: bool = false

var reason: String = ""

var api_result: ApiResponse = null

var bearer: String = ""


static func fail(fail_reason: String, current_bearer: String = "") -> DownloadResponse:
	var response := DownloadResponse.new()
	response.reason = fail_reason
	response.bearer = current_bearer
	return response


static func success(result: ApiResponse, current_bearer: String) -> DownloadResponse:
	var response := DownloadResponse.new()
	response.ok = true
	response.api_result = result
	response.bearer = current_bearer
	return response
