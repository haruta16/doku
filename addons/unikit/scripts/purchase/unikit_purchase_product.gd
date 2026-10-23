## 商店商品模型：区分商品分类、可展示元数据与最近关联的交易。
class_name UniKitPurchaseProduct
extends RefCounted

const TYPE_UNKNOWN: int = 0
const TYPE_CONSUMABLE: int = 1
const TYPE_ENTITLED: int = 2
const TYPE_SUBSCRIPTION: int = 3

const _TYPE_FROM_NATIVE: Dictionary = {
	"consumable": TYPE_CONSUMABLE,
	"entitled": TYPE_ENTITLED,
	"subscription": TYPE_SUBSCRIPTION,
}

var id: String = ""
var type: int = TYPE_UNKNOWN

var platform: String = ""
var title: String = ""
var description: String = ""
var display_price: String = ""

var price: float = 0.0
var currency_code: String = ""

var subscription_group_id: String = ""

var transaction: UniKitPurchaseTransaction = null

var _has_metadata: bool = false


## 判断是否已取得商店元数据，占位商品不会被当作可展示商品。
func is_available() -> bool:
	return _has_metadata


## 在商店元数据到达前保存配置中的商品标识和类型。
static func placeholder(product_id: String, product_type: int) -> UniKitPurchaseProduct:
	var p := UniKitPurchaseProduct.new()
	p.id = product_id
	p.type = product_type
	return p


## 解析统一商品结构并标记元数据已取得。
static func from_dict(d: Dictionary) -> UniKitPurchaseProduct:
	var p := UniKitPurchaseProduct.new()
	p.id = str(d.get("productId", ""))
	p.type = int(_TYPE_FROM_NATIVE.get(str(d.get("type", "")), TYPE_UNKNOWN))
	p.platform = str(d.get("platform", ""))
	p.title = str(d.get("title", ""))
	p.description = str(d.get("description", ""))
	p.display_price = str(d.get("displayPrice", ""))
	p.price = float(d.get("price", 0.0))
	p.currency_code = str(d.get("priceCurrencyCode", ""))
	p.subscription_group_id = str(d.get("subscriptionGroupId", ""))
	p._has_metadata = true
	return p
