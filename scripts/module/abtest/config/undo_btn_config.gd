## 实验配置 undo_btn：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name UndoBtnConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，不显示按钮
const VALUE_UNDO_PAID: int = 1 # 撤销上一步，需要消耗道具/广告
const VALUE_HIGHLIGHT_PAID: int = 2 # 只做高亮提示，需要消耗
const VALUE_UNDO_FREE: int = 3 # 撤销上一步，免费
const VALUE_HIGHLIGHT_FREE: int = 4 # 只做高亮提示，免费


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "undo_btn"
	default_value = VALUE_CONTROL
