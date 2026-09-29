extends RigidBody2D
class_name CombatShip

signal destroyed(ship: CombatShip)

var game: Node2D
var player := false
var hp := 120.0
var hull_resistance := 0.15
var energy := 100.0
var overheated: Dictionary = {}
var heat: Dictionary = {}
var disabled: Dictionary = {}
var shield_on := false
var stealth_on := false
var emp_timer := 0.0
var hack_timer := 0.0
var weapon := "cannon"
var loadout := ["bullet", "cannon", "pulse", "beam", "missile", "torpedo"]
var thrust_input := 0.0
var turn_input := 0.0
var brake_input := false
var fire_input := false
var cooldowns: Dictionary = {}
var blink_cooldown := 0.0
var emp_cooldown := 0.0
var jump_charge := 0.0
var fire_control_spoof := false
var ai_enabled := true
var ai_target: CombatShip
var visual_radius := 800.0
var radar_radius := 1100.0
var ir_radius := 700.0
var has_optical := true
var has_radar := true
var has_ir := true
var has_fire_control := true


func _ready() -> void:
	mass = 5.0
	gravity_scale = 0.0
	linear_damp = 0.04
	angular_damp = 2.0
	contact_monitor = true
	max_contacts_reported = 4
	var shape := CircleShape2D.new()
	shape.radius = 20.0
	var collider := CollisionShape2D.new()
	collider.shape = shape
	add_child(collider)
	var material := PhysicsMaterial.new()
	material.bounce = 0.2
	physics_material_override = material
	queue_redraw()


func _physics_process(delta: float) -> void:
	if hp <= 0.0:
		return
	energy = minf(100.0, energy + (22.0 if energy < 25.0 else 14.0) * delta)
	for key in heat.keys():
		heat[key] = maxf(0.0, heat[key] - 18.0 * delta)
		if heat[key] < 40.0:
			overheated.erase(key)
	for key in disabled.keys():
		disabled[key] -= delta
		if disabled[key] <= 0.0:
			disabled.erase(key)
	emp_timer = maxf(0.0, emp_timer - delta)
	hack_timer = maxf(0.0, hack_timer - delta)
	if hack_timer <= 0.0:
		fire_control_spoof = false
	for key in cooldowns.keys():
		cooldowns[key] = maxf(0.0, cooldowns[key] - delta)
	blink_cooldown = maxf(0.0, blink_cooldown - delta)
	emp_cooldown = maxf(0.0, emp_cooldown - delta)
	if not player and ai_enabled:
		_ai(delta)
	if module_ready("engine") and thrust_input > 0.0 and spend("engine", 9.0 * delta, 22.0 * delta):
		apply_central_force(Vector2.UP.rotated(rotation) * 1200.0 * thrust_input)
	if brake_input:
		apply_central_force(-linear_velocity * 20.0)
	if module_ready("gyro"):
		apply_torque(turn_input * 2500.0)
	if linear_velocity.length() > 650.0:
		apply_central_force(-linear_velocity.normalized() * 850.0)
	if absf(angular_velocity) > 3.0:
		apply_torque(-signf(angular_velocity) * 1800.0)
	if shield_on:
		if not spend("shield", 7.0 * delta, 14.0 * delta):
			shield_on = false
	if stealth_on:
		if not spend("stealth", 5.0 * delta, 2.0 * delta):
			stealth_on = false
	if fire_input and cooldowns.get(weapon, 0.0) <= 0.0:
		game.fire_weapon(self)
	queue_redraw()


func module_ready(module: String) -> bool:
	return emp_timer <= 0.0 and not disabled.has(module) and not overheated.has(module)


func spend(module: String, cost: float, generated_heat: float) -> bool:
	if not module_ready(module) or energy < cost or (energy < 25.0 and module != "engine"):
		return false
	energy -= cost
	heat[module] = heat.get(module, 0.0) + generated_heat
	if heat[module] >= 100.0:
		overheated[module] = true
	return true


func take_damage(amount: float, kind: String) -> void:
	if hp <= 0.0:
		return
	stealth_on = false
	if shield_on and module_ready("shield") and energy > 0.0:
		var shield_factor := 0.7 if kind == "energy" else 1.25
		var absorbed := minf(amount, energy / shield_factor)
		energy -= absorbed * shield_factor
		amount -= absorbed
	if kind == "kinetic":
		amount *= 1.0 - hull_resistance
	hp -= amount
	game.play_sound("hit")
	if hp <= 0.0:
		destroyed.emit(self)
		queue_free()
	queue_redraw()


func is_hot() -> bool:
	if thrust_input > 0.0 or fire_input:
		return true
	for value in heat.values():
		if value > 10.0:
			return true
	return false


func _ai(_delta: float) -> void:
	if not is_instance_valid(ai_target):
		thrust_input = 0.0
		fire_input = false
		return
	var detected: bool = game.can_detect(self, ai_target)
	if not detected:
		thrust_input = 0.0
		fire_input = false
		return
	var offset: Vector2 = game.offset_to(global_position, ai_target.global_position)
	var desired: float = offset.angle() + PI / 2.0
	var difference := wrapf(desired - rotation, -PI, PI)
	turn_input = clampf(difference * 2.0, -1.0, 1.0)
	thrust_input = 1.0 if offset.length() > 260.0 else 0.0
	brake_input = offset.length() < 180.0
	fire_input = absf(difference) < 0.28 and offset.length() < 720.0
	shield_on = energy > 35.0 and offset.length() < 650.0


func _draw() -> void:
	var color := Color("62e7e2") if player else Color("ff735c")
	if stealth_on:
		color.a = 0.45
	if shield_on:
		draw_arc(Vector2.ZERO, 28.0, 0.0, TAU, 48, Color("78dfff"), 2.0)
	draw_colored_polygon(PackedVector2Array([Vector2(0, -27), Vector2(17, 17), Vector2(0, 9), Vector2(-17, 17)]), Color("142d3d"))
	draw_polyline(PackedVector2Array([Vector2(-17, 17), Vector2(0, -27), Vector2(17, 17)]), color, 2.0)
	draw_line(Vector2(-9, 11), Vector2(9, 11), color, 2.0)
	draw_circle(Vector2.ZERO, 4.0, color)
	if thrust_input > 0.0:
		draw_colored_polygon(PackedVector2Array([Vector2(-6, 17), Vector2(0, 30 + 12 * thrust_input), Vector2(6, 17)]), Color("ffb46b"))
