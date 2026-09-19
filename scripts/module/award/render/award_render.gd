# 奖励渲染基类：只负责「把一笔奖励演出来」，入账统一交回 AwardManager
extends RefCounted
class_name AwardRender

# 演出结束（奖励已入账）时发出，携带 uid
signal award_end(uid: int)

# ---- 运行时状态 ----
var _db_award: Dictionary = {} # 本笔奖励的存档条目（uid / items / display_type / reason / bonus_reason）


# ================= 对外接口（AwardManager 调用） =================
# 注入本笔奖励数据，并立刻触发子类的 _on_set_info 钩子
func set_info(db_award: Dictionary) -> void:
	_db_award = db_award
	_on_set_info()


# 触发展示，转发给子类 _on_show_award
func show_award(display_params: Dictionary = {}) -> void:
	_on_show_award(display_params)


# 入账：把本笔奖励的道具写进 GameState（由子类在合适时机调用）
func persistent_award() -> void:
	AwardManager._persist_award(get_uid())


# 本笔奖励的 uid；缺字段时返回 -1
func get_uid() -> int:
	return int(_db_award.get("uid", -1))


# 本笔奖励的道具列表（Dictionary 形态，字段 kind / count）
func get_items() -> Array:
	return _db_award.get("items", [])


# 置翻倍标记：入账时按 bonus_reason 再发一份
func double_award() -> void:
	_db_award["doubled"] = true


# ================= 子类钩子（必须覆写） =================
# 数据注入时的回调：基类直接报错，子类必须覆写
func _on_set_info() -> void:
	push_error("AwardRender._on_set_info() must be overridden")


# 展示时的回调：基类同样只报错，等子类覆写
func _on_show_award(_display_params: Dictionary) -> void:
	push_error("AwardRender._on_show_award() must be overridden")
