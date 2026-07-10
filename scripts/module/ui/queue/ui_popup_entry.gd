class_name UIPopupEntry
extends Resource

@export var ui_name: String = ""
@export var priority: int = 0
@export var params: Dictionary = {}
var condition: Callable = Callable()
@export var once_per_session: bool = false
