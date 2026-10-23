## 躲猫猫的持久化状态；保存领取日期、猫咪是否出现、道具位置及本次是否已交互。

class_name PeekabooData
extends RefCounted

var claimed_date: String = ""

var cat_present: bool = false

var prop_index: int = 0

var pos_index: int = 0

var interacted: bool = false


## 将当前模型转换为字典，供保存或传输层使用；本方法本身不写磁盘。
func to_dict() -> Dictionary:
	return {
		"claimed_date": claimed_date,
		"cat_present": cat_present,
		"prop_index": prop_index,
		"pos_index": pos_index,
		"interacted": interacted,
	}


## 从字典恢复模型，并按这里定义的默认值兼容缺失字段；返回对象尚未自动写回存档。
static func from_dict(d: Dictionary) -> PeekabooData:
	var o := PeekabooData.new()
	o.claimed_date = str(d.get("claimed_date", o.claimed_date))
	o.cat_present = bool(d.get("cat_present", o.cat_present))
	o.prop_index = int(d.get("prop_index", o.prop_index))
	o.pos_index = int(d.get("pos_index", o.pos_index))
	o.interacted = bool(d.get("interacted", o.interacted))
	return o
