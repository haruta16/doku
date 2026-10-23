## 认证层统一的用户资料模型，容纳不同登录渠道返回的身份、昵称和头像字段。

class_name AccountProfile
extends RefCounted

var user_id: String = ""

var firebase_uid: String = ""

var user_name: String = ""

var provider_id: String = ""

var email: String = ""

var photo_url: String = ""


static func empty() -> AccountProfile:
	return AccountProfile.new()
