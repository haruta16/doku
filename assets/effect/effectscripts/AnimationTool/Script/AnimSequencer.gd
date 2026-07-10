@tool
class_name AnimSequencer
extends Node2D

















signal preset_finished(preset_index: int, preset_name: String)


signal all_finished()





@export_group("播放设置")


@export var auto_play: bool = true


@export_range(0.0, 5.0, 0.01, "suffix:s") var auto_play_delay: float = 0.0


@export_range(0.1, 5.0, 0.1) var speed_scale: float = 1.0


@export var sequence_mode: AnimPreset.PlayMode = AnimPreset.PlayMode.SEQUENTIAL


@export_range(0.0, 2.0, 0.01, "suffix:s") var preset_stagger: float = 0.15


@export var loop: bool = false

@export_group("动效预设列表")



@export var presets: Array[AnimPreset] = []





@export_group("编辑器工具")


@export var editor_preview: bool = false:
    set(v):
        editor_preview = v
        if v and Engine.is_editor_hint():
            play_all()
        elif not v and Engine.is_editor_hint():
            stop()
            _reset_to_end()





var _active_tweens: Array[Tween] = []
var _completed_count: int = 0
var _is_playing: bool = false





func _ready() -> void :
    if Engine.is_editor_hint():
        return
    if auto_play:
        if auto_play_delay > 0:
            await get_tree().create_timer(auto_play_delay).timeout
        play_all()

func _exit_tree() -> void :
    stop()






func play_all() -> void :
    stop()
    if presets.is_empty():
        return

    _is_playing = true
    _completed_count = 0


    for preset in presets:
        if preset:
            preset.setup_start(self)

    match sequence_mode:

        AnimPreset.PlayMode.PARALLEL:
            for i in presets.size():
                _play_preset(i)

        AnimPreset.PlayMode.SEQUENTIAL:
            _play_sequential(0)

        AnimPreset.PlayMode.STAGGER:
            for i in presets.size():
                if i > 0:
                    var timer: = get_tree().create_timer(preset_stagger * i / speed_scale)
                    timer.timeout.connect(_play_preset.bind(i))
                else:
                    _play_preset(i)



func play_preset_at(index: int) -> void :
    if index < 0 or index >= presets.size():
        return
    _play_preset(index)



func play_preset_by_name(preset_name: String) -> void :
    for i in presets.size():
        if presets[i] and presets[i].preset_name == preset_name:
            _play_preset(i)
            return
    push_warning("AnimSequencer: 找不到预设 '%s'" % preset_name)



func stop() -> void :
    for tween in _active_tweens:
        if tween and tween.is_valid():
            tween.kill()
    _active_tweens.clear()
    _is_playing = false



func is_playing() -> bool:
    return _is_playing





func _play_preset(index: int) -> void :
    var preset: = presets[index]
    if preset == null:
        _on_preset_done(index)
        return

    var tween: Tween = preset.build_tween(self)
    tween.set_speed_scale(speed_scale)
    _active_tweens.append(tween)

    tween.finished.connect(_on_preset_done.bind(index))


func _play_sequential(index: int) -> void :
    if index >= presets.size():
        return
    var preset: = presets[index]
    if preset == null:
        _on_preset_done(index)
        return

    var tween: Tween = preset.build_tween(self)
    tween.set_speed_scale(speed_scale)
    _active_tweens.append(tween)

    tween.finished.connect( func():
        _on_preset_done(index)

        if index + 1 < presets.size():
            _play_sequential(index + 1)
    )


func _on_preset_done(index: int) -> void :
    var preset_name: = ""
    if index < presets.size() and presets[index]:
        preset_name = presets[index].preset_name
    preset_finished.emit(index, preset_name)

    _completed_count += 1
    if _completed_count >= presets.size():
        _is_playing = false
        all_finished.emit()
        if loop and not Engine.is_editor_hint():
            play_all()


func _reset_to_end() -> void :
    for preset in presets:
        if preset:
            preset.setup_end(self)
