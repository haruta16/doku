# 胜利 Toast：显示结算文案并把其中的数字染色；入场/退场共用一段动画，靠 Mark 标记切分
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
# 设置文案（自动给数字上色）
func set_message(text: String) -> void:
	if _msg_txt == null:
		return
	_msg_txt.text = _wrap_numbers_with_color(text)


# ================= 数字染色 =================
# 把文本里的数字/百分比包一层 color 标签；highlight_color 为白色时原样返回
func _wrap_numbers_with_color(text: String) -> String:
	if highlight_color == Color.WHITE or _NUMBER_RE == null:
		return text
	var hex: String = "#" + highlight_color.to_html(false)
	var out: String = ""
	# pos 记录上一段已拷贝到的位置
	var pos: int = 0
	for m: RegExMatch in _NUMBER_RE.search_all(text):
		var s: int = m.get_start()
		var e: int = m.get_end()
		out += text.substr(pos, s - pos)
		out += "[color=%s]%s[/color]" % [hex, text.substr(s, e - s)]
		pos = e
	out += text.substr(pos)
	return out


# 显示 Toast；兄弟 Toast 还开着就先关掉它
func show_toast(_params: Dictionary = {}) -> void:
	if sibling_toast != null and is_instance_valid(sibling_toast) and sibling_toast.visible:
		if sibling_toast.has_method("hide_toast"):
			sibling_toast.hide_toast()
	visible = true
	if _anim != null and _anim.has_animation(_ANIM_NAME):
		_anim.play_section_with_markers(_ANIM_NAME, &"", _MARK)


# 隐藏 Toast（播到 Mark 标记为止）
func hide_toast() -> void:
	if not visible:
		return
	if _anim != null and _anim.has_animation(_ANIM_NAME):
		_anim.play_section_with_markers(_ANIM_NAME, _MARK, &"")


# 是否正在显示
func is_showing() -> bool:
	return visible
