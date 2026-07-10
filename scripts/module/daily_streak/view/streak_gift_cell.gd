extends UIChildWindow


@onready var _glow_layer_img: TextureRect = $GlowLayerImg
@onready var _treasure_box: Control = $TreasureBox
@onready var _anim: AnimationPlayer = $AnimationPlayer







func on_create() -> void :
    pass


func on_show(_params: Dictionary = {}) -> void :


    _play_appear_then_loop()



func _play_appear_then_loop() -> void :
    if _anim == null:
        return
    if _anim.has_animation(&"Appear"):
        _anim.play(&"Appear")
        await _anim.animation_finished
        if not is_instance_valid(_anim):
            return
    _play_loop()



func _play_loop() -> void :
    if _anim == null or not _anim.has_animation(&"Loop"):
        return
    _anim.get_animation(&"Loop").loop_mode = Animation.LOOP_LINEAR
    _anim.play(&"Loop")


func on_hide() -> void :
    pass


func on_destroy() -> void :
    pass
