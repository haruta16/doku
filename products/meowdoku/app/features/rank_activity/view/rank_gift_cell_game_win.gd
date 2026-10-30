## 单局胜利的领奖台单元；根据当前排名展示头像与对应入场动画。

extends UIChildWindow

const _PODIUM_ANIMS: Array[StringName] = [&"AppearFirst", &"AppearSecond", &"AppearThird"]

var _rank: int = 1

@onready var _overlay: ColorRect = $Overlay
@onready var _podium: Control = $Podium
@onready var _anim: AnimationPlayer = $AnimationPlayer


func setup(top3_infos: Array, rank: int = 1) -> void:
	_rank = rank
	if _podium != null:
		_podium.apply_top3(top3_infos)

	if _overlay != null:
		_overlay.visible = true


func play_appear() -> void:
	var anim: StringName = _PODIUM_ANIMS[clampi(_rank - 1, 0, _PODIUM_ANIMS.size() - 1)]
	if _anim == null or not _anim.has_animation(anim):
		push_error("rank_gift_cell_game_win: 缺 %s 动画（rank=%d），登台态无表现" % [anim, _rank])
		return
	_anim.play(anim)
	await _anim.animation_finished
