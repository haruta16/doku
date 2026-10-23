## 排行榜奖励展示器：把奖励参数交给结算页，页面关闭后完成入账。
extends AwardRender
class_name AwardRenderRankGift


func _on_set_info() -> void:
	pass


func _on_show_award(display_params: Dictionary) -> void:
	var uid: int = get_uid()
	var items: Array = get_items()
	var page := UIManager.show_ui(UiName.AWARD)
	if page == null:
		push_error("AwardRenderRankGift: show_ui(AWARD) returned null, uid=%d" % uid)
		return
	if page.has_method("setup_rank_gift"):
		page.setup_rank_gift(items, uid, _on_page_closed, display_params)

		Tracker.track_dlg_show(Tracker.Dlg.CHALLENGE_REWARD)
	else:
		push_error(
			"AwardRenderRankGift: AwardPage missing setup_rank_gift(items, uid, on_persisted, params)"
		)


func _on_page_closed() -> void:
	persistent_award()
	award_end.emit(get_uid())
