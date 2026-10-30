## 打卡宝箱提示单元：先播放出现动画，再循环提示可领取奖励。
extends UIChildWindow

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _glow_layer_img: TextureRect = $GlowLayerImg # 外发光层
@onready var _treasure_box: Control = $TreasureBox # 宝箱图
@onready var _anim: AnimationPlayer = $AnimationPlayer # 格子动画播放器
var _appear_callback: Callable = Callable()
var _vibrate_timer: Timer = null
var _appear_generation: int = 0


## 创建时不需要初始化
func on_create() -> void:
	pass


## 显示时播「出现 → 循环」
func on_show(_params: Dictionary = {}) -> void:
	_play_appear_then_loop()


func _play_appear_then_loop() -> void:
	_cancel_appear()
	if _anim == null:
		return
	var generation: int = _appear_generation
	if _anim.has_animation(&"Appear"):
		_anim.play(&"Appear")
		_vibrate_timer = create_countdown(1.67, func() -> void:
			_vibrate_timer = null
			if generation == _appear_generation and is_showing():
				VibrateManager.play_at(VibrateManager.Pos.STREAK_GIFT)
		)
		_appear_callback = func(_animation: StringName) -> void:
			if generation == _appear_generation and is_showing():
				_appear_callback = Callable()
				_play_loop()
		_anim.animation_finished.connect(_appear_callback, CONNECT_ONE_SHOT)
	else:
		_play_loop()


func _cancel_appear() -> void:
	_appear_generation += 1
	if _appear_callback.is_valid() and _anim.animation_finished.is_connected(_appear_callback):
		_anim.animation_finished.disconnect(_appear_callback)
	_appear_callback = Callable()
	if is_instance_valid(_vibrate_timer):
		remove_timer(_vibrate_timer)
	_vibrate_timer = null


## 把 Loop 设为线性循环后播放
func _play_loop() -> void:
	if _anim == null or not _anim.has_animation(&"Loop"):
		return
	_anim.get_animation(&"Loop").loop_mode = Animation.LOOP_LINEAR
	_anim.play(&"Loop")


## 隐藏时撤销动画与震动回调。
func on_hide() -> void:
	_cancel_appear()


## 销毁时同步清理，避免动画 await 持有旧脚本资源。
func on_destroy() -> void:
	_cancel_appear()
