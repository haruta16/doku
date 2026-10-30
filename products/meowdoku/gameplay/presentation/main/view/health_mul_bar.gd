## 多槽生命栏：把生命数量和类型映射到各槽位，并执行损失反馈。
class_name HealthMulBar
extends HealthBarBase

const INF_DISPLAY: int = 99

const _PULSE_SCALE: float = 1.25
const _PULSE_SEC: float = 0.18

@onready var _slot: Control = $HeartBg/LifeSlot
@onready var _count_label: Label = $HeartBg/Label

var _last_shown: int = -1


func slots() -> Array[Control]:
	return [_slot]


func refresh(lives: int) -> void:
	_count_label.text = "x%d" % lives
	_last_shown = lives


func animate_lost(_index: int, lives_after: int = -1) -> void:
	if lives_after >= 0:
		refresh(lives_after)
	if _slot is LifeSlot:
		(_slot as LifeSlot).play_lost_bounce()


func apply_kind(_is_golden: bool) -> void:
	pass
