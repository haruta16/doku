## 普通关开局提示卡：为通用提示流程提供动画名、卡片和文案节点。
class_name GameNormalToast
extends BaseGameToast

# ---- 外观配置 ----
const APPEAR_ANIM: StringName = &"Beginning2" # 场景里的入场动画


## 使用的入场动画名
func _appear_anim() -> StringName:
	return APPEAR_ANIM


## 埋点用的弹窗名
func _dlg_name() -> String:
	return Tracker.Dlg.GAME_NORMAL_TOAST


func _label_subpaths() -> Dictionary:
	return {
		"Card6": "PanelContainer/Label",
		"Card7": "PanelContainer/Label",
		"Card11": "PanelContainer/Label",
	}


func _apply_text(params: Dictionary) -> void:
	var iq_text_key: String = params.get("iq_text_key", "")
	if iq_text_key != "":
		_label.text = TextHighlightRenderer.render(
			ABTestManager.text_highlight, iq_text_key, tr(iq_text_key), "#FFEE00"
		)
	else:
		super._apply_text(params)
