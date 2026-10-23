## 第三方身份资料：描述同一账号所绑定的一个登录渠道。
class_name AuthProviderInfo
extends RefCounted

var user_id: String = ""
var provider_id: String = ""
var user_name: String = ""
var email: String = ""
var photo_url: String = ""


## 把原生 JSON 字段转换为脚本模型，缺失字段使用模型定义的默认值。
static func from_json(json: Dictionary) -> AuthProviderInfo:
	var info = AuthProviderInfo.new()
	info.user_id = json.get("userId", "")
	info.provider_id = json.get("providerId", "")
	info.user_name = json.get("name", "")
	info.email = json.get("email", "")
	info.photo_url = json.get("photoUrl", "")
	return info
