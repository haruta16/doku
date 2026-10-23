## 活动结束的单人名次展示单元；挂载自身头像并设置名次文本，复用领奖台入场表现。

extends UIChildWindow

const _AVATAR_CELL: PackedScene = preload("res://scripts/module/profile/ui/avatar_cell.tscn")

const _PODIUM_ANIM: StringName = &"Appear"

const _AUTO_CLOSE_SEC: float = 5.0

const _TEXT_KEY_ACTIVITY_END: String = "RANK_PODIUM_FINISH"

const _AVATAR_NATIVE: float = 185.0

signal finished

@onready var _overlay: ColorRect = $Overlay
@onready var _win_text: RichTextLabel = $WinText
@onready var _rank_num: Label = $BronzeSofa/RankNum
@onready var _avatar_slot: Control = $BronzeSofa/AvatarSlot
@onready var _anim: AnimationPlayer = $AnimationPlayer

var _finished: bool = false

var _avatar = null


func setup(rank: int) -> void:
	var r: int = clampi(
		rank,
		RankActivityConfig.END_SOLO_PODIUM_RANK_MIN,
		RankActivityConfig.END_SOLO_PODIUM_RANK_MAX
	)
	_apply_rank_text(r)
	_rank_num.text = str(r)
	_mount_self_avatar()

	if _overlay != null:
		_overlay.visible = true


func play_appear() -> void:
	if _finished:
		return
	if _anim != null and _anim.has_animation(_PODIUM_ANIM):
		AnimUtil.play(_anim, _PODIUM_ANIM)
	else:
		push_error("rank_gift_cell_solo_end: 缺 %s 动画，单人台无表现" % _PODIUM_ANIM)
	await get_tree().create_timer(_AUTO_CLOSE_SEC).timeout
	if not is_instance_valid(self) or _finished:
		return
	_finished = true
	finished.emit()


func _apply_rank_text(r: int) -> void:
	var key: String = _TEXT_KEY_ACTIVITY_END
	var tpl: String = tr(key)
	if tpl.contains("{0}"):
		_win_text.text = tpl.replace("{0}", str(r))
	elif tpl.contains("%d"):
		_win_text.text = tpl % r
	else:
		push_error("rank_gift_cell_solo_end: 文案 %s 缺名次占位符（{0} / %%d），名次未显示" % key)
		_win_text.text = tpl


func _mount_self_avatar() -> void:
	if _avatar != null:
		destroy_child(_avatar)
		_avatar = null
	if _avatar_slot == null:
		return
	var av = create_child(_AVATAR_CELL, {})
	if av == null:
		push_error("rank_gift_cell_solo_end: avatar_cell 创建失败，单人台无头像")
		return
	av.reparent(_avatar_slot, false)
	av.apply_player_info(ProfileService.get_player_info())
	var slot_w: float = _avatar_slot.offset_right - _avatar_slot.offset_left
	var slot_h: float = _avatar_slot.offset_bottom - _avatar_slot.offset_top
	var s: float = (slot_w / _AVATAR_NATIVE) if slot_w > 0.0 else 1.0
	av.scale = Vector2(s, s)
	av.pivot_offset = Vector2(_AVATAR_NATIVE, _AVATAR_NATIVE) * 0.5
	av.position = Vector2(slot_w, slot_h) * 0.5 - av.pivot_offset
	_avatar = av
