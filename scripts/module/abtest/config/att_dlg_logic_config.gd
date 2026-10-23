## 实验配置 att_dlg_logic：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name AttDlgLogicConfig

# ---- 分组取值 ----
const VALUE_DEFAULT: int = 0 # 保留原有自定义引导
const VALUE_SKIP_CUSTOM_GUIDE: int = 1 # 跳过自定义引导页，直接请求 ATT
const VALUE_RESTYLED_GUIDE: int = 2 # 仍显示自定义引导，但换成新版样式


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "att_dlg_logic"
	default_value = VALUE_SKIP_CUSTOM_GUIDE


## 是否跳过自定义引导页
func should_skip_custom_guide() -> bool:
	return value() == VALUE_SKIP_CUSTOM_GUIDE


## 自定义引导是否改用新版样式
func is_custom_guide_restyled() -> bool:
	return value() == VALUE_RESTYLED_GUIDE
