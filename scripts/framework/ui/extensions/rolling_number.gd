## 数字滚动动画：在目标数字之间插值，开始新滚动前清理旧动画。
class_name RollingNumber
extends RefCounted

const _META_KEY: StringName = &"_rolling_tween" # 存在 Label 元数据里的补间句柄，用来打断上一次没播完的滚动


static func roll(
	label: Label,
	from: int,
	to: int,
	duration: float = 0.35,
	fmt: String = "%d",
	ease_type: Tween.EaseType = Tween.EASE_OUT,
	trans_type: Tween.TransitionType = Tween.TRANS_QUAD
) -> Tween:
	if not is_instance_valid(label):
		return null
	kill_existing(label)
	if from == to:
		label.text = fmt % to
		return null
	var label_ref: WeakRef = weakref(label)
	label.text = fmt % from
	var tw: Tween = label.create_tween()
	(
		tw
		. tween_method(
			func(v: int) -> void:
				var target: Label = label_ref.get_ref() as Label
				if is_instance_valid(target):
					target.text = fmt % v,
			from,
			to,
			duration
		)
		. set_ease(ease_type)
		. set_trans(trans_type)
	)
	label.set_meta(_META_KEY, tw)
	var tween_ref: WeakRef = weakref(tw)
	tw.finished.connect(
		func() -> void:
			var target: Label = label_ref.get_ref() as Label
			var completed: Tween = tween_ref.get_ref() as Tween
			if is_instance_valid(target) and target.get_meta(_META_KEY, null) == completed:
				target.remove_meta(_META_KEY)
	)
	return tw


static func kill_existing(label: Label) -> void:
	if not is_instance_valid(label):
		return
	if not label.has_meta(_META_KEY):
		return
	var old: Tween = label.get_meta(_META_KEY) as Tween
	if old != null and old.is_valid():
		old.kill()
	label.remove_meta(_META_KEY)
