extends Node2D

const ARENA := Vector2(1500.0, 1050.0)
const STAGES := ["Mission", "Power & Heat", "Sensors & Stealth", "Weapons", "Guidance & EMP", "HACK", "Warp Arena", "Torpedo Sniping"]
const TORPEDO_MIN_RANGE := 350.0
const TORPEDO_MAX_RANGE := 12000.0
const FOLLOW_MIN_ZOOM := 0.45
const FREE_MIN_ZOOM := 0.08
const MAX_ZOOM := 1.6
const JUMP_DURATION := 5.0
const STEALTH_RING_RADIUS := 1000.0
const STEALTH_EXIT_RADIUS := 1350.0
const WEAPONS := {
	"bullet": {"cost": 1.0, "heat": 3.0, "delay": 0.06, "damage": 5.0, "speed": 1000.0},
	"cannon": {"cost": 5.0, "heat": 15.0, "delay": 0.96, "damage": 18.0, "speed": 2040.0},
	"pulse": {"cost": 8.0, "heat": 22.0, "delay": 1.0, "damage": 14.0, "speed": 850.0},
	# Continuous beam values are per second; physics ticks integrate them with delta.
	"beam": {"cost": 30.0, "heat": 62.5, "delay": 0.0, "damage": 40.0, "speed": 0.0},
	"missile": {"cost": 16.0, "heat": 26.0, "delay": 1.6, "damage": 36.0, "speed": 220.0},
	"torpedo": {"cost": 22.0, "heat": 34.0, "delay": 1.6, "damage": 70.0, "speed": 1000.0,
		"eject_speed": 160.0, "eject_time": 0.35, "acceleration": 400.0, "blast_radius": 100.0},
}
const HEAVY_TORPEDO := {"cost": 35.0, "heat": 55.0, "delay": 3.8, "damage": 560.0, "speed": 1000.0,
	"eject_speed": 65.0, "eject_time": 0.7, "acceleration": 150.0, "blast_radius": 800.0}

var ships: Array[CombatShip] = []
var projectiles: Array[CombatProjectile] = []
var player: CombatShip
var generator: CombatShip
var command_ship: CombatShip
var stealth_turrets: Array[CombatShip] = []
var stealth_phase := "escape"
var stealth_inside := true
var stealth_detected := false
var stealth_center := Vector2(0, 250)
var stage := ""
var state := "menu"
var wrap_enabled := false
var extraction := Vector2(0, -780)
var camera: Camera2D
var shake_time := 0.0
var shake_strength := 0.0
var shake_duration := 0.22
var beam_mesh := ArrayMesh.new()
var blast_texture := GradientTexture2D.new()
var free_camera := false
var camera_dragging := false
var map_dragging := false
var tactical_overlay: Control
var view_button: Button
var menu: Control
var hud: Control
var test_panel: Control
var message_label: Label
var instructions: Label
var objective_label: Label
var result_overlay: Control
var result_title: Label
var result_hint: Label
var result_tween: Tween
var message_time := 0.0
var effects: Array[Dictionary] = []
var test_target_index := 0
var test_modules := ["weapons", "engine", "gyro", "radar", "shield", "fire_control"]
var sound_players: Dictionary = {}
var sound_gates: Dictionary = {}


func _ready() -> void:
	_build_beam_mesh()
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.25, 0.55, 0.8, 1.0])
	gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.65), Color(1, 1, 1, 0.18), Color(1, 1, 1, 0)])
	blast_texture.gradient = gradient
	blast_texture.fill = GradientTexture2D.FILL_RADIAL
	blast_texture.fill_from = Vector2(0.5, 0.5)
	blast_texture.fill_to = Vector2(1.0, 0.5)
	blast_texture.width = 256
	blast_texture.height = 256
	camera = Camera2D.new()
	camera.zoom = Vector2(0.85, 0.85)
	camera.enabled = true
	add_child(camera)
	for name in ["shot", "hit", "emp"]:
		var audio := AudioStreamPlayer.new()
		audio.stream = load("res://audio/%s.wav" % name)
		audio.volume_db = -12.0
		add_child(audio)
		sound_players[name] = audio
	_build_ui()
	show_menu()


func show_menu() -> void:
	_clear_world()
	state = "menu"
	stage = ""
	menu.visible = true
	hud.visible = false
	test_panel.visible = false
	camera.position = Vector2.ZERO
	queue_redraw()


func start_stage(selected: String) -> void:
	_clear_world()
	stage = selected
	state = "playing"
	wrap_enabled = selected == "Warp Arena"
	menu.visible = false
	hud.visible = true
	test_panel.visible = false
	player = _spawn_ship(Vector2(0, 250), true)
	player.rotation = 0.0
	free_camera = false
	camera_dragging = false
	camera.zoom = Vector2.ONE * 0.85
	camera.position = player.position
	match selected:
		"Mission":
			var first := _spawn_ship(Vector2(-260, -350))
			first.hp = 65.0
			var second := _spawn_ship(Vector2(300, -500))
			second.hp = 65.0
			second.weapon = "pulse"
			set_message("INTERCEPT: neutralize both raiders, then jump at the extraction marker.")
		"Power & Heat":
			_spawn_ship(Vector2(0, -420), false)
			set_message("Hold fire, thrust and shield. Watch power and per-module heat.")
		"Sensors & Stealth":
			player.stealth_on = true
			player.radar_radius = 4500.0
			for index in 8:
				var turret := _spawn_ship(stealth_center + Vector2.from_angle(TAU * float(index) / 8.0 + PI / 8.0) * STEALTH_RING_RADIUS)
				turret.sentry = true
				turret.freeze = true
				turret.network_shielded = true
				turret.weapon = "pulse" if index % 2 == 0 else "bullet"
				turret.fire_range = 1450.0
				turret.ir_radius = 400.0
				turret.damage_multiplier = 3.0
				stealth_turrets.append(turret)
			command_ship = _spawn_ship(Vector2(0, -3200))
			command_ship.hp = 220.0
			command_ship.weapon = "pulse"
			command_ship.network_shielded = true
			set_message("SILENT RUN: stealth is on. Accelerate, then coast cold through a gap. Destroy the command ship outside the ring.", 12.0)
		"Weapons":
			for x in [-340, 0, 340]:
				var target := _spawn_ship(Vector2(x, -420), false)
				target.ai_enabled = false
				target.hp = 220.0
				target.shield_on = x == 0
			set_message("Compare cannon, pulse, beam, missile and torpedo against shielded targets.")
		"Guidance & EMP":
			var target := _spawn_ship(Vector2(0, -450), false)
			target.weapon = "missile"
			set_message("Missiles need fire-control radar; EMP interrupts electronics and guidance.")
		"HACK":
			var target := _spawn_ship(Vector2(0, -30), false)
			target.weapon = "missile"
			set_message("Approach within 350 units, then press R to disable the selected module.")
		"Warp Arena":
			generator = _spawn_ship(Vector2(0, -460), false)
			generator.hp = 250.0
			generator.energy = 100.0
			_spawn_ship(Vector2(380, -280))
			set_message("The warp field folds space. Destroy the generator to escape by jump.")
		"Torpedo Sniping":
			player.weapon = "torpedo"
			player.torpedo_type = "heavy"
			player.radar_radius = 10000.0
			for index in 3:
				var at: Vector2 = [Vector2(-1400, -5000), Vector2(0, -5600), Vector2(1500, -4900)][index]
				var target := _spawn_ship(at)
				target.sentry = true
				target.weapon = ["bullet", "pulse", "missile"][index]
				target.fire_range = 3000.0
				target.radar_radius = 3000.0
				target.damage_multiplier = 12.0
			set_message("HEAVY TORPEDO: press V for free view. Destroy 3 batteries outside their 3,000m defense zones.", 12.0)
	_update_visibility()
	_update_hud()
	queue_redraw()


func _spawn_ship(at: Vector2, is_player := false) -> CombatShip:
	var ship := CombatShip.new()
	ship.game = self
	ship.player = is_player
	ship.position = at
	ship.destroyed.connect(_on_ship_destroyed)
	add_child(ship)
	ships.append(ship)
	if not is_player and is_instance_valid(player):
		ship.ai_target = player
	return ship


func _clear_world() -> void:
	if is_instance_valid(result_tween):
		result_tween.kill()
	result_overlay.hide()
	stealth_turrets.clear()
	command_ship = null
	stealth_phase = "escape"
	stealth_inside = true
	stealth_detected = false
	for ship in ships:
		if is_instance_valid(ship):
			ship.queue_free()
	for projectile in projectiles:
		if is_instance_valid(projectile):
			projectile.queue_free()
	ships.clear()
	projectiles.clear()
	effects.clear()
	shake_time = 0.0
	shake_strength = 0.0
	camera.offset = Vector2.ZERO
	player = null
	generator = null
	wrap_enabled = false
	free_camera = false
	camera_dragging = false
	map_dragging = false


func _physics_process(delta: float) -> void:
	if state != "playing" or not is_instance_valid(player):
		return
	player.thrust_input = 1.0 if Input.is_key_pressed(KEY_W) else 0.0
	player.turn_input = float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
	player.brake_input = Input.is_key_pressed(KEY_S)
	player.fire_input = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not camera_dragging and not map_dragging \
		and get_viewport().gui_get_hovered_control() == null
	advance_jump(delta)
	if state != "playing":
		return
	for i in range(ships.size() - 1, -1, -1):
		if not is_instance_valid(ships[i]) or ships[i].hp <= 0.0:
			ships.remove_at(i)
	for i in range(projectiles.size() - 1, -1, -1):
		if not is_instance_valid(projectiles[i]) or projectiles[i].is_queued_for_deletion():
			projectiles.remove_at(i)
		elif not is_instance_valid(projectiles[i].owner_ship):
			projectiles[i].queue_free()
			projectiles.remove_at(i)
	# ponytail: pair scan is enough for the small test arenas; use spatial queries if projectile counts grow.
	for i in projectiles.size():
		var a := projectiles[i]
		if not is_instance_valid(a) or a.is_queued_for_deletion() or a.kind != "missile" and a.kind != "torpedo":
			continue
		for j in projectiles.size():
			var b := projectiles[j]
			if i == j or not is_instance_valid(b) or b.is_queued_for_deletion() or b.owner_ship.player == a.owner_ship.player:
				continue
			if (b.kind == "bullet" or b.kind == "cannon") and offset_to(a.global_position, b.global_position).length() < 16.0:
				flash(a.global_position, Color("ffba71"), 35.0)
				a.queue_free()
				b.queue_free()
				break
	if stage == "Mission" and _enemies_left() == 0 and player.global_position.distance_to(extraction) < 150.0:
		if not player.jump_charging:
			set_message("Extraction reached. Press SPACE to charge a 5s jump. Any input interrupts it.")
	if stage == "Sensors & Stealth":
		_update_stealth_objective()
	_update_visibility()
	queue_redraw()


func _process(delta: float) -> void:
	shake_time = maxf(0.0, shake_time - delta)
	camera.offset = Vector2(sin(shake_time * 110.0), cos(shake_time * 83.0)) * shake_strength * (shake_time / shake_duration) / camera.zoom
	for effect in effects:
		effect.time -= delta
	effects = effects.filter(func(effect: Dictionary) -> bool: return effect.time > 0.0)
	if state != "playing":
		queue_redraw()
		return
	if is_instance_valid(player):
		if not free_camera:
			camera.global_position = camera.global_position.lerp(player.global_position, minf(1.0, delta * 5.0))
		_update_hud()
	message_time = maxf(0.0, message_time - delta)
	if message_time <= 0.0:
		message_label.text = ""
	for name in sound_gates.keys():
		sound_gates[name] = maxf(0.0, sound_gates[name] - delta)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if state == "playing" and is_instance_valid(player) and player.jump_charging:
		if event is InputEventKey and event.pressed and not event.echo \
			or event is InputEventMouseButton and event.pressed \
			or event is InputEventMouseMotion and not event.relative.is_zero_approx():
			cancel_jump("player input")
			if event is InputEventKey and event.keycode == KEY_SPACE:
				return
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		map_dragging = false
	if event is InputEventMouseButton and not event.pressed and event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
		camera_dragging = false
	if event is InputEventMouseMotion and camera_dragging and free_camera:
		camera.position -= event.relative / camera.zoom
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		show_menu()
		return
	if state != "playing" or not is_instance_valid(player):
		return
	if event.keycode >= KEY_1 and event.keycode <= KEY_6:
		player.weapon = player.loadout[event.keycode - KEY_1]
	elif event.keycode == KEY_Q:
		player.shield_on = not player.shield_on
	elif event.keycode == KEY_F:
		player.stealth_on = not player.stealth_on
	elif event.keycode == KEY_E:
		_activate_emp()
	elif event.keycode == KEY_R:
		_hack_target()
	elif event.keycode == KEY_SHIFT:
		_blink()
	elif event.keycode == KEY_SPACE:
		_jump()
	elif event.keycode == KEY_O:
		player.has_optical = not player.has_optical
	elif event.keycode == KEY_P:
		player.has_radar = not player.has_radar
	elif event.keycode == KEY_I:
		player.has_ir = not player.has_ir
	elif event.keycode == KEY_TAB:
		test_target_index = (test_target_index + 1) % test_modules.size()
	elif event.keycode == KEY_BACKSPACE and stage != "Mission":
		start_stage(stage)
	elif event.keycode == KEY_V:
		set_free_camera(not free_camera)
	elif event.keycode == KEY_F1:
		test_panel.visible = not test_panel.visible


func _unhandled_input(event: InputEvent) -> void:
	if state != "playing" or not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		zoom_view(1.15)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		zoom_view(1.0 / 1.15)
	elif free_camera and event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
		camera_dragging = true
	else:
		return
	get_viewport().set_input_as_handled()


func set_free_camera(enabled: bool) -> void:
	free_camera = enabled
	camera_dragging = false
	map_dragging = false
	camera.zoom = Vector2.ONE * clampf(camera.zoom.x, FREE_MIN_ZOOM if enabled else FOLLOW_MIN_ZOOM, MAX_ZOOM)
	if not enabled and is_instance_valid(player):
		camera.position = player.position
	camera.force_update_scroll()


func zoom_view(factor: float) -> void:
	var anchor := get_global_mouse_position()
	camera.zoom = Vector2.ONE * clampf(camera.zoom.x * factor, FREE_MIN_ZOOM if free_camera else FOLLOW_MIN_ZOOM, MAX_ZOOM)
	camera.force_update_scroll()
	if free_camera:
		camera.position += anchor - get_global_mouse_position()
		camera.force_update_scroll()


func weapon_aim(ship: CombatShip) -> Vector2:
	if ship.player:
		return get_global_mouse_position()
	if is_instance_valid(ship.ai_target):
		return ship.global_position + offset_to(ship.global_position, ship.ai_target.global_position)
	return ship.global_position + Vector2.UP.rotated(ship.rotation) * 760.0


func torpedo_aim_valid(ship: CombatShip, at: Vector2) -> bool:
	var distance := ship.global_position.distance_to(at)
	return distance >= TORPEDO_MIN_RANGE and distance <= TORPEDO_MAX_RANGE


func fire_weapon(ship: CombatShip, delta := 1.0 / 60.0, pulse_tick := false) -> void:
	if state != "playing" or not is_instance_valid(ship) or ship.hp <= 0.0:
		return
	if ship.player and ship.jump_charging:
		cancel_jump("weapon fire")
	var name := ship.weapon
	if pulse_tick and name != "pulse":
		return
	if not pulse_tick and ship.cooldowns.get(name, 0.0) > 0.0:
		return
	var data: Dictionary = WEAPONS[name]
	if name == "torpedo" and ship.torpedo_type == "heavy":
		data = HEAVY_TORPEDO
	var aim_point := weapon_aim(ship)
	if name == "torpedo" and not torpedo_aim_valid(ship, aim_point):
		return
	var locked_target: CombatShip
	if name == "missile":
		locked_target = _nearest_target(ship, ship.radar_radius, true)
		if not is_instance_valid(locked_target):
			if ship.player:
				set_message("MISSILE: no fire-control lock.")
			return
	var rate := delta if name == "beam" else 1.0
	if rate <= 0.0 or not ship.module_ready("weapons"):
		return
	if not pulse_tick and not ship.spend(name, data.cost * rate, data.heat * rate / (5.0 if name == "pulse" else 1.0)):
		return
	if pulse_tick:
		ship.heat[name] = ship.heat.get(name, 0.0) + data.heat / 5.0
		if ship.heat[name] >= 100.0:
			ship.overheated[name] = true
	var direction := Vector2.UP.rotated(ship.rotation)
	if ship.player or ship.sentry:
		var aim := aim_point - ship.global_position
		if aim.length() > 0.0:
			direction = aim.normalized()
	if not pulse_tick:
		ship.cooldowns[name] = data.delay
		if name == "pulse":
			ship.pulse_remaining = 4
			ship.pulse_timer = ship.PULSE_INTERVAL
	if name == "cannon" and ship.player:
		ship.apply_central_impulse(-direction * ship.mass * 70.0)
		shake(9.0, 0.22)
		flash(ship.global_position + direction * 30.0, Color("ffcf91"), 45.0)
	play_sound("shot")
	if name == "beam":
		var start := ship.global_position + direction * 28.0
		var distance := ship.beam_range
		var hit_ship: CombatShip
		var hit_projectile: CombatProjectile
		for target in ships:
			if not is_instance_valid(target) or target.player == ship.player:
				continue
			var relative := offset_to(start, target.global_position)
			var forward := relative.dot(direction)
			if forward > 0.0 and forward < distance and (relative - direction * forward).length() < 22.0:
				distance = forward
				hit_ship = target
				hit_projectile = null
		for shot in projectiles:
			if not is_instance_valid(shot) or shot.is_queued_for_deletion() or not is_instance_valid(shot.owner_ship) or shot.owner_ship.player == ship.player \
				or shot.kind != "missile" and shot.kind != "torpedo":
				continue
			var relative := offset_to(start, shot.global_position)
			var forward := relative.dot(direction)
			if forward > 0.0 and forward < distance and (relative - direction * forward).length() < 14.0:
				distance = forward
				hit_projectile = shot
				hit_ship = null
		if is_instance_valid(hit_ship):
			hit_ship.take_damage(data.damage * delta * ship.damage_multiplier * (0.65 if not ship.player else 1.0), "energy")
		elif is_instance_valid(hit_projectile):
			flash(hit_projectile.global_position, Color("8ee7ff"), 30.0)
			hit_projectile.queue_free()
		ship.beam_active = true
		ship.beam_direction = direction
		ship.beam_length = distance
		return
	var projectile := CombatProjectile.new()
	projectile.game = self
	projectile.owner_ship = ship
	projectile.kind = name
	projectile.damage = data.damage * ship.damage_multiplier * (0.65 if not ship.player else 1.0)
	projectile.position = ship.global_position + direction * 29.0
	projectile.velocity = direction * data.speed + ship.linear_velocity * 0.5
	projectile.lifetime = 4.5 if name == "missile" else 30.0 if name == "torpedo" else 2.0
	if name == "cannon":
		projectile.lifetime /= 3.0
	if ship.sentry:
		projectile.lifetime = ship.fire_range / (310.0 if name == "missile" else data.speed) + 1.0
	projectile.aim_point = aim_point
	if name == "missile":
		projectile.target = locked_target
		projectile.aim_point = projectile.target.global_position
	elif name == "torpedo":
		projectile.torpedo_type = ship.torpedo_type
		projectile.eject_time = data.eject_time
		projectile.cruise_speed = data.speed
		projectile.acceleration = data.acceleration
		projectile.blast_radius = data.blast_radius
		var launch_direction := (aim_point - ship.global_position).normalized()
		var eject_direction := launch_direction.orthogonal()
		projectile.position = ship.global_position + eject_direction * 29.0
		projectile.velocity = eject_direction * data.eject_speed + ship.linear_velocity
		projectile.rotation = launch_direction.angle() + PI / 2.0
		projectile.remaining_distance = projectile.position.distance_to(aim_point)
	add_child(projectile)
	projectiles.append(projectile)


func _nearest_target(from: CombatShip, radius: float, needs_lock := false) -> CombatShip:
	var best: CombatShip
	var distance := radius
	for ship in ships:
		if not is_instance_valid(ship) or ship == from or ship.player == from.player:
			continue
		if needs_lock and not can_fire_control(from, ship):
			continue
		var current := offset_to(from.global_position, ship.global_position).length()
		if current < distance:
			distance = current
			best = ship
	return best


func can_detect(observer: CombatShip, target: CombatShip) -> bool:
	if not is_instance_valid(observer) or not is_instance_valid(target):
		return false
	var distance := offset_to(observer.global_position, target.global_position).length()
	return (observer.has_optical and observer.module_ready("optical") and not target.stealth_on and distance < observer.visual_radius) \
		or (observer.has_radar and observer.module_ready("radar") and not target.stealth_on and distance < observer.radar_radius) \
		or (observer.has_ir and observer.module_ready("ir") and target.is_hot() and distance < observer.ir_radius)


func can_fire_control(observer: CombatShip, target: CombatShip) -> bool:
	return observer.has_radar and observer.has_fire_control and observer.module_ready("radar") \
		and observer.module_ready("fire_control") and not target.stealth_on \
		and offset_to(observer.global_position, target.global_position).length() < observer.radar_radius


func offset_to(from: Vector2, to: Vector2) -> Vector2:
	var offset := to - from
	if wrap_enabled:
		offset.x = wrapf(offset.x + ARENA.x, 0.0, ARENA.x * 2.0) - ARENA.x
		offset.y = wrapf(offset.y + ARENA.y, 0.0, ARENA.y * 2.0) - ARENA.y
	return offset


func wrap_entity(entity: Node2D) -> void:
	if not wrap_enabled or not is_instance_valid(player) or entity == player:
		return
	entity.global_position = player.global_position + offset_to(player.global_position, entity.global_position)


func visible_positions(at: Vector2, margin := 40.0) -> Array[Vector2]:
	if not wrap_enabled:
		return [at]
	var half_view := get_viewport_rect().size / camera.zoom * 0.5 + Vector2.ONE * margin
	var view := Rect2(camera.global_position - half_view, half_view * 2.0)
	var period := ARENA * 2.0
	var positions: Array[Vector2] = []
	for x in range(int(ceil((view.position.x - at.x) / period.x)), int(floor((view.end.x - at.x) / period.x)) + 1):
		for y in range(int(ceil((view.position.y - at.y) / period.y)), int(floor((view.end.y - at.y) / period.y)) + 1):
			positions.append(at + Vector2(x, y) * period)
	return positions


func _update_visibility() -> void:
	if not is_instance_valid(player):
		return
	for ship in ships:
		if is_instance_valid(ship) and ship != player:
			ship.visible = player.has_optical and player.module_ready("optical") and not ship.stealth_on \
				and offset_to(player.global_position, ship.global_position).length() < player.visual_radius


func _on_ship_destroyed(ship: CombatShip) -> void:
	flash(ship.global_position, Color("ff8d64"), 100.0)
	play_sound("hit")
	if ship == player:
		_finish(false)
	elif ship == command_ship:
		command_ship = null
		stealth_phase = "cleanup"
		for turret in stealth_turrets:
			if not is_instance_valid(turret) or turret.hp <= 0.0:
				continue
			turret.network_shielded = false
			turret.network_offline = true
			turret.ai_enabled = false
			turret.fire_input = false
			turret.thrust_input = 0.0
			turret.turn_input = 0.0
			turret.pulse_remaining = 0
			turret.beam_active = false
			flash(turret.global_position, Color("ac98e6"), 60.0)
		for shot in projectiles:
			if is_instance_valid(shot) and shot.owner_ship in stealth_turrets:
				shot.queue_free()
		set_message("COMMAND LINK LOST: all turrets permanently offline. Destroy the remaining platforms.", 10.0)
		if _enemies_left() == 0:
			_finish(true)
	elif ship == generator:
		generator = null
		set_message("Warp generator down. Press SPACE to escape.")
	elif stage == "Mission" and _enemies_left() == 0:
		set_message("Raiders neutralized. Fly to the extraction marker.")
	elif stage in ["Torpedo Sniping", "Sensors & Stealth"] and _enemies_left() == 0:
		_finish(true)


func _update_stealth_objective() -> void:
	if stealth_phase != "escape":
		return
	var distance := player.global_position.distance_to(stealth_center)
	var inside := distance <= STEALTH_EXIT_RADIUS
	var silent := player.stealth_on
	for turret in stealth_turrets:
		if is_instance_valid(turret) and can_detect(turret, player):
			silent = false
	if not silent:
		if not stealth_detected:
			set_message("DETECTED: retreat to the inner safe zone, restore stealth and cool down before retrying.", 10.0)
		stealth_detected = true
	elif distance < STEALTH_RING_RADIUS * 0.6:
		stealth_detected = false
	if not inside and stealth_inside:
		if silent and not stealth_detected:
			stealth_phase = "command"
			command_ship.network_shielded = false
			set_message("SILENT EXIT COMPLETE: command ship exposed. Destroy it to disable the turret network.", 10.0)
		else:
			set_message("EXIT DETECTED: return to the inner safe zone, then leave under stealth without detection.", 10.0)
	stealth_inside = inside


func _enemies_left() -> int:
	var total := 0
	for ship in ships:
		if is_instance_valid(ship) and ship != player and ship.hp > 0.0:
			total += 1
	return total


func _finish(won: bool) -> void:
	if state != "playing":
		return
	state = "won" if won else "lost"
	hud.hide()
	test_panel.hide()
	result_overlay.show()
	result_overlay.modulate.a = 0.0
	result_title.text = "MISSION COMPLETE" if won else "SHIP LOST"
	result_title.add_theme_color_override("font_color", Color("77e4e8") if won else Color("ff735c"))
	result_title.scale = Vector2.ONE * 1.08
	result_title.pivot_offset = result_title.size * 0.5
	result_hint.text = "%s\n\nESC  /  RETURN TO MAIN MENU" % stage.to_upper()
	result_tween = create_tween().set_parallel(true)
	result_tween.tween_property(result_overlay, "modulate:a", 1.0, 0.6)
	result_tween.tween_property(result_title, "scale", Vector2.ONE, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for ship in ships:
		if is_instance_valid(ship):
			ship.freeze = true
			ship.fire_input = false
			ship.beam_active = false
			ship.pulse_remaining = 0
			ship.jump_charging = false
			ship.jump_charge = 0.0
	for projectile in projectiles:
		if is_instance_valid(projectile):
			projectile.queue_free()


func _activate_emp() -> void:
	if player.emp_cooldown > 0.0 or not player.spend("emp", 28.0, 30.0):
		return
	player.emp_cooldown = 8.0
	player.emp_timer = 1.2
	for ship in ships:
		if is_instance_valid(ship) and ship != player and offset_to(player.global_position, ship.global_position).length() < 350.0:
			ship.emp_timer = 3.0
	for projectile in projectiles:
		if is_instance_valid(projectile) and offset_to(player.global_position, projectile.global_position).length() < 350.0:
			if projectile.kind == "missile":
				projectile.queue_free()
			elif projectile.kind == "torpedo" and projectile.age < projectile.eject_time:
				projectile.age = projectile.eject_time
	flash(player.global_position, Color("8fd8ff"), 350.0)
	play_sound("emp")
	set_message("EMP pulse: nearby electronics offline; your systems recover first.")


func _hack_target() -> void:
	var target := _nearest_target(player, 350.0)
	if not is_instance_valid(target) or not player.spend("hack", 22.0, 20.0):
		set_message("HACK requires a target within 350 units and available power.")
		return
	var module: String = test_modules[test_target_index]
	if module == "fire_control":
		target.fire_control_spoof = true
		target.hack_timer = 5.0
	else:
		target.disabled[module] = 5.0
	flash(target.global_position, Color("bb8aff"), 60.0)
	set_message("HACK: %s compromised for 5 seconds." % module.to_upper())


func _blink() -> void:
	if player.blink_cooldown > 0.0 or not player.spend("blink", 30.0, 20.0):
		return
	var displacement := get_global_mouse_position() - player.global_position
	if displacement.length() > 0.0:
		flash(player.global_position, Color("78dfff"), 45.0)
		player.global_position += displacement.limit_length(320.0)
		wrap_entity(player)
		flash(player.global_position, Color("78dfff"), 45.0)
		player.blink_cooldown = 5.0


func _can_jump() -> bool:
	if not player.module_ready("jump"):
		set_message("JUMP OFFLINE: electronics recovering from EMP.")
		return false
	if stage == "Warp Arena" and is_instance_valid(generator):
		player.emp_timer = 1.5
		set_message("Generator field interrupts the jump and disables electronics.")
		return false
	if stage == "Mission" and (_enemies_left() > 0 or player.global_position.distance_to(extraction) > 150.0):
		set_message("Clear the raiders and reach the extraction marker first.")
		return false
	if stage == "Torpedo Sniping" and _enemies_left() > 0:
		set_message("Destroy all three batteries before jumping.")
		return false
	if stage == "Sensors & Stealth" and _enemies_left() > 0:
		set_message("Complete the silent exit, destroy the command ship, then clear its turrets.")
		return false
	return true


func _jump() -> void:
	if state != "playing" or not is_instance_valid(player):
		return
	if player.jump_charging:
		cancel_jump("player input")
		return
	if not _can_jump():
		return
	player.jump_charging = true
	player.jump_charge = 0.0
	set_message("JUMP CHARGING: keep all controls idle for 5 seconds.")


func cancel_jump(reason: String) -> void:
	if not is_instance_valid(player) or not player.jump_charging:
		return
	player.jump_charging = false
	player.jump_charge = 0.0
	set_message("JUMP INTERRUPTED: %s." % reason)


func advance_jump(delta: float) -> void:
	if not player.jump_charging:
		return
	if player.thrust_input > 0.0 or not is_zero_approx(player.turn_input) or player.brake_input \
		or player.fire_input or player.pulse_remaining > 0 or camera_dragging or map_dragging:
		cancel_jump("controls must remain idle")
		return
	if not _can_jump():
		cancel_jump("jump conditions changed")
		return
	player.jump_charge = minf(JUMP_DURATION, player.jump_charge + delta)
	if player.jump_charge >= JUMP_DURATION:
		flash(player.global_position, Color("78dfff"), 160.0)
		_finish(true)


func flash(at: Vector2, color: Color, radius: float) -> void:
	effects.append({"at": at, "color": color, "radius": radius, "time": 0.32})


func shake(strength: float, duration: float) -> void:
	if strength < shake_strength * shake_time / shake_duration:
		return
	shake_strength = strength
	shake_duration = duration
	shake_time = duration


func torpedo_blast(at: Vector2, radius: float, heavy: bool) -> void:
	var duration := 2.0 if heavy else 0.55
	effects.append({"at": at, "radius": radius, "time": duration, "duration": duration, "blast": true, "heavy": heavy})
	var distance := offset_to(camera.global_position, at).length()
	var falloff := pow(clampf(1.0 - distance / (radius * (12.0 if heavy else 15.0)), 0.0, 1.0), 1.4)
	shake((32.0 if heavy else 8.0) * falloff, 0.9 if heavy else 0.25)


func _build_beam_mesh() -> void:
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for section in 41:
		var x := float(section) / 40.0
		var taper := 1.0 - smoothstep(0.68, 1.0, x)
		for side in [-1, 0, 1]:
			vertices.append(Vector2(x, side * taper))
			colors.append(Color(1.0, 1.0, 1.0, taper if side == 0 else 0.0))
		if section < 40:
			for side in 2:
				var index := section * 3 + side
				indices.append_array(PackedInt32Array([index, index + 3, index + 1, index + 1, index + 3, index + 4]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	beam_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func play_sound(name: String) -> void:
	if sound_gates.get(name, 0.0) > 0.0:
		return
	sound_players[name].play()
	sound_gates[name] = 0.15


func set_message(value: String, duration := 5.0) -> void:
	message_label.text = value
	message_time = duration


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("081622e8")
	style.border_color = Color("348798")
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
	return style


func _add_button(parent: Node, title: String, action: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(0, 44)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_color_override("font_color", Color("e5f8fa"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	var style := _panel_style()
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	button.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = Color("164350")
	hover.border_color = Color("77e4e8")
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("focus", hover)
	button.pressed.connect(action)
	parent.add_child(button)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	menu = PanelContainer.new()
	menu.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	menu.position = Vector2(58, -245)
	menu.custom_minimum_size = Vector2(390, 0)
	menu.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(menu)
	var menu_box := VBoxContainer.new()
	menu_box.add_theme_constant_override("separation", 8)
	menu.add_child(menu_box)
	var title := Label.new()
	title.text = "SOMALIA / SPACE PROGRAM"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("77e4e8"))
	menu_box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "COMBAT SYSTEMS  /  MISSION SELECT\nChoose a mission or combat test range."
	subtitle.add_theme_color_override("font_color", Color("b8d0da"))
	menu_box.add_child(subtitle)
	menu_box.add_spacer(false)
	for selected in STAGES:
		_add_button(menu_box, selected, func() -> void: start_stage(selected))

	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)
	view_button = Button.new()
	view_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	view_button.position = Vector2(-630, 14)
	view_button.size = Vector2(300, 44)
	view_button.focus_mode = Control.FOCUS_ALL
	view_button.pressed.connect(func() -> void: set_free_camera(not free_camera))
	hud.add_child(view_button)
	var tests_button := Button.new()
	tests_button.text = "Test controls [F1]"
	tests_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tests_button.position = Vector2(-316, 14)
	tests_button.size = Vector2(300, 44)
	tests_button.focus_mode = Control.FOCUS_ALL
	tests_button.pressed.connect(func() -> void: test_panel.visible = not test_panel.visible)
	hud.add_child(tests_button)
	var bottom := PanelContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bottom.position = Vector2(16, -112)
	bottom.custom_minimum_size = Vector2(974, 96)
	bottom.add_theme_stylebox_override("panel", _panel_style())
	hud.add_child(bottom)
	instructions = Label.new()
	instructions.text = "FLIGHT   W/S thrust/brake  ·  A/D turn  ·  LMB fire  ·  1–6 weapon\nSYSTEMS   Q shield  ·  F stealth  ·  O/P/I sensors  ·  E EMP  ·  R HACK  ·  TAB module\nNAVIGATION   SHIFT blink  ·  SPACE jump (5s idle)  ·  V view  ·  WHEEL zoom  ·  RMB drag  ·  ESC menu"
	instructions.add_theme_font_size_override("font_size", 14)
	instructions.add_theme_color_override("font_color", Color("d4e5eb"))
	bottom.add_child(instructions)
	message_label = Label.new()
	message_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	message_label.position = Vector2(16, -150)
	message_label.custom_minimum_size = Vector2(974, 38)
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.add_theme_font_size_override("font_size", 16)
	message_label.add_theme_color_override("font_color", Color("ffd58b"))
	hud.add_child(message_label)
	objective_label = Label.new()
	objective_label.position = Vector2(16, 145)
	objective_label.add_theme_font_size_override("font_size", 15)
	objective_label.add_theme_color_override("font_color", Color("bce9ed"))
	hud.add_child(objective_label)

	test_panel = PanelContainer.new()
	test_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	test_panel.position = Vector2(-266, 66)
	test_panel.custom_minimum_size = Vector2(250, 0)
	root.add_child(test_panel)
	var test_box := VBoxContainer.new()
	test_panel.add_child(test_box)
	var test_title := Label.new()
	test_title.text = "TEST CONTROLS"
	test_title.add_theme_color_override("font_color", Color("78e7e5"))
	test_box.add_child(test_title)
	_add_button(test_box, "Reset scene", func() -> void: start_stage(stage))
	_add_button(test_box, "Restore power + cool", func() -> void:
		player.energy = 100.0
		player.heat.clear()
		player.overheated.clear())
	_add_button(test_box, "Toggle target stealth", func() -> void: _test_toggle_stealth())
	_add_button(test_box, "Toggle target shield", func() -> void: _test_toggle_shield())
	_add_button(test_box, "Toggle target heat", func() -> void: _test_toggle_heat())
	_add_button(test_box, "Toggle target radar", func() -> void: _test_toggle_radar())
	_add_button(test_box, "Target EMP", func() -> void: _test_target_emp())
	_add_button(test_box, "Spawn target", func() -> void: _spawn_ship(player.global_position + Vector2(0, -350)))
	_add_button(test_box, "Toggle wrap", func() -> void: wrap_enabled = not wrap_enabled)
	_add_button(test_box, "Next HACK module", func() -> void:
		test_target_index = (test_target_index + 1) % test_modules.size())
	tactical_overlay = preload("res://tactical_overlay.gd").new()
	tactical_overlay.game = self
	hud.add_child(tactical_overlay)
	result_overlay = Control.new()
	result_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(result_overlay)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.015, 0.025, 0.04, 0.78)
	result_overlay.add_child(shade)
	var result_center := CenterContainer.new()
	result_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_overlay.add_child(result_center)
	var result_box := VBoxContainer.new()
	result_box.add_theme_constant_override("separation", 20)
	result_center.add_child(result_box)
	result_title = Label.new()
	result_title.custom_minimum_size = Vector2(0, 100)
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_title.add_theme_font_size_override("font_size", 60)
	result_hint = Label.new()
	result_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_hint.add_theme_font_size_override("font_size", 16)
	result_hint.add_theme_color_override("font_color", Color("a7bfca"))
	result_box.add_child(result_hint)


func _test_toggle_stealth() -> void:
	var target := _nearest_target(player, 1500.0)
	if is_instance_valid(target):
		target.stealth_on = not target.stealth_on


func _test_toggle_shield() -> void:
	var target := _nearest_target(player, 1500.0)
	if is_instance_valid(target):
		target.shield_on = not target.shield_on


func _test_toggle_heat() -> void:
	var target := _nearest_target(player, 1500.0)
	if is_instance_valid(target):
		target.ai_enabled = false
		target.thrust_input = 0.0 if target.thrust_input > 0.0 else 1.0


func _test_toggle_radar() -> void:
	var target := _nearest_target(player, 1500.0)
	if is_instance_valid(target):
		target.has_radar = not target.has_radar


func _test_target_emp() -> void:
	var target := _nearest_target(player, 1500.0)
	if is_instance_valid(target):
		target.emp_timer = 3.0


func _update_hud() -> void:
	view_button.text = "%s VIEW  ·  %d%%  [V]" % ["FREE" if free_camera else "FOLLOW", roundi(camera.zoom.x * 100.0)]
	objective_label.visible = stage == "Sensors & Stealth"
	match stealth_phase:
		"escape":
			objective_label.text = "01 / SILENT EXIT   ·   Stealth + cold coasting beyond the perimeter"
		"command":
			objective_label.text = "02 / COMMAND SHIP   ·   Destroy the exposed controller outside the ring"
		"cleanup":
			objective_label.text = "03 / CLEANUP   ·   Destroy offline turrets: %d remaining" % _enemies_left()


func _draw() -> void:
	var grid_color := Color("184452")
	var half_view := get_viewport_rect().size / camera.zoom * 0.5 + Vector2(100, 100)
	var top_left := camera.global_position - half_view
	var bottom_right := camera.global_position + half_view
	# AA coverage and constant screen-space width prevent subpixel flicker.
	for spacing in [100, 500]:
		grid_color.a = 0.34 * smoothstep(8.0, 45.0, spacing * camera.zoom.x)
		for x in range(int(floor(top_left.x / spacing)) * spacing, int(bottom_right.x) + spacing, spacing):
			if spacing == 500 or posmod(x, 500) != 0:
				draw_line(Vector2(x, top_left.y), Vector2(x, bottom_right.y), grid_color, 1.0 / camera.zoom.x, true)
		for y in range(int(floor(top_left.y / spacing)) * spacing, int(bottom_right.y) + spacing, spacing):
			if spacing == 500 or posmod(y, 500) != 0:
				draw_line(Vector2(top_left.x, y), Vector2(bottom_right.x, y), grid_color, 1.0 / camera.zoom.x, true)
	for i in 85:
		var point := Vector2(sin(float(i) * 42.17) * 2100.0, cos(float(i) * 17.31) * 1800.0)
		for at in visible_positions(point):
			draw_circle(at, 1.2, Color("496675"))
	for i in 18:
		var center := Vector2(sin(float(i + 2) * 13.7) * 1700.0, cos(float(i + 4) * 7.3) * 1150.0)
		var radius := 28.0 + float(i % 5) * 10.0
		for at in visible_positions(center, radius):
			var points := PackedVector2Array()
			for corner in 7:
				var angle := TAU * float(corner) / 7.0
				points.append(at + Vector2.from_angle(angle) * radius * (0.8 + 0.18 * sin(float(i + corner) * 3.1)))
			draw_colored_polygon(points, Color("0b2029"))
			points.append(points[0])
			draw_polyline(points, Color("31515d"), 1.0)
	if state != "playing" or not is_instance_valid(player):
		_draw_effects()
		return
	if stage == "Mission" and _enemies_left() == 0:
		draw_arc(extraction, 75.0, 0.0, TAU, 64, Color("71e8d9"), 3.0)
		draw_line(extraction + Vector2(-15, 0), extraction + Vector2(15, 0), Color("71e8d9"), 2.0)
	if stage == "Sensors & Stealth" and stealth_phase == "escape":
		draw_arc(stealth_center, STEALTH_EXIT_RADIUS, 0.0, TAU, 128, Color("62e7e244"), 2.0, true)
	if player.has_radar and player.module_ready("radar"):
		draw_arc(player.global_position, player.radar_radius, 0.0, TAU, 96, Color("225969"), 1.0)
	if player.has_ir and player.module_ready("ir"):
		for ship in ships:
			if is_instance_valid(ship) and ship != player and ship.is_hot() \
				and offset_to(player.global_position, ship.global_position).length() < player.ir_radius:
				for at in visible_positions(ship.global_position):
					draw_arc(at, 25.0, 0.0, TAU, 24, Color("ffae69"), 2.0)
	for ship in ships:
		if not is_instance_valid(ship) or not ship.beam_active:
			continue
		var start := ship.global_position + ship.beam_direction * 28.0
		var length := ship.beam_direction * ship.beam_length
		for at in visible_positions(start, length.length()):
			draw_mesh(beam_mesh, null, Transform2D(ship.beam_direction.angle(), Vector2(ship.beam_length, 6.0 / camera.zoom.x), 0.0, at), Color("3899bb88"))
			draw_mesh(beam_mesh, null, Transform2D(ship.beam_direction.angle(), Vector2(ship.beam_length, 1.5 / camera.zoom.x), 0.0, at), Color("d5f7ff"))
	_draw_effects()


func _draw_effects() -> void:
	for effect in effects:
		if effect.has("smoke"):
			for at in visible_positions(effect.at):
				draw_circle(at, 4.0 + (0.9 - effect.time) * 18.0, Color(0.55, 0.62, 0.68, effect.time * 0.35))
			continue
		if effect.has("blast"):
			var progress: float = 1.0 - effect.time / effect.duration
			var fade := 1.0 - progress
			var wave: float = effect.radius * pow(progress, 0.55) * 1.3
			var fire: float = effect.radius * 0.42 * sin(PI * minf(progress / 0.75, 1.0))
			for at in visible_positions(effect.at, effect.radius * 1.3):
				draw_arc(at, wave, 0.0, TAU, 128, Color(1.0, 0.65, 0.3, fade * fade), 8.0 if effect.heavy else 2.0, true)
				if effect.heavy:
					draw_arc(at, wave * 0.82, 0.0, TAU, 128, Color(1.0, 0.87, 0.6, fade * 0.35), 3.0, true)
				for lobe in 12:
					var direction := Vector2.from_angle(float(lobe) * TAU / 12.0 + sin(float(lobe) * 7.3) * 0.24)
					var plume: float = effect.radius * progress * (0.32 + 0.07 * sin(float(lobe) * 4.7))
					_draw_blast_cloud(at + direction * plume, effect.radius * (0.09 + progress * 0.18), Color(0.18, 0.16, 0.15, sin(PI * progress) * 0.65))
					var debris: float = wave * (0.55 + 0.3 * sin(float(lobe) * 3.7))
					draw_line(at + direction * debris, at + direction * (debris + effect.radius * 0.08 * fade), Color(1.0, 0.5, 0.2, fade * fade), 4.0 if effect.heavy else 1.0, true)
					if fire > 0.0:
						_draw_blast_cloud(at + direction * fire * 0.45, fire * (0.65 + 0.1 * sin(float(lobe) * 2.3)), Color(1.0, 0.3 + fade * 0.25, 0.08, fade * 0.6))
				if fire > 0.0:
					_draw_blast_cloud(at, fire, Color(1.0, 0.72, 0.25, fade * 0.9))
					_draw_blast_cloud(at, fire * 0.6, Color(1.0, 0.95, 0.8, fade))
			continue
		for at in visible_positions(effect.at, effect.radius):
			draw_arc(at, effect.radius * (1.0 - effect.time / 0.32), 0.0, TAU, 48,
				Color(effect.color, effect.time / 0.32), 2.0, true)


func _draw_blast_cloud(at: Vector2, radius: float, color: Color) -> void:
	draw_texture_rect(blast_texture, Rect2(at - Vector2.ONE * radius, Vector2.ONE * radius * 2.0), false, color)
