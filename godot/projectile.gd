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
var fuse := 0.0
var alive := true


func _physics_process(delta: float) -> void:
	if not alive:
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
		if age < 0.7:
			var desired: Vector2 = game.offset_to(global_position, aim_point).normalized() * 100.0
			velocity = velocity.lerp(desired, minf(1.0, delta * 4.0))
		else:
			velocity = velocity.move_toward(velocity.normalized() * 450.0, 120.0 * delta)
		if age >= fuse:
			explode()
			return
	if age >= lifetime:
		queue_free()
		return
	var from := global_position
	var step := velocity * delta
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
		if kind == "torpedo":
			explode()
		else:
			hit_ship.take_damage(damage, "energy" if kind == "pulse" else "kinetic")
			queue_free()
		return
	global_position = from + step
	game.wrap_entity(self)
	if kind == "missile" or kind == "torpedo":
		rotation = velocity.angle() + PI / 2.0
	queue_redraw()


func explode() -> void:
	if not alive:
		return
	alive = false
	for ship in game.ships:
		if is_instance_valid(ship) and ship.player != owner_ship.player:
			var distance: float = game.offset_to(global_position, ship.global_position).length()
			if distance < 100.0:
				ship.take_damage(damage * (1.0 - distance / 140.0), "blast")
	game.flash(global_position, Color("ffbf76"), 110.0)
	queue_free()


func _draw() -> void:
	var color := Color("f5c27b")
	if kind == "pulse":
		color = Color("78e7ff")
	elif kind == "missile":
		color = Color("ff5b79")
	elif kind == "torpedo":
		color = Color("ffc46b")
	if kind == "missile" or kind == "torpedo":
		draw_colored_polygon(PackedVector2Array([Vector2(0, -10), Vector2(5, 7), Vector2(-5, 7)]), color)
		draw_line(Vector2.ZERO, Vector2(0, 17), color.darkened(0.4), 2.0)
	else:
		draw_circle(Vector2.ZERO, 5.0 if kind == "cannon" else 4.0, color)
