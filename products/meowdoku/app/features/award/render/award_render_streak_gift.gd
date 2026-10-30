## 「签到宝箱」渲染：打开奖励页展示道具，玩家领取（或看广告翻倍）后才入账
extends AwardRender
class_name AwardRenderStreakGift


## 宝箱形态不在注入时展示，等外部显式 show_award
func _on_set_info() -> void:
	pass


## 打开奖励页，并把「入账」回调交给它
func _on_show_award(_display_params: Dictionary) -> void:
	var uid: int = get_uid()
	var items: Array = get_items()
	# 页面取不到就报错返回（不能静默吞掉）
	# 数据在 on_show 中装配，window_shown 监听重开其他奖励时，旧 Render 不再覆盖它。
	var page := UIManager.show_ui(UiName.AWARD, {"items": items, "uid": uid, "on_persisted": _on_page_closed})
	if page == null:
		push_error("AwardRenderStreakGift: show_ui(AWARD) returned null, uid=%d" % uid)



## 奖励页关闭 → 入账并发 award_end
func _on_page_closed() -> bool:
	if not persistent_award():
		return false
	award_end.emit(get_uid())
	return true
