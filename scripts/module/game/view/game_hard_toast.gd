# 高难度关卡的 Toast：只提供动画名、埋点名与文案节点路径，交互逻辑全在 BaseGameToast
class_name GameHardToast
extends BaseGameToast

# ---- 外观配置 ----
const APPEAR_ANIM: StringName = &"Beginning" # 场景里的入场动画


# 使用的入场动画名
func _appear_anim() -> StringName:
	return APPEAR_ANIM


# 埋点用的弹窗名
func _dlg_name() -> String:
	return Tracker.Dlg.GAME_HARD_TOAST


# 文案节点在卡片下的相对路径
func _label_subpath() -> String:
	return "PanelContainer/VBoxContainer/Label"
