extends AbConfigBase
class_name DcLevelConfig















const VALUE_CONTROL: int = 0
const VALUE_TIERED_10: int = 1
const VALUE_TIERED_12_EASY: int = 2
const VALUE_TIERED_12_HARD: int = 3
const VALUE_RANDOM: int = 4

func _init() -> void :
    key = "dc_level"
    default_value = VALUE_CONTROL
    timing = ABTestManager.TIMING_GAME_START_DC


func is_override_enabled() -> bool:
    return value() != VALUE_CONTROL




func get_pool_size(current_level: int, day_seed: int) -> int:
    match value():
        VALUE_TIERED_10:
            if current_level <= 200:
                return 10
            return 12
        VALUE_TIERED_12_EASY:
            return 12
        VALUE_TIERED_12_HARD:
            return 12
        VALUE_RANDOM:

            return 10 if (day_seed % 2 == 0) else 12
        _:
            return 10




func get_pool_rank(current_level: int, day_seed: int) -> int:
    match value():
        VALUE_TIERED_10:
            if current_level <= 50:
                return 3
            elif current_level <= 100:
                return 4
            else:
                return 5
        VALUE_TIERED_12_EASY:
            if current_level <= 100:
                return 3
            else:
                return 4
        VALUE_TIERED_12_HARD:
            if current_level <= 50:
                return 3
            elif current_level <= 100:
                return 4
            else:
                return 5
        VALUE_RANDOM:

            var r: = (day_seed + 1) % 10
            if r < 4:
                return 3
            elif r < 8:
                return 4
            else:
                return 5
        _:
            return 3





func use_gc_bank(sz: int, day_offset: int) -> bool:
    if sz == 10:
        return true
    else:
        return day_offset % 2 != 0
