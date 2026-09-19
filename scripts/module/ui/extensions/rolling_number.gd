# 数字滚动：把 Label 的文本从 from 插值到 to（整数递增），格式化交给调用方给的 fmt
class_name RollingNumber
extends RefCounted

const _META_KEY: StringName = &"_rolling_tween" # 存在 Label 元数据里的补间句柄，用来打断上一次没播完的滚动


# 让 label 从 from 滚到 to（时长单位：秒，默认 0.35）；from 等于 to 就直接写值并返回 null
static func roll(
	label: Label,
	from: int,
	to: int,
	duration: float = 0.35,
	fmt: String = "%d",
	ease_type: Tween.EaseType = Tween.EASE_OUT,
	trans_type: Tween.TransitionType = Tween.TRANS_QUAD
) -> Tween:
	if label == null:
		return null
	if from == to: # 数值没变，不播动画
		label.text = fmt % to # 直接写终值
		return null
	_kill_existing(label) # 先把上一次的滚动杀掉，避免两个补间抢同一个文本
	# 用 Dictionary 做可变捕获（GDScript 的 lambda 是按值捕获变量）
	var value := {"v": from}
	label.text = fmt % from # 先立刻显示起始值，再开始插值
	var tw: Tween = label.create_tween()
	(
		tw
		. tween_method(
			func(v: int) -> void:
				value.v = v
				label.text = fmt % v,
			from,
			to,
			duration
		)
		. set_ease(ease_type)
		. set_trans(trans_type)
	)
	label.set_meta(_META_KEY, tw) # 记下句柄，下次滚动好打断
	# 播完清掉句柄；但要确认这期间没有新的滚动接管过
	tw.finished.connect(
		func() -> void:
			if label != null and label.get_meta(_META_KEY, null) == tw:
				label.remove_meta(_META_KEY)
	)
	return tw


# 杀掉该 Label 上没播完的滚动并清掉元数据
static func _kill_existing(label: Label) -> void:
	if not label.has_meta(_META_KEY):
		return
	var old: Tween = label.get_meta(_META_KEY) as Tween
	if old != null and old.is_valid():
		old.kill()
	label.remove_meta(_META_KEY)
