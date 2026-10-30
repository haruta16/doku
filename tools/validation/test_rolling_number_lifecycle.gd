## RollingNumber interrupted tweens must not retain themselves or overwrite a direct value.
extends SceneTree

const Rolling = preload("res://scripts/framework/ui/extensions/rolling_number.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var label := Label.new()
	root.add_child(label)
	var old: Tween = Rolling.roll(label, 0, 100, 10.0)
	var old_ref: WeakRef = weakref(old)
	_check(old != null, "changing value starts a tween")
	Rolling.roll(label, 7, 7)
	_check(label.text == "7" and not label.has_meta(Rolling._META_KEY), "same-value replacement cancels old animation")
	old = null
	for frame in 4:
		await process_frame
	_check(label.text == "7", "canceled tween cannot overwrite direct value")
	_check(old_ref.get_ref() == null, "killed tween has no self-referencing signal cycle")
	var active: Tween = Rolling.roll(label, 0, 100, 10.0)
	var active_ref: WeakRef = weakref(active)
	active = null
	label.queue_free()
	for frame in 4:
		await process_frame
	_check(active_ref.get_ref() == null, "destroyed label releases its bound tween")
	print("ROLLING NUMBER LIFECYCLE TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TEST_FAILED: " + message)
