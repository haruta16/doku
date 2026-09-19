# 奖励格子：按 kind 换图标并显示数量，供奖励页摆 1~2 个
extends UIChildWindow

# 图标纵向基准偏移（像素）：格子以它为锚点摆图标
const _ICON_Y_BIAS: float = -63.21

# kind → [图标贴图, 图标尺寸(像素)]；键与奖励道具的 kind 对应
const _ICON_BY_KIND: Dictionary = {
	"locate": [preload("res://assets/sprites/game/tool_cat_item.png"), Vector2(106, 106)],
	"hint": [preload("res://assets/sprites/game/icon_hint_lamp.png"), Vector2(67, 106)],
	"undo": [preload("res://assets/sprites/game/icon_undo.png"), Vector2(92, 90)],
}

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _icon: TextureRect = $IconImg # 道具图标
@onready var _count_txt: Label = $CountTxt # 数量文字


# on_show：从 params 取 kind / count 后交给 set_award
func on_show(params: Dictionary = {}) -> void:
	set_award(str(params.get("kind", "")), int(params.get("count", 0)))


# 设置格子外观：未知 kind 会告警并清空图标
func set_award(kind: String, count: int) -> void:
	# 先写数量（图标查不到也要显示数量）
	if _count_txt != null:
		_count_txt.text = str(count)
	var entry: Variant = _ICON_BY_KIND.get(kind, null)
	if entry == null:
		# 未知 kind：清空图标并告警
		push_warning("[AwardCell] unknown kind: %s" % kind)
		if _icon != null:
			_icon.texture = null
		return
	var tex: Texture2D = entry[0]
	var size: Vector2 = entry[1]
	if _icon == null:
		return
	_icon.texture = tex
	# 以格子中心为原点，把图标摆到 _ICON_Y_BIAS 高度
	_icon.offset_left = -size.x * 0.5
	_icon.offset_top = _ICON_Y_BIAS - size.y * 0.5
	_icon.offset_right = size.x * 0.5
	_icon.offset_bottom = _ICON_Y_BIAS + size.y * 0.5
