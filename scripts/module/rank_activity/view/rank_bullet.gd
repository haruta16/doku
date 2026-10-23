## 点赞弹幕节点；把点赞信息组装为带图标的富文本，并控制横向运动与停止。

class_name RankBullet
extends Control

const MIN_WIDTH: float = 0
const HORIZONTAL_PADDING_LEFT: float = 59.0
const HORIZONTAL_PADDING_RIGHT: float = 21.0
const NON_HEART_ICON_PADDING_RIGHT: float = 8.0
const SCREEN_TRAVERSE_DURATION: float = 8.0
const HEART_ICON_WIDTH: float = 74
const HEART_BBCODE: String = "[img=74x65]res://assets/sprites/rank_activity/icon_heart_full.png[/img]"
const INLINE_ICON_TOKENS: Array[String] = ["2", "3", "4", "5"]

@onready var _background: NinePatchRect = $Bg
@onready var _text: RichTextLabel = $Bg/BulletText

var _motion: Tween = null


func set_barrage(barrage: Dictionary) -> void:
	var key: String = str(barrage.get("key", ""))
	var template: String = TranslationServer.translate(key)
	var formatted: Dictionary = format_barrage_text(template, barrage)
	_text.text = str(formatted.rich_text)
	_refresh_size(
		str(formatted.visible_text), float(formatted.icon_width), float(formatted.right_padding)
	)


static func format_barrage_text(template: String, barrage: Dictionary) -> Dictionary:
	var content_args: Array = barrage.get("args", []) as Array
	var rich_text_args: Array = content_args.duplicate()
	var visible_text_args: Array = content_args.duplicate()
	var icon_width: float = 0.0
	var right_padding: float = HORIZONTAL_PADDING_RIGHT
	if bool(barrage.get("append_heart", true)):
		rich_text_args.append(HEART_BBCODE)
		visible_text_args.append("")
		icon_width += HEART_ICON_WIDTH
	var rich_text: String = template % rich_text_args if not rich_text_args.is_empty() else template
	var visible_text: String = (
		template % visible_text_args if not visible_text_args.is_empty() else template
	)

	var named_args: Dictionary = barrage.get("named_args", {}) as Dictionary
	var named_keys: Array = named_args.keys()
	for named_key: Variant in named_keys:
		var marker: String = "{%s}" % str(named_key)
		var replacement: String = str(named_args[named_key])
		rich_text = rich_text.replace(marker, replacement)
		visible_text = visible_text.replace(marker, replacement)

	var inline_icons: Dictionary = barrage.get("inline_icons", {}) as Dictionary
	for token: String in INLINE_ICON_TOKENS:
		var marker: String = "{%s}" % token
		if not rich_text.contains(marker):
			continue
		var icon_result: Dictionary = _inline_icon_bbcode(inline_icons.get(token, {}))
		rich_text = rich_text.replace(marker, str(icon_result.bbcode))
		visible_text = visible_text.replace(marker, "")
		icon_width += float(icon_result.width)
		if float(icon_result.width) > 0.0:
			right_padding = NON_HEART_ICON_PADDING_RIGHT
	return {
		"rich_text": rich_text,
		"visible_text": visible_text,
		"icon_width": icon_width,
		"right_padding": right_padding,
	}


static func _inline_icon_bbcode(icon_value: Variant) -> Dictionary:
	var path: String = ""
	var width: int = 0
	var height: int = 0
	if icon_value is String:
		path = str(icon_value)
		width = int(HEART_ICON_WIDTH)
		height = 65
	elif icon_value is Dictionary:
		var icon: Dictionary = icon_value as Dictionary
		path = str(icon.get("path", ""))
		width = maxi(0, int(icon.get("width", HEART_ICON_WIDTH)))
		height = maxi(0, int(icon.get("height", 65)))
	if path.is_empty() or width <= 0 or height <= 0 or not ResourceLoader.exists(path):
		return {"bbcode": "", "width": 0.0}
	return {
		"bbcode": "[img=%dx%d]%s[/img]" % [width, height, path],
		"width": float(width),
	}


func start_moving(
	start_position: Vector2, end_x: float, duration: float = SCREEN_TRAVERSE_DURATION
) -> void:
	stop_motion()
	position = start_position
	var travel_distance: float = absf(end_x - start_position.x)
	if travel_distance <= 0.0 or duration <= 0.0:
		queue_free()
		return
	_motion = create_tween()
	_motion.set_trans(Tween.TRANS_LINEAR)
	_motion.tween_property(self, "position", Vector2(end_x, start_position.y), duration)
	_motion.tween_callback(queue_free)


func stop_motion() -> void:
	if _motion != null and _motion.is_valid():
		_motion.kill()
	_motion = null


func _refresh_size(
	visible_text: String,
	icon_width: float = HEART_ICON_WIDTH,
	right_padding: float = HORIZONTAL_PADDING_RIGHT
) -> void:
	var font: Font = _text.get_theme_font(&"normal_font")
	var font_size: int = _text.get_theme_font_size(&"normal_font_size")
	var text_width: float = (
		font.get_string_size(visible_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + icon_width
	)
	var bullet_width: float = maxf(
		MIN_WIDTH, ceilf(text_width + HORIZONTAL_PADDING_LEFT + right_padding)
	)
	var bullet_size := Vector2(bullet_width, _background.size.y)
	size = bullet_size
	_background.size = bullet_size
	_text.custom_minimum_size = Vector2(
		maxf(0.0, bullet_width - HORIZONTAL_PADDING_LEFT - right_padding), _text.size.y
	)
