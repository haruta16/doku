## 一款头像框的存档记录：编号、累计获得次数与形态，支持字典序列化。

class_name AvatarFrame
extends RefCounted

var id: int = 0
var acquired_count: int = -1

var form: int = 0


func _init(p_id: int = 0, p_acquired_count: int = -1, p_form: int = 0) -> void:
	id = p_id
	acquired_count = p_acquired_count
	form = p_form


## 将当前模型转换为字典，供保存或传输层使用；本方法本身不写磁盘。
func to_dict() -> Dictionary:
	return {"id": id, "acquired_count": acquired_count, "form": form}


## 从字典恢复模型，并按这里定义的默认值兼容缺失字段；返回对象尚未自动写回存档。
static func from_dict(d: Dictionary) -> AvatarFrame:
	return AvatarFrame.new(
		int(d.get("id", 0)), int(d.get("acquired_count", -1)), int(d.get("form", 0))
	)
