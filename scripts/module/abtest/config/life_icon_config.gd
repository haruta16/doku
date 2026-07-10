extends AbConfigBase
class_name LifeIconConfig












const VALUE_HEART: int = 0
const VALUE_FISH: int = 1
const VALUE_LIGHTNING: int = 2

func _init() -> void :
    key = "life_icon"
    default_value = VALUE_FISH
    timing = ABTestManager.TIMING_GAME_START


func is_fish_life_bar() -> bool:
    return value() == VALUE_FISH


func is_lightning_life_bar() -> bool:
    return value() == VALUE_LIGHTNING
