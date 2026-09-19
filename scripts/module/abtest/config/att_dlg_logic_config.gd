# ATT(跟踪授权)弹窗前的自定义引导实验：0=原流程 1=跳过自定义引导直接弹系统框 2=自定义引导换新版样式
extends AbConfigBase
class_name AttDlgLogicConfig

# ---- 分组取值 ----
const VALUE_DEFAULT: int = 0 # 保留原有自定义引导
const VALUE_SKIP_CUSTOM_GUIDE: int = 1 # 跳过自定义引导页，直接请求 ATT
const VALUE_RESTYLED_GUIDE: int = 2 # 仍显示自定义引导，但换成新版样式


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "att_dlg_logic"
	default_value = VALUE_DEFAULT # 默认档：保留原引导流程
	timing = ABTestManager.TIMING_APP_START # 染色时机：冷启动就绪即定档


# 是否跳过自定义引导页
func should_skip_custom_guide() -> bool:
	return value() == VALUE_SKIP_CUSTOM_GUIDE


# 自定义引导是否改用新版样式
func is_custom_guide_restyled() -> bool:
	return value() == VALUE_RESTYLED_GUIDE
