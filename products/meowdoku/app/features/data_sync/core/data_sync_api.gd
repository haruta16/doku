## 云存档接口封装：查询版本、下载存档、上传存档都通过 HttpClient 发起异步请求。
## 这里负责协议参数和响应，是否覆盖本地数据由 DataSyncManager 及各存档模块决定。

class_name DataSyncApi
extends RefCounted

var _http: HttpClient


func _init(http: HttpClient) -> void:
	_http = http


## 只请求云存档的版本元信息，供管理器判断是否需要下载完整内容。
func fetch_meta(bearer: String) -> ApiResponse:
	return await _http.request_json(
		HTTPClient.METHOD_GET, ApiConfig.PATH_SYNC_GAMEDATA_META, {}, bearer
	)


## 用访问令牌请求完整云存档；返回协议响应，由管理器负责解析和合并。
func download(bearer: String) -> ApiResponse:
	return await _http.request_json(HTTPClient.METHOD_GET, ApiConfig.PATH_SYNC_GAMEDATA, {}, bearer)


## 提交封装后的存档与同步版本；服务器版本冲突由上层重试流程处理。
func upload(
	bearer: String,
	game_data: String,
	schema_version: String,
	sync_code: int,
	extra_info: String = ""
) -> ApiResponse:
	var body: Dictionary = {
		"game_data": game_data,
		"schema_version": schema_version,
		"sync_code": sync_code,
	}
	if not extra_info.is_empty():
		body["extra_info"] = extra_info
	return await _http.request_json(
		HTTPClient.METHOD_POST, ApiConfig.PATH_SYNC_GAMEDATA, body, bearer
	)
