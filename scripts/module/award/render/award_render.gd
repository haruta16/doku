extends RefCounted
class_name AwardRender


















signal award_end(uid: int)

var _db_award: Dictionary = {}


func set_info(db_award: Dictionary) -> void :
    _db_award = db_award
    _on_set_info()



func show_award(display_params: Dictionary = {}) -> void :
    _on_show_award(display_params)



func persistent_award() -> void :
    AwardManager._persist_award(get_uid())

func get_uid() -> int:
    return int(_db_award.get("uid", -1))

func get_items() -> Array:
    return _db_award.get("items", [])







func double_award() -> void :
    _db_award["doubled"] = true



func _on_set_info() -> void :
    push_error("AwardRender._on_set_info() must be overridden")

func _on_show_award(_display_params: Dictionary) -> void :
    push_error("AwardRender._on_show_award() must be overridden")
