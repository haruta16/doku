## 购买请求参数：携带商品、业务订单和订阅变更信息，附加数据只允许基础类型。
class_name UniKitPurchaseParams
extends RefCounted

var product_id: String = ""

var inner_order_id: String = ""

var old_product_id: String = ""

var extra_data: Dictionary = {}


## 把脚本参数转换为原生购买字段，同时过滤不支持的附加数据。
func to_json_dict() -> Dictionary:
	return {
		"productId": product_id,
		"oldProductId": old_product_id,
		"innerOrderId": inner_order_id,
		"extraData": _sanitized_extra_data(),
	}


## 只保留字符串、数字和布尔值，复杂对象会告警并剔除。
func _sanitized_extra_data() -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in extra_data:
		var v: Variant = extra_data[k]
		match typeof(v):
			TYPE_STRING, TYPE_INT, TYPE_FLOAT, TYPE_BOOL:
				out[str(k)] = v
			_:
				push_warning(
					(
						'[UniKit] purchase extra_data["%s"] 类型 %s 不受支持（仅 String/int/float/bool），已剔除'
						% [k, type_string(typeof(v))]
					)
				)
	return out
