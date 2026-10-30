## 每日挑战参与人数条：组合格式化人数与头像堆叠，并适配文本宽度。
extends HBoxContainer
class_name DcPlayersJoinedRow

@onready var _count_label: RichTextLabel = $CountLabel
@onready var _avatar_stack: Control = $AvatarStack
@onready var _avatar_rects: Array[TextureRect] = [
	$AvatarStack/Avatar0,
	$AvatarStack/Avatar1,
	$AvatarStack/Avatar2,
	$AvatarStack/Avatar3,
]

const _NUM_COLOR: String = "#566DC9"
const _TEXT_COLOR: String = "#93A6F1"

const _FALLBACK_TEMPLATE: String = "%s players joined today"

const _MIN_FONT_SIZE: int = 20

var _base_font_size: int = 0

@export var avatar_textures: Array[Texture2D] = []

var _follow_host: CanvasItem = null


func follow_host(host: CanvasItem) -> void:
	_follow_host = host

	process_priority = 100 if host != null else 0
	set_process(host != null)
	if host != null:
		_sync_from_host()


func _process(_delta: float) -> void:
	if _follow_host == null or not is_instance_valid(_follow_host):
		set_process(false)
		return
	_sync_from_host()


func sync_now() -> void:
	if _follow_host == null or not is_instance_valid(_follow_host):
		return
	_sync_from_host()


func _sync_from_host() -> void:
	modulate = _follow_host.modulate
	z_index = _host_effective_z()


func _host_effective_z() -> int:
	var z: int = 0
	var cur: CanvasItem = _follow_host
	while cur != null:
		z += cur.z_index
		if not cur.z_as_relative:
			break
		cur = cur.get_parent() as CanvasItem
	return z


func refresh(state: int) -> void:
	if not ABTestManager.dc_number.is_count_visible() or state == DailyEntryState.State.LOCKED:
		visible = false
		return
	var num_text: String = DcPlayersCount.display_text(
		GameState.get_first_open_time_ms(), Time.get_datetime_dict_from_system()
	)
	if num_text.is_empty():
		visible = false
		return
	var num_bb: String = "[b][color=%s]%s[/color][/b]" % [_NUM_COLOR, num_text]

	var tpl: String = tr("DC_PLAYERS_JOINED")
	if not tpl.contains("%s"):
		tpl = _FALLBACK_TEMPLATE

	var parts: PackedStringArray = tpl.split("%s", true, 1)
	var prefix: String = parts[0]
	var suffix: String = parts[1] if parts.size() > 1 else ""
	_count_label.text = "[color=%s]%s[/color]" % [_TEXT_COLOR, tpl % num_bb]
	_avatar_stack.visible = ABTestManager.dc_number.has_avatars()
	visible = true
	_fit_single_line(num_text, prefix, suffix)


func _fit_single_line(num_text: String, prefix: String, suffix: String) -> void:
	if _base_font_size <= 0:
		_base_font_size = _count_label.get_theme_font_size(&"normal_font_size")
	if _base_font_size <= 0 or size.x <= 0.0:
		return
	var available: float = size.x
	if _avatar_stack.visible:
		available -= _avatar_stack.custom_minimum_size.x + get_theme_constant(&"separation")
	var bold_font: Font = _count_label.get_theme_font(&"bold_font")
	var normal_font: Font = _count_label.get_theme_font(&"normal_font")
	var fs: int = _MIN_FONT_SIZE
	for candidate: int in range(_base_font_size, _MIN_FONT_SIZE - 1, -1):
		var w: float = (
			bold_font.get_string_size(num_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, candidate).x
			+ normal_font.get_string_size(prefix, HORIZONTAL_ALIGNMENT_LEFT, -1.0, candidate).x
			+ normal_font.get_string_size(suffix, HORIZONTAL_ALIGNMENT_LEFT, -1.0, candidate).x
		)
		if w <= available:
			fs = candidate
			break
	_count_label.add_theme_font_size_override(&"normal_font_size", fs)
	_count_label.add_theme_font_size_override(&"bold_font_size", fs)


func roll_avatars() -> void:
	if avatar_textures.size() < _avatar_rects.size():
		return
	var pool: Array[Texture2D] = avatar_textures.duplicate()
	pool.shuffle()
	for i: int in _avatar_rects.size():
		_avatar_rects[i].texture = pool[i]
