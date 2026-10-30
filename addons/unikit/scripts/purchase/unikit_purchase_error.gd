## 内购错误模型：保留平台原始错误码，并映射为业务可共用的失败原因。
class_name UniKitPurchaseError
extends RefCounted

const REASON_UNKNOWN: int = 0
const REASON_USER_CANCELLED: int = 1
const REASON_PRODUCT_UNAVAILABLE: int = 2
const REASON_PURCHASING_UNAVAILABLE: int = 3
const REASON_EXISTING_PURCHASE_PENDING: int = 4
const REASON_PENDING: int = 5
const REASON_PAYMENT_DECLINED: int = 6
const REASON_DUPLICATE_TRANSACTION: int = 7
const REASON_SIGNATURE_INVALID: int = 8
const REASON_NETWORK_ERROR: int = 9

const ANDROID_PURCHASE_LIST_EMPTY: int = 100

const _ANDROID_REASON: Dictionary = {
	-2: REASON_PURCHASING_UNAVAILABLE,
	-1: REASON_NETWORK_ERROR,
	1: REASON_USER_CANCELLED,
	2: REASON_NETWORK_ERROR,
	3: REASON_PURCHASING_UNAVAILABLE,
	4: REASON_PRODUCT_UNAVAILABLE,
	5: REASON_UNKNOWN,
	6: REASON_UNKNOWN,
	7: REASON_DUPLICATE_TRANSACTION,
	8: REASON_UNKNOWN,
	12: REASON_NETWORK_ERROR,
	100: REASON_UNKNOWN,
	200: REASON_PRODUCT_UNAVAILABLE,
	300: REASON_UNKNOWN,
	400: REASON_PENDING,
}

const _IOS_REASON: Dictionary = {
	-1: REASON_UNKNOWN,
	1: REASON_SIGNATURE_INVALID,
	2: REASON_PURCHASING_UNAVAILABLE,
	1001: REASON_USER_CANCELLED,
	1002: REASON_PAYMENT_DECLINED,
	1003: REASON_PAYMENT_DECLINED,
	1004: REASON_PRODUCT_UNAVAILABLE,
	1005: REASON_PENDING,
	1006: REASON_NETWORK_ERROR,
	1007: REASON_PURCHASING_UNAVAILABLE,
	1010: REASON_PURCHASING_UNAVAILABLE,
	1012: REASON_SIGNATURE_INVALID,
	1013: REASON_PAYMENT_DECLINED,
}

const _IOS_REASON_NAME: Dictionary = {
	"UserCancelled": REASON_USER_CANCELLED,
	"PurchasingUnavailable": REASON_PURCHASING_UNAVAILABLE,
	"PaymentDeclined": REASON_PAYMENT_DECLINED,
}

var code: int = 0
var message: String = ""
var reason: int = REASON_UNKNOWN


## 按平台映射错误码，iOS 明确的原因名称可覆盖整数码推断。
static func from_json(json: String, is_ios: bool = OS.has_feature("ios")) -> UniKitPurchaseError:
	var e := UniKitPurchaseError.new()
	var d: Variant = JSON.parse_string(json)
	if d is Dictionary:
		e.code = int(d.get("errorCode", 0))
		e.message = str(d.get("errorMessage", ""))
	else:
		e.message = json
		push_warning("[UniKit] 内购错误 JSON 解析失败，原文保留：%s" % json)
	var table: Dictionary = _IOS_REASON if is_ios else _ANDROID_REASON
	e.reason = int(table.get(e.code, REASON_UNKNOWN))

	if d is Dictionary:
		var reason_name: String = str((d as Dictionary).get("errorReason", ""))
		if _IOS_REASON_NAME.has(reason_name):
			e.reason = int(_IOS_REASON_NAME[reason_name])
	return e


## 为脚本层前置检查创建失败对象，与原生错误共用返回类型。
static func local(reason_code: int, msg: String) -> UniKitPurchaseError:
	var e := UniKitPurchaseError.new()
	e.code = -1
	e.message = msg
	e.reason = reason_code
	return e
