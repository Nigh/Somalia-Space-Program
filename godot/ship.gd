extends RigidBody2D
class_name CombatShip

signal destroyed(ship: CombatShip)
const PULSE_INTERVAL := 0.065

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
var torpedo_type := "rapid"
var loadout := ["bullet", "cannon", "pulse", "beam", "missile", "torpedo"]
var thrust_input := 0.0
var turn_input := 0.0
var brake_input := false
var fire_input := false
var cooldowns: Dictionary = {}
var pulse_remaining := 0
var pulse_timer := 0.0
var blink_cooldown := 0.0
var emp_cooldown := 0.0
var jump_charge := 0.0
var jump_charging := false
var network_shielded := false
var network_offline := false
var fire_control_spoof := false
var ai_enabled := true
var ai_target: CombatShip
var visual_radius := 1500.0
var radar_radius := 2400.0
var ir_radius := 1300.0
var has_optical := true
var has_radar := true
var has_ir := true
var has_fire_control := true
var sentry := false
var damage_multiplier := 1.0
var beam_range := 900.0
var fire_range := 720.0
var beam_active := false
var beam_direction := Vector2.UP
var beam_length := 0.0


func _ready() -> void:
	mass = 5.0
	gravity_scale = 0.0
	linear_damp = 0.04
	angular_damp = 2.0
	can_sleep = false
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
	beam_active = false
	if hp <= 0.0 or game.state != "playing":
		return
	energy = minf(100.0, energy + (200.0 if sentry else 22.0 if energy < 25.0 else 14.0) * delta)
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
		if player:
			# Responsive assisted steering; gyro damage still disables the assist.
			angular_velocity = move_toward(angular_velocity, turn_input * 4.5, 16.0 * delta)
		else:
			apply_torque(turn_input * 2500.0)
	if linear_velocity.length() > 650.0:
		apply_central_force(-linear_velocity.normalized() * 850.0)
	if not player and absf(angular_velocity) > 3.0:
		apply_torque(-signf(angular_velocity) * 1800.0)
	if shield_on:
		if not spend("shield", 7.0 * delta, 14.0 * delta):
			shield_on = false
	if stealth_on:
		if not spend("stealth", 5.0 * delta, 2.0 * delta):
			stealth_on = false
	if pulse_remaining > 0:
		if weapon != "pulse" or not module_ready("weapons"):
			pulse_remaining = 0
		else:
			pulse_timer -= delta
			while pulse_timer <= 0.0 and pulse_remaining > 0:
				game.fire_weapon(self, delta, true)
				pulse_remaining -= 1
				pulse_timer += PULSE_INTERVAL
	elif fire_input and cooldowns.get(weapon, 0.0) <= 0.0:
		game.fire_weapon(self, delta)
	queue_redraw()


func _integrate_forces(body: PhysicsDirectBodyState2D) -> void:
	if game.wrap_enabled and not player and is_instance_valid(game.player):
		var at: Vector2 = game.player.global_position
		body.transform.origin = at + game.offset_to(at, body.transform.origin)


func module_ready(module: String) -> bool:
	return not network_offline and emp_timer <= 0.0 and not disabled.has(module) and not overheated.has(module)


func spend(module: String, cost: float, generated_heat: float) -> bool:
	if not module_ready(module) or energy < cost or (energy < 25.0 and module != "engine"):
		return false
	energy -= cost
	heat[module] = heat.get(module, 0.0) + generated_heat
	if heat[module] >= 100.0:
		overheated[module] = true
	return true


func take_damage(amount: float, kind: String) -> void:
	if hp <= 0.0 or network_shielded:
		return
	if player and jump_charging:
		game.cancel_jump("hull impact")
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
	if network_offline or not is_instance_valid(ai_target):
		thrust_input = 0.0
		turn_input = 0.0
		fire_input = false
		return
	var detected: bool = game.can_detect(self, ai_target)
	if not detected:
		thrust_input = 0.0
		turn_input = 0.0
		fire_input = false
		return
	var offset: Vector2 = game.offset_to(global_position, ai_target.global_position)
	if sentry:
		thrust_input = 0.0
		turn_input = 0.0
		brake_input = true
		rotation = offset.angle() + PI / 2.0
		fire_input = offset.length() < fire_range
		return
	var desired: float = offset.angle() + PI / 2.0
	var difference := wrapf(desired - rotation, -PI, PI)
	turn_input = clampf(difference * 2.0, -1.0, 1.0)
	thrust_input = 1.0 if offset.length() > 260.0 else 0.0
	brake_input = offset.length() < 180.0
	fire_input = absf(difference) < 0.28 and offset.length() < 720.0
	shield_on = energy > 35.0 and offset.length() < 650.0


func _draw() -> void:
	for at in game.visible_positions(global_position):
		draw_set_transform(to_local(at))
		_draw_ship()


func _draw_ship() -> void:
	var color := Color("62e7e2") if player else Color("ff735c")
	if network_offline:
		color = Color("617c89")
	if stealth_on:
		color.a = 0.45
	if network_shielded:
		draw_arc(Vector2.ZERO, 31.0, 0.0, TAU, 48, Color("ac98e6"), 2.0, true)
	if shield_on:
		draw_arc(Vector2.ZERO, 28.0, 0.0, TAU, 48, Color("78dfff"), 2.0)
	if sentry:
		draw_circle(Vector2.ZERO, 19.0, Color("142d3d"))
		draw_arc(Vector2.ZERO, 19.0, 0.0, TAU, 32, color, 2.0, true)
		for angle in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
			var at := Vector2.from_angle(angle) * 19.0
			draw_line(at * 0.7, at * 1.25, color, 4.0, true)
		draw_line(Vector2.ZERO, Vector2(0, -26), color, 5.0, true)
		draw_circle(Vector2.ZERO, 5.0, color)
		return
	draw_colored_polygon(PackedVector2Array([Vector2(0, -27), Vector2(17, 17), Vector2(0, 9), Vector2(-17, 17)]), Color("142d3d"))
	draw_polyline(PackedVector2Array([Vector2(-17, 17), Vector2(0, -27), Vector2(17, 17)]), color, 2.0)
	draw_line(Vector2(-9, 11), Vector2(9, 11), color, 2.0)
	draw_circle(Vector2.ZERO, 4.0, color)
	if thrust_input > 0.0:
		draw_colored_polygon(PackedVector2Array([Vector2(-6, 17), Vector2(0, 30 + 12 * thrust_input), Vector2(6, 17)]), Color("ffb46b"))
