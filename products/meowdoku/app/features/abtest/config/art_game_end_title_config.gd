## 实验配置 art_game_end_title：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name ArtGameEndTitleConfig

const VALUE_LEGACY: int = 0
const VALUE_OPTIMIZED: int = 1


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "art_game_end_title"
	default_value = VALUE_LEGACY


func is_title_quality_optimized() -> bool:
	return int(value()) == VALUE_OPTIMIZED
