## 排行榜奖励展示器：把奖励参数交给结算页，页面关闭后完成入账。
extends AwardRender
class_name AwardRenderRankGift


func _on_set_info() -> void:
	pass


func _on_show_award(display_params: Dictionary) -> void:
	var page := UIManager.show_ui(UiName.AWARD, {"rank_mode": true, "items": get_items(), "uid": get_uid(), "on_persisted": _on_page_closed, "display_params": display_params})
	if page != null:
		Tracker.track_dlg_show(Tracker.Dlg.CHALLENGE_REWARD)


func _on_page_closed() -> bool:
	if not persistent_award():
		return false
	award_end.emit(get_uid())
	return true
