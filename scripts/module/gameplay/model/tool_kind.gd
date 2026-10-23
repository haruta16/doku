## 道具标识表：统一定位、提示、老鼠和草稿四种库存与行为使用的字符串。
class_name ToolKind
extends Object

const LOCATE: String = "locate"

const HINT: String = "hint"

const MOUSE: String = "mouse"

const DRAFT: String = "draft"

const ALL: Array[String] = [LOCATE, HINT, MOUSE, DRAFT]


## 检查外部传入的道具标识是否属于受支持集合。
static func is_valid(kind: String) -> bool:
	return kind in ALL
