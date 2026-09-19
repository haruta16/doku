# BBCode 自定义效果 breath（@tool）：用 sin(elapsed_time * freq) 缩放字形，做呼吸 / 脉动效果
@tool
class_name RichTextBreath
extends RichTextEffect

var bbcode := "breath" # 效果名：正文里写 [breath ...]...[/breath] 触发


# 对每个字形算瞬时缩放并写回 transform；group=true 时再补横向偏移，让缩放以整组中心为轴
func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var amp: float = char_fx.env.get("amp", 0.2) # 缩放振幅（相对量）
	var freq: float = char_fx.env.get("freq", 2.0) # 角频率（弧度/秒）
	var base: float = char_fx.env.get("base", 1.0) # 基础缩放倍数，1.0 为原始大小
	var group: bool = bool(char_fx.env.get("group", false)) # 整组模式：所有字用同一个相位，额外做横向补偿
	var char_w: float = char_fx.env.get("char_w", 32.0) # 单字宽度（像素），横向补偿用
	var count: int = int(char_fx.env.get("count", 0)) # 整组字数，用来求组中心

	var s: float = base + sin(char_fx.elapsed_time * freq) * amp # 瞬时缩放 s = base + amp * sin(freq * t)

	char_fx.transform = char_fx.transform.scaled_local(Vector2(s, s)) # 绕字形自身原点缩放

	if group:
		var anchor: float = (count - 1) * 0.5 if count > 0 else 0.0 # 以组中心为锚：按下标把字往外推，抵消缩放造成的间距变化
		char_fx.offset.x += (char_fx.relative_index - anchor) * char_w * (s - 1.0)

	return true
