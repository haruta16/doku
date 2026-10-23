## 会话失效信息：携带失效用户标识和原生错误详情。
class_name AuthExpiredInfo
extends RefCounted

var expired_user_id: String = ""
var error: AuthError = null


## 把原生 JSON 字段转换为脚本模型，缺失字段使用模型定义的默认值。
static func from_json(json: Dictionary) -> AuthExpiredInfo:
	var info = AuthExpiredInfo.new()
	info.expired_user_id = json.get("expiredUserId", "")
	if json.has("expiredError"):
		info.error = AuthError.from_json(json["expiredError"])
	return info
