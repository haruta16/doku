extends UIFrameWindow







@onready var _bar: Control = $Bar
@onready var _info_label: Label = $Bar / InfoLabel

func on_show(params: Dictionary = {}) -> void :
    visible = true
    var placement_id: String = params.get("placement_id", "banner")
    var position: String = params.get("position", "")
    var anchor_bottom: bool = params.get("anchor_bottom", true)
    var height_base: float = float(params.get("height_base", 180))
    var offset_base: float = float(params.get("offset_base", 0))

    _bar.anchor_left = 0.0
    _bar.anchor_right = 1.0
    _bar.offset_left = 0.0
    _bar.offset_right = 0.0
    if anchor_bottom:

        _bar.anchor_top = 1.0
        _bar.anchor_bottom = 1.0
        _bar.offset_top = - (height_base + offset_base)
        _bar.offset_bottom = - offset_base
    else:

        _bar.anchor_top = 0.0
        _bar.anchor_bottom = 0.0
        _bar.offset_top = offset_base
        _bar.offset_bottom = offset_base + height_base
    _info_label.text = "MOCK Banner  [%s / %s]" % [placement_id, position]
