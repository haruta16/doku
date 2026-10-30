## Android 登录导出配置：集中保存 Facebook 接入所需的应用标识与客户端令牌。
@tool
class_name LXAuthAndroidConfig
extends Resource

@export_group("Facebook（接入 Facebook 登录时必填）")
@export var facebook_app_id: String = ""
@export var facebook_client_token: String = ""
