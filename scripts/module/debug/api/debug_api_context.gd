class_name DebugApiContext
extends RefCounted




var method: String = ""
var path: String = ""
var query_params: Dictionary = {}
var headers: Dictionary = {}

var status_code: int = 200
var response_body: String = ""


func set_json(data: Dictionary, code: int = 200) -> void :
    status_code = code
    response_body = JSON.stringify(data)


func set_error(message: String, code: int = 400) -> void :
    status_code = code
    response_body = JSON.stringify({"result": "error", "message": message})



func get_query(key: String, default_value: String = "") -> String:
    return String(query_params.get(key, default_value))


func get_query_int(key: String, default_value: int = 0) -> int:
    if not query_params.has(key):
        return default_value
    var raw: String = String(query_params[key])
    if not raw.is_valid_int():
        return default_value
    return raw.to_int()
