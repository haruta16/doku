## 通关消息提示：给数字片段着色，管理提示文字的显示与隐藏。
class_name GameWinToast
extends CanvasLayer

# ---- Inspector 参数 ----
@export var sibling_toast: CanvasLayer = null # 兄弟 Toast：显示前先关掉它，避免叠加

@export var highlight_color: Color = Color.WHITE # 数字高亮色；白色表示不染色

# ---- 常量与缓存 ----
const _ANIM_NAME: StringName = &"GenericPopup" # 弹窗动画名
const _MARK: StringName = &"Mark" # 动画里的分段标记

static var _NUMBER_RE: RegEx = RegEx.create_from_string("\\d+%?") # 匹配数字（可带 %）的正则，静态缓存只建一次

# ---- 子节点引用（按名字在场景里找） ----
@onready var _anim: AnimationPlayer = find_child("AnimationPlayer", true, false) as AnimationPlayer # 动画播放器
@onready var _msg_txt: RichTextLabel = find_child("MessageTxt", true, false) as RichTextLabel # 文案节点


# ================= 对外接口 =================
## 设置文案（自动给数字上色）
func set_message(text: String) -> void:
	if _msg_txt == null:
		return
	_msg_txt.text = _wrap_numbers_with_color(text)


func _wrap_numbers_with_color(text: String) -> String:
	if highlight_color == Color.WHITE or _NUMBER_RE == null:
		return text
	var hex: String = "#" + highlight_color.to_html(false)
	var output: String = ""
	var cursor: int = 0
	var color_depth: int = 0
	while cursor < text.length():
		var tag_start: int = text.find("[", cursor)
		if tag_start < 0:
			var tail: String = text.substr(cursor)
			output += tail if color_depth > 0 else _wrap_plain_numbers(tail, hex)
			break
		var visible_text: String = text.substr(cursor, tag_start - cursor)
		output += visible_text if color_depth > 0 else _wrap_plain_numbers(visible_text, hex)
		var tag_end: int = text.find("]", tag_start)
		if tag_end < 0:
			var remainder: String = text.substr(tag_start)
			output += remainder if color_depth > 0 else _wrap_plain_numbers(remainder, hex)
			break
		var bbcode_tag: String = text.substr(tag_start, tag_end - tag_start + 1)
		output += bbcode_tag
		if bbcode_tag.begins_with("[color="):
			color_depth += 1
		elif bbcode_tag == "[/color]":
			color_depth = maxi(0, color_depth - 1)
		cursor = tag_end + 1
	return output


func _wrap_plain_numbers(visible_text: String, hex_color: String) -> String:
	var output: String = ""
	var cursor: int = 0
	var matches: Array = _NUMBER_RE.search_all(visible_text)
	for match_result: RegExMatch in matches:
		var match_start: int = match_result.get_start()
		var match_end: int = match_result.get_end()
		output += visible_text.substr(cursor, match_start - cursor)
		output += (
			"[color=%s]%s[/color]"
			% [hex_color, visible_text.substr(match_start, match_end - match_start)]
		)
		cursor = match_end
	return output + visible_text.substr(cursor)


## 显示 Toast；兄弟 Toast 还开着就先关掉它
func show_toast(_params: Dictionary = {}) -> void:
	if sibling_toast != null and is_instance_valid(sibling_toast) and sibling_toast.visible:
		if sibling_toast.has_method("hide_toast"):
			sibling_toast.hide_toast()
	visible = true
	if _anim != null and _anim.has_animation(_ANIM_NAME):
		_anim.play_section_with_markers(_ANIM_NAME, &"", _MARK)


## 隐藏 Toast（播到 Mark 标记为止）
func hide_toast() -> void:
	if not visible:
		return
	if _anim != null and _anim.has_animation(_ANIM_NAME):
		_anim.play_section_with_markers(_ANIM_NAME, _MARK, &"")


## 是否正在显示
func is_showing() -> bool:
	return visible
