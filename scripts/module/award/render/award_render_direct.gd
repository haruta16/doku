# 「直接到账」渲染：数据一注入就立刻入账，不弹任何界面
extends AwardRender
class_name AwardRenderDirect


# 注入数据即触发一次 show_award → 立刻入账
func _on_set_info() -> void:
	AwardManager.show_award(get_uid())


# 入账并发 award_end，调用方不用等界面
func _on_show_award(_display_params: Dictionary) -> void:
	persistent_award()
	award_end.emit(get_uid())
