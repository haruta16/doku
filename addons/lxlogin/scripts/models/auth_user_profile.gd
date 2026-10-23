## 登录 SDK 用户模型：汇总主账号资料和绑定的第三方身份列表。
class_name AuthUserProfile
extends RefCounted

var user_id: String = ""
var firebase_uid: String = ""
var user_name: String = ""
var provider_id: String = ""
var email: String = ""
var photo_url: String = ""
var providers: Array[AuthProviderInfo] = []


## 把原生 JSON 字段转换为脚本模型，缺失字段使用模型定义的默认值。
static func from_json(json: Dictionary) -> AuthUserProfile:
	var profile = AuthUserProfile.new()
	profile.user_id = json.get("id", "")
	profile.firebase_uid = json.get("firebaseUid", "")
	profile.user_name = json.get("name", "")
	profile.provider_id = json.get("providerId", "")
	profile.email = json.get("email", "")
	profile.photo_url = json.get("photoUrl", "")
	var providers_json: Array = json.get("providers", [])
	for p in providers_json:
		if p is Dictionary:
			profile.providers.append(AuthProviderInfo.from_json(p))
	return profile
