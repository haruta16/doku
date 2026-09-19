# 应用内评价（不跳商店的评分弹窗）：iOS 走 UniKit 封装，Android 走 InAppReviewPlugin
class_name InAppReviewManager
extends RefCounted


# 取原生插件单例；没装插件就返回 null
static func _plugin() -> Object:
	if Engine.has_singleton("InAppReviewPlugin"):
		return Engine.get_singleton("InAppReviewPlugin")
	return null


# 请求系统评分弹窗；系统可能不弹（有频率限制），这里拿不到结果
static func request_review() -> void:
	if OS.has_feature("ios"):
		UniKitManager.request_store_review()
		return
	var p: Object = _plugin()
	if p == null:
		return
	p.requestReview()
