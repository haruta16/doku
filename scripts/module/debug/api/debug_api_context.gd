# 调试 HTTP 接口的单次请求上下文：装请求（方法/路径/查询串/头）与响应（状态码/JSON 体）
class_name DebugApiContext
extends RefCounted

# ---- 请求字段（由 DebugApiServer 解析后填好） ----
var method: String = "" # HTTP 方法，本项目只注册 GET
var path: String = "" # 去掉查询串后的路径，如 /meowdoku/api/ping
var query_params: Dictionary = {} # ?a=1&b=2 解析出的键值对，值统一是 String
var headers: Dictionary = {} # 请求头，键名保留原始大小写

# ---- 响应字段（处理函数只改这两个，服务器据此回包） ----
var status_code: int = 200 # HTTP 状态码，默认 200
var response_body: String = "" # 响应体字符串，通常是 JSON.stringify 的结果


# 把字典序列化成 JSON 当响应体，并设置状态码
func set_json(data: Dictionary, code: int = 200) -> void:
	status_code = code
	response_body = JSON.stringify(data)


# 统一的错误响应：固定 result=error 加 message 两个字段
func set_error(message: String, code: int = 400) -> void:
	status_code = code
	response_body = JSON.stringify({"result": "error", "message": message})


# 取查询参数；缺失时用 default_value，非字符串值也会转成字符串
func get_query(key: String, default_value: String = "") -> String:
	return String(query_params.get(key, default_value))


# 取整数查询参数；缺失或不是合法整数时都退化成 default_value
func get_query_int(key: String, default_value: int = 0) -> int:
	if not query_params.has(key):
		return default_value
	var raw: String = String(query_params[key])
	if not raw.is_valid_int():
		return default_value
	return raw.to_int()
