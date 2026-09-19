# 普通关卡 Toast：与高难度版共用基类，额外支持一段 IQ 文案覆盖
class_name GameNormalToast
extends BaseGameToast

# ---- 外观配置 ----
const APPEAR_ANIM: StringName = &"Beginning2" # 场景里的入场动画


# 使用的入场动画名
func _appear_anim() -> StringName:
	return APPEAR_ANIM


# 埋点用的弹窗名
func _dlg_name() -> String:
	return Tracker.Dlg.GAME_NORMAL_TOAST


# 文案节点在卡片下的相对路径
func _label_subpath() -> String:
	return "PanelContainer/Label"


# 文案填充：有 iq_text_key 就用它，否则退回父类的首次尝试文案
func _apply_text(params: Dictionary) -> void:
	# 有 IQ 文案 key → 直接翻译显示
	var iq_text_key: String = params.get("iq_text_key", "")
	if iq_text_key != "":
		_label.text = tr(iq_text_key)
	else:
		super._apply_text(params)
