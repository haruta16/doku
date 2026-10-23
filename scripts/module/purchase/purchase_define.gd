## 订阅商品与权益规则目录；集中维护商品编号、套餐档位、折扣展示、每日礼包和合规文案键。

extends RefCounted
class_name PurchaseDefine

enum Tier { WEEK, MONTH, YEAR }

const TIER_COUNT: int = 3

const TIER_NOMINAL_DAYS: Array = [7, 30, 365]

const ORIGINAL_PRICE_USD: Array = [6.99, 27.99, 363.99]

const REAL_PRICE_USD_PRO: Array = [6.99, 14.99, 69.99]

const REAL_PRICE_USD_BASE: Array = [3.99, 7.99, 34.99]


static func origin_price_multi(is_base: bool, tier: int) -> float:
	if tier < 0 or tier >= TIER_COUNT:
		return 1.0
	var real: Array = REAL_PRICE_USD_BASE if is_base else REAL_PRICE_USD_PRO
	var r: float = float(real[tier])
	if r <= 0.0:
		return 1.0
	return float(ORIGINAL_PRICE_USD[tier]) / r


static func origin_price_multi_of_product_id(product_id: String) -> float:
	if not is_known_product_id(product_id):
		return 1.0
	return origin_price_multi(is_base_product_id(product_id), tier_of_product_id(product_id))


static func discount_percent_from_multi(multi: float) -> int:
	if multi <= 1.0:
		return 0
	var percent: float = (1.0 - 1.0 / multi) * 100.0
	return roundi(percent / 10.0) * 10


static func discount_percent(is_base: bool, tier: int) -> int:
	return discount_percent_from_multi(origin_price_multi(is_base, tier))


static func sub_type_of_tier(tier: int) -> String:
	match tier:
		Tier.WEEK:
			return Tracker.SubscriptionType.WEEKLY
		Tier.MONTH:
			return Tracker.SubscriptionType.MONTHLY
		Tier.YEAR:
			return Tracker.SubscriptionType.YEARLY
	return ""


const SUBSCRIPTION_IDS_ANDROID: Array = [
	"com.oakever.meowdoku.noad_1week",
	"com.oakever.meowdoku.noad_1month",
	"com.oakever.meowdoku.noad_1year",
	"com.oakever.meowdoku.noad_1week_2",
	"com.oakever.meowdoku.noad_1month_2",
	"com.oakever.meowdoku.noad_1year_2",
]
const SUBSCRIPTION_IDS_IOS: Array = [
	"com.oakever.meowdoku.noad_1week",
	"com.oakever.meowdoku.noad_1month",
	"com.oakever.meowdoku.noad_1year",
	"com.oakever.meowdoku.noad_1week_2",
	"com.oakever.meowdoku.noad_1month_2",
	"com.oakever.meowdoku.noad_1year_2",
]

const BASE_SUFFIX: String = "_2"

const PERIOD_MARKERS: Array = ["noad_1week", "noad_1month", "noad_1year"]


static func is_known_product_id(product_id: String) -> bool:
	if product_id.is_empty():
		return false
	for marker: String in PERIOD_MARKERS:
		if product_id.contains(marker):
			return true
	return false


static func is_base_product_id(product_id: String) -> bool:
	return product_id.ends_with(BASE_SUFFIX)


static func is_base_edition(product_id: String) -> bool:
	if not is_known_product_id(product_id):
		return true
	return is_base_product_id(product_id)


static func tier_of_product_id(product_id: String) -> int:
	for tier: int in PERIOD_MARKERS.size():
		if product_id.contains(String(PERIOD_MARKERS[tier])):
			return tier
	return -1


static func real_price_usd(product_id: String) -> float:
	var tier: int = tier_of_product_id(product_id)
	if tier < 0:
		return 0.0
	var table: Array = REAL_PRICE_USD_BASE if is_base_product_id(product_id) else REAL_PRICE_USD_PRO
	return float(table[tier])


static func highest_priced_product_id(product_ids: Array) -> String:
	var best: String = ""
	var best_price: float = 0.0
	for pid: String in product_ids:
		var price: float = real_price_usd(pid)
		if price > best_price:
			best_price = price
			best = pid
	return best


const DAILY_GIFT_BASE: int = 1

const DAILY_GIFT_PRO: int = 2


static func daily_gift_count(product_id: String) -> int:
	return DAILY_GIFT_BASE if is_base_edition(product_id) else DAILY_GIFT_PRO


static func daily_gift_count_by_edition(is_base: bool) -> int:
	return DAILY_GIFT_BASE if is_base else DAILY_GIFT_PRO


static func compliance_key() -> String:
	return "PURCHASE_COMPLIANCE_IOS" if OS.has_feature("ios") else "PURCHASE_COMPLIANCE_ANDROID"


static func manage_guide_key(tier: int) -> String:
	if OS.has_feature("ios"):
		match tier:
			Tier.WEEK:
				return "PURCHASE_MANAGE_IOS_WEEKLY"
			Tier.MONTH:
				return "PURCHASE_MANAGE_IOS_MONTHLY"
			Tier.YEAR:
				return "PURCHASE_MANAGE_IOS_YEARLY"
		return "PURCHASE_MANAGE_IOS_GENERIC"
	match tier:
		Tier.WEEK:
			return "PURCHASE_MANAGE_ANDROID_WEEKLY"
		Tier.MONTH:
			return "PURCHASE_MANAGE_ANDROID_MONTHLY"
		Tier.YEAR:
			return "PURCHASE_MANAGE_ANDROID_YEARLY"
	return "PURCHASE_MANAGE_ANDROID_GENERIC"


const EDITOR_PRICE_PRO: Array = ["$6.99", "$14.99", "$69.99"]

const EDITOR_PRICE_BASE: Array = ["$3.99", "$7.99", "$34.99"]
