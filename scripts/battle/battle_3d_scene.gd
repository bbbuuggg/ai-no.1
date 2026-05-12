extends Node3D
## 3D 牌桌背景 — Boss 全息体旋转动画

@onready var boss_hologram: Node3D = $BossHologram
@onready var outer_ring: CSGTorus3D = $BossHologram/OuterRing
@onready var inner_shape: CSGBox3D = $BossHologram/InnerShape

var rotation_speed: float = 0.5
var ring_speed: float = 1.2
var float_amplitude: float = 0.15
var float_speed: float = 2.0
var base_y: float = 2.0


func _ready() -> void:
	base_y = boss_hologram.position.y


func _process(delta: float) -> void:
	# Boss 主体缓慢旋转
	inner_shape.rotate_y(rotation_speed * delta)
	inner_shape.rotate_x(rotation_speed * 0.3 * delta)

	# 外环快速旋转
	outer_ring.rotate_y(ring_speed * delta)
	outer_ring.rotate_z(ring_speed * 0.5 * delta)

	# 浮动
	boss_hologram.position.y = base_y + sin(Time.get_ticks_msec() * 0.001 * float_speed) * float_amplitude
