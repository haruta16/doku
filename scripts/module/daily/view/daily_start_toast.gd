## 每日挑战开局提示：复用游戏提示基类，指定挑战卡片与入场动画。
class_name DailyStartToast
extends BaseGameToast

const APPEAR_ANIM: StringName = &"Beginning"


func _appear_anim() -> StringName:
	return APPEAR_ANIM


func _dlg_name() -> String:
	return Tracker.Dlg.DC_START_TOAST


func _select_variant_card() -> void:
	_label = _card.get_node_or_null("CardDc/PanelContainer/VBoxContainer/Label") as RichTextLabel


func _label_subpaths() -> Dictionary:
	return {}
