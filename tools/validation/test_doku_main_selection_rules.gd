## 主线抽样的独立固定期望；不从被测 recipe/possibilities 推导答案。
## 随机序列取自重构前分支在 Godot 4.6.1 的运行结果；升级引擎 RNG 时需审阅兼容性后更新。
extends SceneTree

const Rules = preload("res://products/meowdoku/gameplay/domain/doku_main_selection_rules.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		printerr("TEST_FAILED: use tools/run_validation.py")
		quit(2)
		return
	_test_hard_choices()
	_test_g_tracking()
	_test_rng_short_circuits()
	_test_rng_sequence()
	print("DOKU MAIN SELECTION RULE TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_hard_choices() -> void:
	# K 组 201 关后达到策略 6 的难关才掷币；两个种子固定覆盖两种档位。
	for sample: Dictionary in [{"seed": 0, "tier": "H", "next": 1327520283}, {"seed": 2, "tier": "N", "next": 3018856683}]:
		var rng := _rng(sample.seed)
		var choice := Rules.select(210, 11, 6, true, true, rng)
		_check(choice == _expected(5, sample.tier, {"hard": true}), "K hard coin result, no daily consumption or G history update: seed %d" % sample.seed)
		_check(rng.randi() == sample.next, "K hard coin consumes exactly the historical random draw")
	var rng := _rng(3)
	var before: int = rng.state
	_check(Rules.select(210, 4, 6, true, true, rng) == _expected(5, "N", {"hard": true}), "D hard level stays N despite strategy 6 and daily easing")
	_check(rng.state == before, "fixed hard tier consumes no random draw")
	_check(Rules.select(209, 10, 6, true, true, rng) == _expected(5, "H", {"hard": true}), "J hard levels use the 9-ending boundary and high tier")
	_check(rng.state == before, "J fixed high tier consumes no random draw")


func _test_g_tracking() -> void:
	# 同一随机数在正常区间命中策略6，在“上次已顶档”的区间只能抽到策略2。
	var rng := _rng(3)
	_check(Rules.select(202, 7, 6, false, false, rng) == _expected(5, "N", {"next_previous_was_max": true}), "G records a sampled strategy-6 maximum")
	_check(rng.randi() == 4290596118, "G ordinary selection preserves the next RNG value")
	rng = _rng(3)
	_check(Rules.select(202, 7, 6, false, true, rng) == _expected(2, "N", {"next_previous_was_max": false}), "G excludes a consecutive original maximum after level 50")
	_check(rng.randi() == 4290596118, "G narrowed range preserves random consumption")
	rng = _rng(3)
	_check(Rules.select(202, 7, 6, true, false, rng) == _expected(4, "H", {"consume_daily": true, "next_previous_was_max": true}), "G records the maximum before daily easing maps strategy6 to strategy5/rank4H")
	_check(rng.randi() == 4290596118, "daily easing does not draw another random number")
	rng = _rng(0)
	_check(Rules.select(22, 7, 3, false, true, rng) == _expected(3, "N", {"next_previous_was_max": true}), "G before level51 may still repeat its original maximum")
	_check(rng.randi() == 1327520283, "pre-level51 G selection preserves RNG order")


func _test_rng_short_circuits() -> void:
	var rng := _rng(0)
	var before: int = rng.state
	_check(Rules.select(52, 7, 3, false, true, rng) == _expected(2, "N", {"next_previous_was_max": false}), "G narrowed singleton range cannot remain at its original strategy3 maximum")
	_check(rng.state == before, "Godot4.6 singleton randi_range consumes no random value")
	rng = _rng(3)
	before = rng.state
	_check(Rules.select(51, 7, 6, true, true, rng) == _expected(1, "N", {"consume_daily": true, "mod1": true}), "early mod1 has fixed strategy2, eases to1 and preserves previous G flag")
	_check(rng.state == before, "mod1 before level101 consumes no random value")
	_check(Rules.select(101, 7, 6, true, true, rng) == _expected(1, "N", {"consume_daily": true, "mod1": true}), "level101 mod1 starts sampling2..3, keeps easing and no G flag update")
	_check(rng.randi() == 4290596118, "level101 mod1 consumes its first random value")


func _test_rng_sequence() -> void:
	# 同一 RNG 穿过抽样、固定难关、掷币、固定首关和 mod1。
	# 每步状态和最后一个数均来自旧分支固定记录，避免仅验证“相同种子重跑相同结果”。
	var rng := _rng(3)
	_check(Rules.select(202, 7, 6, true, false, rng) == _expected(4, "H", {"consume_daily": true, "next_previous_was_max": true}), "sequence: G samples maximum before easing")
	_check(rng.state == 3439983728589879556, "sequence RNG after G")
	_check(Rules.select(210, 4, 6, true, true, rng) == _expected(5, "N", {"hard": true}), "sequence: fixed hard tier")
	_check(rng.state == 3439983728589879556, "sequence RNG unchanged by fixed hard tier")
	_check(Rules.select(210, 11, 6, true, true, rng) == _expected(5, "N", {"hard": true}), "sequence: K coin uses the next draw")
	_check(rng.state == -5030687368022391725, "sequence RNG after K coin")
	_check(Rules.select(1, 1, 6, false, false, rng) == _expected(1, "N"), "sequence: first level stays strategy1")
	_check(rng.state == -5030687368022391725, "sequence RNG unchanged by first level")
	_check(Rules.select(211, 7, 6, true, true, rng) == _expected(2, "N", {"consume_daily": true, "mod1": true}), "sequence: mod1 samples strategy3 then eases to2")
	_check(rng.state == 9031260457417241142 and rng.randi() == 923096409, "sequence RNG state and following value match the historical trace")


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## 只组装测试里的字面期望，不调用任何选题规则。
func _expected(rank: int, tier: String, flags: Dictionary = {}) -> Dictionary:
	var value := {"rank": rank, "tier": tier, "hard": false, "consume_daily": false, "mod1": false, "next_previous_was_max": null}
	value.merge(flags, true)
	return value


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("TEST_FAILED: " + message)
