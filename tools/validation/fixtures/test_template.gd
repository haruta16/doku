## 复制到 tools/validation/test_<name>.gd 后替换待实现检查。
## 仅通过 tools/run_validation.py 运行；不要在日常工程中直接执行或按 F6。
extends SceneTree

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	var project := ProjectSettings.globalize_path("res://").replace("\\", "/")
	if not project.contains("/doku-validation-"):
		printerr("TEST_FAILED: use tools/run_validation.py with an isolated project")
		quit(2)
		return
	_run.call_deferred()


func _run() -> void:
	var fixture := Node.new()
	root.add_child(fixture)

	# 换成被测行为及独立预期；空模板必须失败，不能用恒真断言占位。
	_check(false, "replace this placeholder with a real behavior check")

	# 先取消本测试发起的异步任务并断开外部连接，再释放拥有的节点。
	fixture.queue_free()
	await process_frame
	# 若业务另有 deferred 工作或信号，等待其明确完成；不要靠延长固定睡眠掩盖问题。
	print("TEMPLATE TESTS checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _checks > 0 and _failures == 0 else 1)


func _check(passed: bool, label: String) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("TEST_FAILED: " + label)
