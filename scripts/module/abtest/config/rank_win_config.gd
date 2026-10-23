## 实验配置 rank_win：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name RankWinConfig

const VALUE_CONTROL: int = 0
const VALUE_TIER5_LINEAR: int = 1
const VALUE_TIER5_STEEP: int = 2
const VALUE_TIER3: int = 3

const _STREAK_TABLES: Dictionary = {
	VALUE_TIER5_LINEAR: [1, 2, 3, 4, 5],
	VALUE_TIER5_STEEP: [1, 2, 4, 8, 10],
	VALUE_TIER3: [1, 2, 3],
}

const _BOOST_SPECS: Dictionary = {
	VALUE_TIER5_LINEAR: {"a2": [0.35, 0.55], "a3": [0.6, 0.9], "k": 0.5},
	VALUE_TIER5_STEEP: {"a2": [0.4, 0.6], "a3": [0.7, 1.0], "k": 0.8},
	VALUE_TIER3: {"a2": [0.3, 0.5], "a3": [0.5, 0.7], "k": 0.3},
}

const _X_BASE_ALPHAS: Dictionary = {
	VALUE_TIER5_LINEAR: [0.4, 0.15, -0.3, -0.3],
	VALUE_TIER5_STEEP: [0.8, 0.3, -0.3, -0.3],
	VALUE_TIER3: [0.24, 0.09, -0.3, -0.3],
}


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "rank_win"
	default_value = VALUE_CONTROL


func is_enabled() -> bool:
	return _STREAK_TABLES.has(int(value()))


func streak_table() -> Array:
	return (_STREAK_TABLES.get(int(value()), []) as Array).duplicate()


func boost_spec() -> Dictionary:
	return (_BOOST_SPECS.get(int(value()), {}) as Dictionary).duplicate(true)


func x_base_rule() -> Dictionary:
	var table: Array = streak_table()
	if table.is_empty():
		return {}
	return {"alpha": (_X_BASE_ALPHAS[int(value())] as Array).duplicate(), "k": int(table.max())}
