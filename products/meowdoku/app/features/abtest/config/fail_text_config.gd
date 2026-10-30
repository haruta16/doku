## 实验配置 fail_text：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name FailTextConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，用原文案
const VALUE_PROGRESS_TEXT: int = 1 # 换成进度鼓励文案
const VALUE_REVIVE_PROMOTE: int = 2 # 鼓励文案 + 突出复活按钮


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "fail_text"
	default_value = VALUE_CONTROL


## 是否显示鼓励文案（档位 >=1）
func should_show_encourage() -> bool:
	return value() >= VALUE_PROGRESS_TEXT


## 是否突出复活入口（档位 2）
func should_show_revive_promote() -> bool:
	return value() == VALUE_REVIVE_PROMOTE
