@tool
class_name RichTextBreath
extends RichTextEffect

var bbcode := "breath"


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var amp: float = char_fx.env.get("amp", 0.2)
	var freq: float = char_fx.env.get("freq", 2.0)
	var base: float = char_fx.env.get("base", 1.0)
	var group: bool = bool(char_fx.env.get("group", false))
	var char_w: float = char_fx.env.get("char_w", 32.0)
	var count: int = int(char_fx.env.get("count", 0))

	var s: float = base + sin(char_fx.elapsed_time * freq) * amp

	char_fx.transform = char_fx.transform.scaled_local(Vector2(s, s))

	if group:
		var anchor: float = (count - 1) * 0.5 if count > 0 else 0.0
		char_fx.offset.x += (char_fx.relative_index - anchor) * char_w * (s - 1.0)

	return true
