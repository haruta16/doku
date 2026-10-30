## 实验配置 vip_price：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name VipPriceConfig

const VALUE_CONTROL: int = 0
const VALUE_REGULAR: int = 1
const VALUE_REGULAR_WITH_ORIGINAL: int = 2
const VALUE_LOW_PRICE: int = 3
const VALUE_REVIEW_ALL: int = 4


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "vip_price"
	default_value = VALUE_CONTROL


static func entry_enabled_for(v: int) -> bool:
	return v != VALUE_CONTROL


static func uses_low_price_for(v: int) -> bool:
	return v == VALUE_LOW_PRICE


static func show_original_price_for(v: int) -> bool:
	return v == VALUE_REGULAR_WITH_ORIGINAL or v == VALUE_LOW_PRICE


static func uses_scroll_layout_for(v: int) -> bool:
	return v == VALUE_REVIEW_ALL


func uses_low_price_products() -> bool:
	return uses_low_price_for(value())


func should_show_original_price() -> bool:
	return show_original_price_for(value())


func uses_scroll_layout() -> bool:
	return uses_scroll_layout_for(value())
