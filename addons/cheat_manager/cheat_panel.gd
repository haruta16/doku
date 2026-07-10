class_name CheatPanel
extends Control

@onready var _tab_container: TabContainer = $PanelContainer / Margin / VBox / TabContainer
@onready var _cmd_input: LineEdit = $PanelContainer / Margin / VBox / InputRow / CmdInput
@onready var _run_btn: Button = $PanelContainer / Margin / VBox / InputRow / RunBtn
@onready var _close_btn: Button = $PanelContainer / Margin / VBox / TitleRow / CloseBtn

func _ready() -> void :
    visible = false
    _run_btn.pressed.connect(_on_run_pressed)
    _close_btn.pressed.connect(hide)



func open_panel() -> void :
    _rebuild_tabs()
    visible = true

func close_panel() -> void :
    visible = false

func toggle() -> void :
    if visible:
        close_panel()
    else:
        open_panel()





func _rebuild_tabs() -> void :


    for child in _tab_container.get_children():
        _tab_container.remove_child(child)
        child.queue_free()

    for tab in CheatBus.get_tabs():
        var title: String = tab["title"]
        var builder: Callable = tab["builder"]

        var page: = Control.new()
        page.name = title
        var scroll: = ScrollContainer.new()
        scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
        scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
        page.add_child(scroll)
        _tab_container.add_child(page)


        builder.call(scroll, self)





func fill_input(text: String) -> void :
    _cmd_input.text = text

func _on_run_pressed() -> void :
    var raw: = _cmd_input.text.strip_edges()
    if raw.is_empty():
        return
    CheatBus.issue(raw)
    close_panel()
