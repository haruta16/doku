## 订阅模块的本地缓存：订阅标识、价格实验锁、礼包领取日期等；商店状态仍需由原生 SDK 刷新。

class_name PurchaseData
extends RefCounted

var vip_active: bool = false

var vip_daily_gift_last_claim_date: String = ""

var vip_sub_inter_last_show_date: String = ""

var debug_fake_store_purchase: Dictionary = {}

var valid_sub_product_ids: Array = []

var vip_price_ab_lock: int = -1


## 将当前模型转换为字典，供保存或传输层使用；本方法本身不写磁盘。
func to_dict() -> Dictionary:
	return {
		"vip_active": vip_active,
		"vip_daily_gift_last_claim_date": vip_daily_gift_last_claim_date,
		"vip_sub_inter_last_show_date": vip_sub_inter_last_show_date,
		"debug_fake_store_purchase": debug_fake_store_purchase,
		"valid_sub_product_ids": valid_sub_product_ids,
		"vip_price_ab_lock": vip_price_ab_lock,
	}


## 从字典恢复模型，并按这里定义的默认值兼容缺失字段；返回对象尚未自动写回存档。
static func from_dict(d: Dictionary) -> PurchaseData:
	var p := PurchaseData.new()
	p.vip_active = bool(d.get("vip_active", false))
	p.vip_daily_gift_last_claim_date = str(d.get("vip_daily_gift_last_claim_date", ""))
	p.vip_sub_inter_last_show_date = str(d.get("vip_sub_inter_last_show_date", ""))
	p.debug_fake_store_purchase = d.get("debug_fake_store_purchase", {})
	p.valid_sub_product_ids = d.get("valid_sub_product_ids", [])
	p.vip_price_ab_lock = int(d.get("vip_price_ab_lock", -1))
	return p
