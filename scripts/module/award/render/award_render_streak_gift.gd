extends AwardRender
class_name AwardRenderStreakGift















func _on_set_info() -> void :

    pass

func _on_show_award(_display_params: Dictionary) -> void :
    var uid: int = get_uid()
    var items: Array = get_items()
    var page: = UIManager.show_ui(UiName.AWARD)
    if page == null:
        push_error("AwardRenderStreakGift: show_ui(REWARD) returned null, uid=%d" % uid)
        return
    if page.has_method("setup_streak_gift"):
        page.setup_streak_gift(items, uid, _on_page_closed)
    else:
        push_error("AwardRenderStreakGift: AwardPage missing setup_streak_gift(items, uid, on_persisted)")

func _on_page_closed() -> void :
    persistent_award()
    award_end.emit(get_uid())
