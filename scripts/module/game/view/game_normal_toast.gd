class_name GameNormalToast
extends BaseGameToast

const APPEAR_ANIM: StringName = &"Beginning2"


func _appear_anim() -> StringName:
	return APPEAR_ANIM


func _dlg_name() -> String:
	return Tracker.Dlg.GAME_NORMAL_TOAST


func _label_subpath() -> String:
	return "PanelContainer/Label"


func _apply_text(params: Dictionary) -> void:
	var iq_text_key: String = params.get("iq_text_key", "")
	if iq_text_key != "":
		_label.text = tr(iq_text_key)
	else:
		super._apply_text(params)
