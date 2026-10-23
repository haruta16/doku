## 第三版通关文案分组：依据表现百分比及相对上次的提升选择夸奖文案。
class_name PassTextStrategyV3G1
extends PassTextStrategyV3


## 75% 以下用普通夸奖；超过上次成绩时优先展示进步，否则按百分比档位选择。
func _percent_scene(pct: float, last: float) -> Dictionary:
	if pct <= 75.0:
		return _pick_pair(_plain_pool())

	if last >= 0.0 and pct > last:
		var diff: float = PassTextStats.round_non_zero_decimal(pct - last)
		return _pick_pair_with_pct_diff(_AWESOME, pct, diff)
	if pct < 83.0:
		return _pick_pair_with_pct(_PERCEPTIVE, pct)
	if pct < 91.0:
		return _pick_pair_with_pct(_INTELLIGENT, pct)
	return _pick_pair_with_pct(_BRILLIANT, pct)
