class_name RollingNumber
extends RefCounted

const _META_KEY: StringName = &"_rolling_tween"


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
	if from == to:
		label.text = fmt % to
		return null
	_kill_existing(label)
	var value := {"v": from}
	label.text = fmt % from
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
	label.set_meta(_META_KEY, tw)
	tw.finished.connect(
		func() -> void:
			if label != null and label.get_meta(_META_KEY, null) == tw:
				label.remove_meta(_META_KEY)
	)
	return tw


static func _kill_existing(label: Label) -> void:
	if not label.has_meta(_META_KEY):
		return
	var old: Tween = label.get_meta(_META_KEY) as Tween
	if old != null and old.is_valid():
		old.kill()
	label.remove_meta(_META_KEY)
