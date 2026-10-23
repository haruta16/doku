## 普通档回退规则：当前尺寸与层级没有 N 档题时，放宽为不限制档位。
class_name TierFallbackModifier
extends RefCounted


## 返回档位回退修饰器标识。
func get_modifier_id() -> StringName:
	return &"tier_fallback"


## 非困难关的 N 档在常规与 LK 风格来源都为空时，清空档位限制。
static func apply(ctx: LevelSelectContext) -> void:
	if ctx.is_hard:
		return
	if ctx.tier != "N":
		return
	var sample: Array = BankData.get_levels_by_tier(ctx.sz, ctx.rank, "N")
	if sample.is_empty():
		sample = BankData.get_lk_style_levels_by_tier(ctx.sz, ctx.rank, "N")
	if sample.is_empty():
		ctx.tier = ""
