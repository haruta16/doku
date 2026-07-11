class_name GameHardToast
extends BaseGameToast

const APPEAR_ANIM: StringName = &"Beginning"


func _appear_anim() -> StringName:
	return APPEAR_ANIM


func _dlg_name() -> String:
	return Tracker.Dlg.GAME_HARD_TOAST


func _label_subpath() -> String:
	return "PanelContainer/VBoxContainer/Label"
