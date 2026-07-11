extends AwardRender
class_name AwardRenderDirect


func _on_set_info() -> void:
	AwardManager.show_award(get_uid())


func _on_show_award(_display_params: Dictionary) -> void:
	persistent_award()
	award_end.emit(get_uid())
