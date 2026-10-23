## UniKit Android 导出配置资源：集中提供统计、广告、推送与平台接入字段。
@tool
class_name UniKitAndroidConfig
extends Resource

@export_group("Common（必填）")

@export var production_id: String = ""

@export_group("Analyze（必填）")
@export var analyze_key_id: String = ""
@export var analyze_secret: String = ""
@export var analyze_af_dev_key: String = ""

@export_group("Push（必填）")
@export var push_key_id: String = ""
@export var push_secret: String = ""

@export var notification_small_icon_name: String = "notification_small_icon"

@export var notification_icon_bg_color: String = ""

@export_group("AdMob（必填）")

@export var admob_app_id: String = ""

@export_group("广告 SDK 大版本")

@export_enum("AD6", "AD7") var ad_major_version: int = 1

@export_group("TikTok（可空）")
@export var tiktok_app_id: String = ""
@export var tiktok_secret: String = ""


## 返回缺失的必填字段名称，供 Inspector 和导出器向使用者说明配置问题。
func validate() -> Array[String]:
	var errors: Array[String] = []
	if production_id.is_empty():
		errors.append("production_id")
	if analyze_key_id.is_empty():
		errors.append("analyze_key_id")
	if analyze_secret.is_empty():
		errors.append("analyze_secret")
	if analyze_af_dev_key.is_empty():
		errors.append("analyze_af_dev_key")
	if push_key_id.is_empty():
		errors.append("push_key_id")
	if push_secret.is_empty():
		errors.append("push_secret")
	if notification_small_icon_name.is_empty():
		errors.append("notification_small_icon_name")
	if admob_app_id.is_empty():
		errors.append("admob_app_id")
	return errors
