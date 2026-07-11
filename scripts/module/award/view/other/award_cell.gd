extends UIChildWindow

const _ICON_Y_BIAS: float = -63.21

const _ICON_BY_KIND: Dictionary = {
	"locate": [preload("res://assets/sprites/game/tool_cat_item.png"), Vector2(106, 106)],
	"hint": [preload("res://assets/sprites/game/icon_hint_lamp.png"), Vector2(67, 106)],
	"undo": [preload("res://assets/sprites/game/icon_undo.png"), Vector2(92, 90)],
}

@onready var _icon: TextureRect = $IconImg
@onready var _count_txt: Label = $CountTxt


func on_show(params: Dictionary = {}) -> void:
	set_award(str(params.get("kind", "")), int(params.get("count", 0)))


func set_award(kind: String, count: int) -> void:
	if _count_txt != null:
		_count_txt.text = str(count)
	var entry: Variant = _ICON_BY_KIND.get(kind, null)
	if entry == null:
		push_warning("[AwardCell] unknown kind: %s" % kind)
		if _icon != null:
			_icon.texture = null
		return
	var tex: Texture2D = entry[0]
	var size: Vector2 = entry[1]
	if _icon == null:
		return
	_icon.texture = tex
	_icon.offset_left = -size.x * 0.5
	_icon.offset_top = _ICON_Y_BIAS - size.y * 0.5
	_icon.offset_right = size.x * 0.5
	_icon.offset_bottom = _ICON_Y_BIAS + size.y * 0.5
