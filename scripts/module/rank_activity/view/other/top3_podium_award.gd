## 奖励页面中的前三名头像展示；把排名资料挂载到固定领奖台槽位。

extends Control

const AVATAR_CELL: PackedScene = preload("res://scripts/module/profile/ui/avatar_cell.tscn")

const _GOLD_SCALE: float = 210.0 / 185.0

@onready var _gold_slot: Control = $GoldSofa/AvatarSlot
@onready var _silver_slot: Control = $SilverSofa/AvatarSlot
@onready var _bronze_slot: Control = $BronzeSofa/AvatarSlot

var _gold_avatar: Control = null
var _silver_avatar: Control = null
var _bronze_avatar: Control = null


func _ready() -> void:
	_gold_avatar = _mount_avatar(_gold_slot, _GOLD_SCALE)
	_silver_avatar = _mount_avatar(_silver_slot, 1.0)
	_bronze_avatar = _mount_avatar(_bronze_slot, 1.0)


func _mount_avatar(slot: Control, scale_v: float) -> Control:
	var a: Control = AVATAR_CELL.instantiate()
	a.scale = Vector2(scale_v, scale_v)
	slot.add_child(a)
	return a


func apply_top3(infos: Array) -> void:
	if infos.size() > 0 and _gold_avatar != null and infos[0] != null:
		_gold_avatar.apply_player_info(infos[0])
	if infos.size() > 1 and _silver_avatar != null and infos[1] != null:
		_silver_avatar.apply_player_info(infos[1])
	if infos.size() > 2 and _bronze_avatar != null and infos[2] != null:
		_bronze_avatar.apply_player_info(infos[2])
