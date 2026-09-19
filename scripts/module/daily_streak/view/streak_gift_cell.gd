# 宝箱奖励格的视觉件：播一次出现动画后转循环，本身不含业务逻辑
extends UIChildWindow

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _glow_layer_img: TextureRect = $GlowLayerImg # 外发光层
@onready var _treasure_box: Control = $TreasureBox # 宝箱图
@onready var _anim: AnimationPlayer = $AnimationPlayer # 格子动画播放器


# 创建时不需要初始化
func on_create() -> void:
	pass


# 显示时播「出现 → 循环」
func on_show(_params: Dictionary = {}) -> void:
	_play_appear_then_loop()


# 先播 Appear；没有这个动画就直接接循环
func _play_appear_then_loop() -> void:
	if _anim == null:
		return
	if _anim.has_animation(&"Appear"):
		_anim.play(&"Appear")
		await _anim.animation_finished
		if not is_instance_valid(_anim):
			return
	_play_loop()


# 把 Loop 设为线性循环后播放
func _play_loop() -> void:
	if _anim == null or not _anim.has_animation(&"Loop"):
		return
	_anim.get_animation(&"Loop").loop_mode = Animation.LOOP_LINEAR
	_anim.play(&"Loop")


# 隐藏时不需要额外处理
func on_hide() -> void:
	pass


# 销毁时不需要额外处理
func on_destroy() -> void:
	pass
