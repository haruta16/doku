## 内购交易模型：保留订单令牌、原生校验材料和毫秒时间，供去重、发货与权益判断。
class_name UniKitPurchaseTransaction
extends RefCounted

var product_id: String = ""

var token: String = ""
var order_id: String = ""
var purchase_time_ms: int = 0

var inner_order_id: String = ""

var signature: String = ""

var purchase_json: String = ""

var expiration_time_ms: int = 0
var revocation_time_ms: int = 0

var subscription_group_id: String = ""

var is_active_purchase: bool = false


## 从统一交易字段构建模型，缺失时间使用 0 表示未提供。
static func from_dict(d: Dictionary) -> UniKitPurchaseTransaction:
	var t := UniKitPurchaseTransaction.new()
	t.product_id = str(d.get("productId", ""))
	t.token = str(d.get("token", ""))
	t.order_id = str(d.get("orderId", ""))
	t.purchase_time_ms = int(d.get("purchaseTime", 0))
	t.inner_order_id = str(d.get("innerOrderId", ""))
	t.signature = str(d.get("signature", ""))
	t.purchase_json = str(d.get("purchaseJson", ""))
	t.expiration_time_ms = int(d.get("expirationTime", 0))
	t.revocation_time_ms = int(d.get("revocationTime", 0))
	t.subscription_group_id = str(d.get("subscriptionGroupId", ""))
	return t


## 解析原生交易 JSON，失败时记录原因并返回空交易对象。
static func from_json(json: String) -> UniKitPurchaseTransaction:
	var d: Variant = JSON.parse_string(json)
	if d is Dictionary:
		return from_dict(d)
	push_warning("[UniKit] 内购交易 JSON 解析失败：%s" % json)
	return UniKitPurchaseTransaction.new()
