extends Node2D
class_name CombatProjectile

var game: Node2D
var owner_ship: CombatShip
var kind := "cannon"
var velocity := Vector2.ZERO
var damage := 12.0
var age := 0.0
var lifetime := 3.0
var target: CombatShip
var aim_point := Vector2.ZERO
var remaining_distance := 12000.0
var alive := true
var motor_started := false
var accelerating := false
var smoke_timer := 0.0
const EJECT_TIME := 0.35
const TORPEDO_SPEED := 1000.0


func _physics_process(delta: float) -> void:
	if not alive or is_queued_for_deletion():
		return
	if not is_instance_valid(owner_ship):
		queue_free()
		return
	age += delta
	if kind == "missile":
		if owner_ship.emp_timer > 0.0:
			queue_free()
			return
		if owner_ship.fire_control_spoof:
			aim_point = owner_ship.global_position
		elif is_instance_valid(target) and game.can_fire_control(owner_ship, target):
			aim_point = target.global_position
		var desired: Vector2 = (game.offset_to(global_position, aim_point)).normalized() * 310.0
		velocity = velocity.lerp(desired, minf(1.0, delta * 2.0))
	elif kind == "torpedo":
		if age >= EJECT_TIME:
			if not motor_started:
				motor_started = true
				velocity = (aim_point - global_position).normalized() * minf(velocity.length(), TORPEDO_SPEED)
				remaining_distance = global_position.distance_to(aim_point)
			velocity = velocity.move_toward(velocity.normalized() * TORPEDO_SPEED, 400.0 * delta)
			accelerating = velocity.length() < TORPEDO_SPEED - 0.1
			if accelerating:
				smoke_timer -= delta
				if smoke_timer <= 0.0:
					game.effects.append({"at": global_position - velocity.normalized() * 10.0, "time": 0.9, "smoke": true})
					smoke_timer += 0.04
	if age >= lifetime:
		queue_free()
		return
	var from := global_position
	var step := velocity * delta
	if kind == "torpedo" and motor_started:
		step = step.limit_length(remaining_distance)
		remaining_distance = maxf(0.0, remaining_distance - step.length())
	var hit_ship: CombatShip
	var first_t := 2.0
	# ponytail: scan ships directly; switch to a spatial query if arena populations grow.
	for ship in game.ships:
		if not is_instance_valid(ship) or ship.player == owner_ship.player:
			continue
		var relative: Vector2 = game.offset_to(from, ship.global_position)
		var t := clampf(relative.dot(step) / maxf(step.length_squared(), 0.001), 0.0, 1.0)
		if relative.distance_to(step * t) < 24.0 and t < first_t:
			hit_ship = ship
			first_t = t
	if is_instance_valid(hit_ship):
		global_position = from + step * first_t
		if kind == "torpedo":
			explode()
		else:
			hit_ship.take_damage(damage, "energy" if kind == "pulse" else "kinetic")
			queue_free()
		return
	global_position = from + step
	if kind == "torpedo":
		if remaining_distance <= 0.01:
			explode()
			return
	else:
		game.wrap_entity(self)
	if kind == "missile" or kind == "torpedo":
		rotation = velocity.angle() + PI / 2.0
	queue_redraw()


func explode() -> void:
	if not alive or is_queued_for_deletion():
		return
	alive = false
	if not is_instance_valid(owner_ship):
		queue_free()
		return
	for ship in game.ships:
		if is_instance_valid(ship) and ship.player != owner_ship.player:
			var distance: float = game.offset_to(global_position, ship.global_position).length()
			if distance < 100.0:
				ship.take_damage(damage * (1.0 - distance / 140.0), "blast")
	game.flash(global_position, Color("ffbf76"), 110.0)
	queue_free()


func _draw() -> void:
	for at in game.visible_positions(global_position):
		draw_set_transform(to_local(at))
		_draw_projectile()


func _draw_projectile() -> void:
	var color := Color("f5c27b")
	if kind == "pulse":
		color = Color("78e7ff")
	elif kind == "missile":
		color = Color("ff5b79")
	elif kind == "torpedo":
		color = Color("ffc46b")
	if kind == "missile" or kind == "torpedo":
		if kind == "torpedo" and motor_started:
			var length := 32.0 if accelerating else 13.0
			draw_colored_polygon(PackedVector2Array([Vector2(-4, 7), Vector2(0, length), Vector2(4, 7)]), Color("ff9d47"))
			draw_line(Vector2(0, 7), Vector2(0, length * 0.7), Color("fff3c4"), 3.0, true)
		draw_colored_polygon(PackedVector2Array([Vector2(0, -10), Vector2(5, 7), Vector2(-5, 7)]), color)
		draw_line(Vector2.ZERO, Vector2(0, 17), color.darkened(0.4), 2.0)
	elif kind == "pulse" or kind == "cannon":
		var direction := velocity.normalized()
		var length := 22.0 if kind == "cannon" else 12.0
		draw_line(-direction * length, direction * length, color, 4.0 if kind == "cannon" else 3.0, true)
	else:
		draw_circle(Vector2.ZERO, 5.0 if kind == "cannon" else 4.0, color)
