## 实验配置 rule_text：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name RuleTextConfig

# ---- 分组取值 ----
const VALUE_TEXT: int = 0 # 纯文字展示
const VALUE_THIRD_IMG: int = 1 # 第三条规则用图
const VALUE_ALL_IMG: int = 2 # 全部规则用图
const VALUE_ICON_TEXT: int = 3 # 图标 + 文字
const VALUE_COLLAPSE_10: int = 4 # 第 10 关起折叠规则条
const VALUE_INFO_POPUP: int = 5 # 规则放进信息弹窗
const VALUE_SETTING_ENTRY: int = 6 # 规则挪到设置页入口
const VALUE_SINGLE_SWIPE: int = 7 # 单页滑动查看规则


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "rule_text"
	default_value = VALUE_TEXT
