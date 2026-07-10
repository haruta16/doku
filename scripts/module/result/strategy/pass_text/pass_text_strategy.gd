class_name PassTextStrategy
extends RefCounted








static func create() -> PassTextStrategy:
    match ABTestManager.pass_text.value():
        PassTextConfig.VALUE_BEAT_PERCENT:
            return PassTextStrategyV1.new()
        PassTextConfig.VALUE_V2:
            return PassTextStrategyV2.new()
        _:
            return PassTextStrategyV0.new()






func get_win_text(_level_config: Dictionary) -> Dictionary:
    return {"title": "", "body": "", "shown_percent": -1.0}
