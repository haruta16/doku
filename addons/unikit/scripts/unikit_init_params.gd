## UniKit 初始化参数：汇总统计标签、广告配置和商品目录，并转换为原生协议字段。
@tool
class_name UniKitInitParams
extends RefCounted

var production_id: String = ""
var app_store_id: String = ""
var app_store_url: String = ""

var first_open_time_ms: int = 0

var is_debug: bool = false
var is_show_log: bool = false

var is_update_by_account_id: bool = true

var is_grt_channel_rule: bool = false

var is_switch_ad_config: bool = false

var filter_group_keys: PackedStringArray = PackedStringArray()

var variable_tags: Dictionary = {}
var variable_list_tags: Dictionary = {}
var fixed_tags: Dictionary = {}
var fixed_list_tags: Dictionary = {}

var is_late_init_purchase: bool = true

var is_purchase_custom_verify: bool = false

var entitled_product_ids: PackedStringArray = PackedStringArray()
var consumable_product_ids: PackedStringArray = PackedStringArray()
var subscription_product_ids: PackedStringArray = PackedStringArray()

var is_auto_finish_transaction_enabled: bool = true


## 按当前构建类型初始化调试与日志开关。
func _init() -> void:
	is_debug = OS.is_debug_build()
	is_show_log = OS.is_debug_build()


## 将脚本命名转换为原生初始化字段，包含商品分类和交易完成策略。
func to_json_dict() -> Dictionary:
	return {
		"productionId": production_id,
		"appStoreId": app_store_id,
		"appStoreURL": app_store_url,
		"firstOpenTime": first_open_time_ms,
		"isDebug": is_debug,
		"isShowLog": is_show_log,
		"isUpdateByAccountId": is_update_by_account_id,
		"isGRTChannelRule": is_grt_channel_rule,
		"isSwitchAdConfig": is_switch_ad_config,
		"filterGroupKeyList": _to_array(filter_group_keys),
		"variableTags": variable_tags,
		"variableListTags": variable_list_tags,
		"fixedTags": fixed_tags,
		"fixedListTags": fixed_list_tags,
		"isLateInitPurchase": is_late_init_purchase,
		"isPurchaseCustomVerify": is_purchase_custom_verify,
		"entitledProductList": _to_array(entitled_product_ids),
		"consumableProductList": _to_array(consumable_product_ids),
		"subscriptionProductList": _to_array(subscription_product_ids),
		"isAutoFinishTransactionEnabled": is_auto_finish_transaction_enabled,
	}


## 把紧凑字符串数组转换为普通数组供 JSON 序列化。
func _to_array(p: PackedStringArray) -> Array:
	var a: Array = []
	for s in p:
		a.append(s)
	return a
