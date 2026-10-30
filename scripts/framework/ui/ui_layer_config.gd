## UI 层级表：ui_layer 的六个取值 + 同层 z_index 的步长/上限，数值越大越靠前
## 具体页面落在哪层由场景里的 ui_layer 决定；当前仓库的页面都还是默认 0 层
class_name UILayerConfig
extends RefCounted

const LAYER_DEFAULT: int = 0 # 普通页面层：主页、对局页、设置页这类整页 UI
const LAYER_POPUP: int = 100 # 弹窗层：盖在普通页面之上的弹窗
const LAYER_NOTICE: int = 200 # 通知层：Toast 一类不拦操作的提示
const LAYER_MODAL: int = 300 # 模态层：需要用户先处理的对话框
const LAYER_TUTORIAL: int = 400 # 教程层：新手引导的遮罩与手指提示
const LAYER_LOADING: int = 500 # 加载层：全局 loading，压在所有内容之上

# 逻辑层与实际 z_index 解耦，避免低层重复显示后越过高层。
# 每个窗口给内部控件预留 128 个相对绘制位置（子节点正向累计相对 z 不超过 126）；再多的内容应使用节点顺序。
const Z_STEP: int = 128
const MAX_OPEN_WINDOWS: int = 32 # 保持根节点及其相对控件都在 Godot [-4096, 4095] 范围内。
