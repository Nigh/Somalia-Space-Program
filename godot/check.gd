extends SceneTree


func _initialize() -> void:
	create_timer(30.0).timeout.connect(func() -> void: quit(1))
	call_deferred("run_checks")


func run_checks() -> void:
	var game: Node2D = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	for stage in game.STAGES:
		game.start_stage(stage)
		await process_frame
		assert(is_instance_valid(game.player), "%s did not spawn a player" % stage)
		assert(game.ships.size() >= 2, "%s did not spawn a target" % stage)
		for i in 4:
			await physics_frame
	assert(await run_stealth_mission_checks(game), "stealth mission checks failed")
	game.start_stage("Weapons")
	await process_frame
	var hot: CombatShip = game.ships[1]
	var cold: CombatShip = game.ships[2]
	hot.stealth_on = true
	hot.thrust_input = 1.0
	cold.stealth_on = true
	assert(not game.can_fire_control(game.player, hot), "stealth must break radar lock")
	assert(game.can_detect(game.player, hot), "IR must reveal a hot stealth target")
	assert(not game.can_detect(game.player, cold), "cold stealth target must be hidden")
	game.player.has_ir = false
	assert(not game.can_detect(game.player, hot), "IR toggle must change detection")
	hot.take_damage(1.0, "kinetic")
	assert(not hot.stealth_on, "a hit must break stealth")
	game.start_stage("Power & Heat")
	await process_frame
	var before: float = game.player.energy
	assert(game.player.spend("cannon", 10.0, 110.0), "weapon should spend power")
	assert(game.player.energy < before and not game.player.module_ready("cannon"), "overheat must lock weapon")
	game.player.shield_on = true
	game.player.take_damage(20.0, "kinetic")
	assert(game.player.hp == 120.0, "shield must absorb a valid hit")
	game.start_stage("Weapons")
	await process_frame
	for weapon in game.player.loadout:
		game.player.weapon = weapon
		game.player.energy = 100.0
		game.player.heat.clear()
		game.player.overheated.clear()
		var shots_before: int = game.projectiles.size()
		game.fire_weapon(game.player)
		if weapon == "beam":
			assert(game.player.beam_active, "beam must fire")
		else:
			assert(game.projectiles.size() == shots_before + 1, "%s must launch" % weapon)
		var energy_after: float = game.player.energy
		if weapon != "beam":
			game.fire_weapon(game.player)
			assert(game.player.energy == energy_after, "cooldown must prevent duplicate fire")
		for i in 8:
			await physics_frame
	assert(game.projectiles.size() > 0, "projectile weapons must spawn")
	game.start_stage("HACK")
	await process_frame
	game.test_target_index = 0
	game._hack_target()
	assert(game.ships[1].disabled.has("weapons"), "HACK must disable a selected module")
	game.test_target_index = 5
	game._hack_target()
	assert(game.ships[1].fire_control_spoof, "HACK must spoof fire control")
	game.start_stage("Guidance & EMP")
	await process_frame
	game.player.weapon = "missile"
	game.fire_weapon(game.player)
	assert(game.projectiles.size() == 1, "missile must launch with radar lock")
	var missile: CombatProjectile = game.projectiles[0]
	var last_fix := missile.aim_point
	game.player.has_radar = false
	game.ships[1].global_position += Vector2(200, 0)
	await physics_frame
	assert(missile.aim_point == last_fix, "missile must keep last fix after radar loss")
	game._activate_emp()
	assert(missile.is_queued_for_deletion(), "EMP must stop a nearby missile")
	game.start_stage("Weapons")
	await process_frame
	var shooter: CombatShip = game.ships[1]
	shooter.global_position = Vector2(0, 250)
	shooter.rotation = 0.0
	shooter.weapon = "beam"
	var incoming := CombatProjectile.new()
	incoming.game = game
	incoming.owner_ship = game.player
	incoming.kind = "missile"
	incoming.position = Vector2(0, 100)
	incoming.velocity = Vector2.ZERO
	game.add_child(incoming)
	game.projectiles.append(incoming)
	game.fire_weapon(shooter)
	assert(incoming.is_queued_for_deletion(), "beam must intercept a guided projectile")
	# Exercise the real mouse-input path, not only direct fire_weapon calls.
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(700, 400)
	Input.parse_input_event(click)
	await process_frame
	game._physics_process(0.0)
	assert(game.player.fire_input, "mouse fire must reach the player")
	game.player._physics_process(0.0)
	assert(game.player.cooldowns.has(game.player.weapon), "mouse fire must launch a weapon")
	click.pressed = false
	Input.parse_input_event(click)
	# A missing AI target must not leave a half-created projectile behind.
	shooter.ai_target = null
	shooter.weapon = "torpedo"
	shooter.energy = 100.0
	game.fire_weapon(shooter)
	assert(game.projectiles.back().kind == "torpedo", "untargeted torpedo must launch")
	shooter.free()
	game._physics_process(0.0)
	for shot in game.projectiles:
		assert(is_instance_valid(shot.owner_ship), "interception must discard orphaned shots")
	game.start_stage("Mission")
	await process_frame
	for enemy in game.ships.slice(1):
		enemy.take_damage(500.0, "kinetic")
	game.player.global_position = game.extraction
	game._jump()
	assert(game.state == "playing" and game.player.jump_charging, "jump must start charging instead of finishing immediately")
	game.advance_jump(4.9)
	assert(game.state == "playing", "jump must wait for the full five seconds")
	game.advance_jump(0.1)
	assert(game.state == "won", "mission must finish at extraction after combat")
	game.start_stage("Warp Arena")
	await process_frame
	assert(game.offset_to(Vector2(1490, 0), Vector2(-1490, 0)).length() == 20.0, "wrap distance failed")
	for at in [Vector2(1510, 0), Vector2(-1510, 0), Vector2(0, 1060), Vector2(0, -1060), Vector2(7510, 5260)]:
		game.player.global_position = at
		game.camera.global_position = at
		game.wrap_entity(game.player)
		assert(game.player.global_position == at, "player must never teleport at a seam")
		var equivalent: Vector2 = at - game.ARENA * 2.0
		assert(game.visible_positions(equivalent).has(at), "opposite-edge objects must render beside player")
		game._process(1.0 / 60.0)
		assert(game.camera.global_position.is_equal_approx(at), "camera must not jump at seams")
	game.player.global_position = Vector2(1490, 0)
	game.camera.global_position = game.player.global_position
	var seam_target: CombatShip = game._spawn_ship(Vector2(-1490, 0), false)
	seam_target.ai_enabled = false
	var seam_shot := CombatProjectile.new()
	seam_shot.game = game
	seam_shot.owner_ship = game.player
	seam_shot.kind = "cannon"
	seam_shot.position = Vector2(1470, 0)
	seam_shot.velocity = Vector2(400, 0)
	game.add_child(seam_shot)
	seam_shot._physics_process(0.1)
	assert(seam_target.hp < 120.0, "projectile must hit across the wrap seam")
	# Run actual rigid-body integration across the corner at speed.
	for enemy in game.ships.slice(1):
		enemy.ai_enabled = false
		enemy.fire_input = false
	game.player.global_position = Vector2(1490, 1040)
	game.player.linear_velocity = Vector2(300, 300)
	for i in 12:
		await physics_frame
	assert(game.player.global_position.x > 1500 and game.player.global_position.y > 1050,
		"physics must move continuously through both edges")
	game._jump()
	assert(game.state == "playing" and game.player.emp_timer > 0.0, "generator must interrupt jump")
	game.generator.take_damage(500.0, "kinetic")
	await process_frame
	game.player.emp_timer = 0.0
	game._jump()
	game.advance_jump(5.0)
	assert(game.state == "won", "destroying generator must allow escape")
	assert(await run_tactical_checks(game), "tactical checks failed")
	assert(run_jump_input_checks(game), "jump input checks failed")
	print("Combat MVP checks passed")
	for audio in game.sound_players.values():
		audio.stop()
	game.queue_free()
	game = null
	# Let the audio thread release its finished playbacks before quitting.
	await create_timer(0.1).timeout
	quit()


func run_stealth_mission_checks(game: Node2D) -> bool:
	game.start_stage("Sensors & Stealth")
	assert(game.stealth_turrets.size() == 8 and is_instance_valid(game.command_ship), "stealth mission must start surrounded by linked turrets")
	var command: CombatShip = game.command_ship
	var turrets: Array[CombatShip] = game.stealth_turrets.duplicate()
	command.take_damage(999.0, "blast")
	turrets[0].take_damage(999.0, "blast")
	assert(command.hp == 220.0 and turrets[0].hp == 120.0, "network shields must enforce mission order")
	game._jump()
	assert(not game.player.jump_charging, "jump must not bypass the stealth mission")
	game.player.stealth_on = false
	game._update_stealth_objective()
	game.player.stealth_on = true
	game.player.position = game.stealth_center + Vector2(0, -1400)
	game._update_stealth_objective()
	assert(game.stealth_phase == "escape", "recloaking after detection must not count as a silent exit")
	game.player.position = game.stealth_center
	game.player.stealth_on = true
	game.player.linear_velocity = Vector2(0, -400)
	game._update_stealth_objective()
	# Run the real rigid-body coast through a gap with active turret AI.
	for tick in 330:
		await physics_frame
		if game.stealth_phase == "command":
			break
	assert(game.stealth_phase == "command" and game.player.hp == 120.0, "cold stealth coasting must escape the ring without damage")
	assert(game.projectiles.is_empty(), "turrets must not fire at an undetected stealth ship")
	command.take_damage(999.0, "blast")
	assert(game.stealth_phase == "cleanup" and game.state == "playing", "command destruction must start cleanup rather than complete the mission")
	for turret in turrets:
		assert(turret.network_offline and not turret.network_shielded, "command loss must disable every turret and remove its shield")
		turret.fire_input = true
		turret._physics_process(100.0)
		assert(not turret.module_ready("weapons"), "turret shutdown must be permanent")
	assert(game.projectiles.is_empty(), "offline turrets must not fire")
	for turret in turrets:
		turret.take_damage(999.0, "blast")
	assert(game.state == "won" and game.result_overlay.visible and not game.hud.visible, "clearing offline turrets must show the full-screen result")
	game.start_stage("Weapons")
	assert(not game.result_overlay.visible, "restarting must remove the result overlay")
	return true


func run_jump_input_checks(game: Node2D) -> bool:
	game.start_stage("Weapons")
	var events: Array[InputEvent] = []
	for keycode in [KEY_W, KEY_Q, KEY_SPACE, KEY_V]:
		var key := InputEventKey.new()
		key.keycode = keycode
		key.pressed = true
		events.append(key)
	for button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_WHEEL_UP]:
		var button := InputEventMouseButton.new()
		button.button_index = button_index
		button.pressed = true
		events.append(button)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(2, 0)
	events.append(motion)
	for event in events:
		game._jump()
		game.advance_jump(2.0)
		game._input(event)
		assert(not game.player.jump_charging and game.player.jump_charge == 0.0 and game.state == "playing", "any new operation must cancel and reset jump charge")
	game._jump()
	var release := InputEventKey.new()
	release.keycode = KEY_SPACE
	game._input(release)
	assert(game.player.jump_charging, "releasing the initiating space key must allow charging")
	game.player.thrust_input = 1.0
	game.advance_jump(0.1)
	assert(not game.player.jump_charging, "held thrust must cancel jump charge")
	game.player.thrust_input = 0.0
	game._jump()
	game.player.emp_timer = 1.0
	game.advance_jump(0.1)
	assert(not game.player.jump_charging, "EMP must interrupt jump electronics")
	game.player.emp_timer = 0.0
	game._jump()
	game.player.take_damage(1.0, "kinetic")
	assert(not game.player.jump_charging, "impact must interrupt jump charge")
	return true


func run_tactical_checks(game: Node2D) -> bool:
	game.start_stage("Weapons")
	var shooter: CombatShip = game.ships[1]
	shooter.ai_enabled = false
	shooter.position = Vector2.ZERO
	shooter.rotation = 0.0
	shooter.weapon = "beam"
	game.player.position = Vector2(0, -400)
	# Identical beam damage, heat and power at different physics tick rates.
	for ticks in [30, 60, 120]:
		game.player.hp = 120.0
		shooter.energy = 100.0
		shooter.heat.clear()
		for i in ticks:
			game.fire_weapon(shooter, 1.0 / ticks)
			assert(shooter.beam_active, "beam must be present on every firing tick")
		assert(is_equal_approx(game.player.hp, 94.0), "beam damage must be 26 HP/s for AI at every tick rate")
		assert(is_equal_approx(shooter.energy, 70.0), "beam power must be time-based")
		assert(is_equal_approx(float(shooter.heat.beam), 62.5), "beam heat must be time-based")
	shooter.fire_input = false
	shooter._physics_process(1.0 / 60.0)
	assert(not shooter.beam_active, "beam must stop immediately on release")
	shooter.emp_timer = 1.0
	game.fire_weapon(shooter)
	assert(not shooter.beam_active, "EMP must stop the beam")
	shooter.emp_timer = 0.0
	# Close and beyond-range torpedo aims must not consume power or cooldown.
	shooter.weapon = "torpedo"
	for distance in [0.0, 349.0, 12001.0]:
		game.player.position = Vector2(0, -distance)
		var energy: float = shooter.energy
		game.fire_weapon(shooter)
		assert(game.projectiles.is_empty(), "invalid torpedo aim must not launch")
		assert(shooter.energy == energy and not shooter.cooldowns.has("torpedo"), "rejected shot must be free")
	assert(game.torpedo_aim_valid(shooter, Vector2(0, -350)), "minimum boundary must be valid")
	game.player.position = Vector2(0, -12000)
	game.player.hp = 120.0
	shooter.energy = 100.0
	game.fire_weapon(shooter)
	assert(game.projectiles.size() == 1, "maximum-range torpedo must launch")
	var torpedo: CombatProjectile = game.projectiles[0]
	for i in 310:
		torpedo._physics_process(1.0 / 60.0)
	assert(not torpedo.is_queued_for_deletion(), "torpedo must live beyond the old five-second limit")
	for i in 1500:
		if torpedo.is_queued_for_deletion():
			break
		torpedo._physics_process(1.0 / 60.0)
	assert(game.player.hp < 120.0, "torpedo must hit at 12,000m")
	assert(torpedo.is_queued_for_deletion(), "torpedo must detonate on impact")
	# Zoom limits, stationary free camera, map inverse mapping, and drag events.
	game.start_stage("Torpedo Sniping")
	assert(game.ships.size() == 4 and not game.free_camera, "sniping range must start in follow view")
	assert(game.camera.position == game.player.position and is_equal_approx(game.camera.zoom.x, 0.85), "sniping view must start centered on the ship")
	assert(game.player.torpedo_type == "heavy", "sniping range must equip heavy torpedoes")
	game.set_free_camera(true)
	var overlay: Control = game.tactical_overlay
	var map_size: Vector2 = overlay.map_bounds().size
	game.player.position = Vector2(30000, 30000)
	assert(overlay.map_bounds().size == map_size, "tactical map scale must stay fixed")
	assert(overlay.map_area().has_point(overlay.map_position(game.player.position)), "player must remain on the tactical map")
	game.player.position = Vector2(0, 250)
	game.zoom_view(0.001)
	assert(is_equal_approx(game.camera.zoom.x, game.FREE_MIN_ZOOM), "free zoom limit")
	var camera_before: Vector2 = game.camera.position
	game._process(0.1)
	assert(game.camera.position == camera_before, "free camera must not follow player")
	var target: Vector2 = game.ships[1].position
	assert(overlay.map_world(overlay.map_position(target)).distance_to(target) < 0.01, "minimap coordinates must round-trip")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = overlay.map_position(target)
	overlay._map_input(click)
	assert(game.camera.position.distance_to(target) < 0.01, "minimap click must move the camera")
	assert(game.map_dragging, "map interactions must suppress weapon fire")
	click.pressed = false
	game._input(click)
	assert(not game.map_dragging, "map drag must end on release")
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	game._unhandled_input(click)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(32, -16)
	camera_before = game.camera.position
	game._input(motion)
	assert(game.camera.position.is_equal_approx(camera_before - motion.relative / game.camera.zoom), "drag must account for zoom")
	game.set_free_camera(false)
	assert(not game.camera_dragging and is_equal_approx(game.camera.zoom.x, game.FOLLOW_MIN_ZOOM), "return to follow must stop dragging and clamp zoom")
	assert(game.camera.position == game.player.position, "follow must recenter on the ship")
	game.zoom_view(1000)
	assert(is_equal_approx(game.camera.zoom.x, game.MAX_ZOOM), "maximum zoom limit")
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN, Vector2(1, 1)]:
		var edge: Vector2 = overlay.edge_position(overlay.size * 0.5 + direction * 10000)
		assert(Rect2(Vector2(27, 27), overlay.size - Vector2(54, 54)).has_point(edge), "bearing arrows must stay on screen")
	# Each battery type must engage and kill at close range using real shots.
	for index in 3:
		game.start_stage("Torpedo Sniping")
		var battery: CombatShip = game.ships[index + 1]
		assert(battery.weapon == ["bullet", "pulse", "missile"][index], "battery loadout")
		battery._ai(0.0)
		assert(not battery.fire_input, "battery must not fire outside defense range")
		game.player.position = battery.position + Vector2(0, 250)
		for tick in 180:
			battery._physics_process(1.0 / 60.0)
			for shot in game.projectiles:
				if not shot.is_queued_for_deletion():
					shot._physics_process(1.0 / 60.0)
			if game.player.hp <= 0.0:
				break
		assert(game.player.hp <= 0.0, "each battery must kill quickly with projectile fire")
	# Pan the free camera to aim at each battery without moving the ship.
	# This also works with the headless display's fixed hardware cursor.
	game.start_stage("Torpedo Sniping")
	game.set_free_camera(true)
	game.camera.force_update_scroll()
	for enemy in game.ships.slice(1):
		game.camera.position += enemy.position - game.weapon_aim(game.player)
		game.camera.force_update_scroll()
		assert(game.weapon_aim(game.player).distance_to(enemy.position) < 0.1, "free-view mouse must aim at the distant target")
		for shot_index in 3:
			if enemy.hp <= 0.0:
				break
			game.player.energy = 100.0
			game.player.cooldowns.clear()
			game.player.heat.clear()
			game.fire_weapon(game.player)
			var shot: CombatProjectile = game.projectiles.back()
			for tick in 1200:
				if shot.is_queued_for_deletion():
					break
				shot._physics_process(1.0 / 60.0)
		assert(enemy.hp <= 0.0, "three long-range torpedoes must destroy a battery")
	assert(game.state == "won", "torpedo sniping must be completable from outside defense range")
	game.start_stage("Weapons")
	game.player.turn_input = 1.0
	game.player._physics_process(0.1)
	assert(game.player.angular_velocity > 1.5, "player steering must accelerate promptly")
	game.player.turn_input = 0.0
	game.player._physics_process(0.1)
	assert(is_zero_approx(game.player.angular_velocity), "steering assist must brake after release")
	assert(await run_weapon_feedback_checks(game), "weapon feedback checks failed")
	return true


func run_weapon_feedback_checks(game: Node2D) -> bool:
	assert(is_equal_approx(game.WEAPONS.bullet.delay, 0.06), "bullet rate must double")
	assert(is_equal_approx(game.WEAPONS.cannon.delay, 0.96), "cannon rate must be one third")
	assert(is_equal_approx(game.WEAPONS.cannon.speed, 2040.0), "cannon speed must triple")
	game.start_stage("Weapons")
	await physics_frame
	game.fire_weapon(game.player)
	assert(game.shake_time > 0.0, "cannon must shake the view")
	await physics_frame
	await physics_frame
	assert(game.player.linear_velocity.length() > 60.0, "cannon must impart recoil")
	game._process(0.3)
	assert(game.camera.offset == Vector2.ZERO, "camera shake must settle without drift")
	game.start_stage("Weapons")
	var shooter: CombatShip = game.ships[1]
	shooter.weapon = "pulse"
	shooter.rotation = 0.0
	game.fire_weapon(shooter)
	assert(is_equal_approx(float(shooter.heat.pulse), game.WEAPONS.pulse.heat / 5.0), "pulse must add heat per shot")
	assert(shooter.cooldowns.pulse > shooter.PULSE_INTERVAL * 4.0, "pulse must reload between bursts")
	for index in 4:
		shooter.rotation += 0.2
		shooter._physics_process(shooter.PULSE_INTERVAL)
	assert(game.projectiles.size() == 5 and shooter.pulse_remaining == 0, "pulse must complete exactly five shots after trigger release")
	assert(is_equal_approx(float(shooter.heat.pulse), game.WEAPONS.pulse.heat - shooter.PULSE_INTERVAL * 4.0 * 18.0), "all five pulse shots must add heat")
	for index in range(1, 5):
		assert(game.projectiles[index].velocity.normalized().dot(game.projectiles[index - 1].velocity.normalized()) < 0.99, "burst must track changing aim")
	shooter.cooldowns.clear()
	game.fire_weapon(shooter)
	shooter.emp_timer = 1.0
	shooter._physics_process(0.1)
	assert(shooter.pulse_remaining == 0 and game.projectiles.size() == 6, "EMP must cancel pending burst shots")
	shooter.emp_timer = 0.0
	shooter.cooldowns.clear()
	game.fire_weapon(shooter)
	shooter.weapon = "bullet"
	shooter._physics_process(0.1)
	assert(shooter.pulse_remaining == 0 and game.projectiles.size() == 7, "weapon switch must cancel the burst")
	game.start_stage("Weapons")
	shooter = game.ships[1]
	shooter.position = Vector2.ZERO
	shooter.rotation = PI / 2.0
	shooter.linear_velocity = Vector2.ZERO
	shooter.weapon = "torpedo"
	game.player.position = Vector2(0, -6000)
	game.fire_weapon(shooter)
	var torpedo: CombatProjectile = game.projectiles[0]
	torpedo._physics_process(0.1)
	assert(absf(torpedo.velocity.x) > 150.0 and absf(torpedo.velocity.y) < 0.1, "cold launch must move across the target direction")
	assert(absf(torpedo.rotation) < 0.1, "torpedo nose must face its target during ejection")
	assert(not torpedo.motor_started and game.effects.is_empty(), "cold launch must have no exhaust")
	for tick in 20:
		torpedo._physics_process(1.0 / 60.0)
	assert(torpedo.motor_started and torpedo.accelerating and torpedo.velocity.y < 0, "torpedo must ignite and turn toward its aim")
	assert(not game.effects.is_empty(), "accelerating torpedo must emit smoke")
	for tick in 180:
		torpedo._physics_process(1.0 / 60.0)
	assert(not torpedo.accelerating, "torpedo must reach cruise speed")
	var smoke_count: int = game.effects.size()
	for tick in 15:
		torpedo._physics_process(1.0 / 60.0)
	assert(game.effects.size() == smoke_count, "cruising torpedo must stop producing smoke")
	shooter.cooldowns.clear()
	game.player.position = Vector2(-6000, 0)
	game.fire_weapon(shooter)
	var side_torpedo: CombatProjectile = game.projectiles.back()
	side_torpedo._physics_process(0.1)
	assert(absf(side_torpedo.velocity.y) > 150.0 and absf(side_torpedo.velocity.x) < 0.1, "leftward aim must eject vertically")
	assert(Vector2.UP.rotated(side_torpedo.rotation).dot((side_torpedo.aim_point - shooter.position).normalized()) > 0.99, "ejecting torpedo must face leftward aim")
	game.start_stage("Guidance & EMP")
	game.player.weapon = "missile"
	game.fire_weapon(game.player)
	var missile: CombatProjectile = game.projectiles[0]
	missile.position = Vector2(10000, 10000)
	missile.velocity = Vector2(310, 0)
	missile.age = missile.lifetime
	missile._physics_process(0.1)
	assert(not missile.is_queued_for_deletion() and missile.velocity == Vector2(310, 0), "empty missile must coast without guidance")
	missile._physics_process(missile.MISSILE_COAST_TIME + 0.1)
	assert(not missile.is_queued_for_deletion() and missile.age > missile.lifetime + missile.MISSILE_COAST_TIME, "missile must fade after coasting")
	missile._physics_process(missile.MISSILE_FADE_TIME)
	assert(missile.is_queued_for_deletion(), "missile must expire after its fade")
	var overlay: Control = game.tactical_overlay
	assert(overlay.weapon_buttons.size() == 6, "weapon selector must contain six buttons")
	overlay.weapon_buttons[2].pressed.emit()
	overlay._process(0.0)
	assert(game.player.weapon == "pulse" and overlay.weapon_buttons[2].button_pressed, "clicking a weapon icon must select and highlight it")
	assert(run_torpedo_type_checks(game), "torpedo type checks failed")
	return true


func run_torpedo_type_checks(game: Node2D) -> bool:
	game.start_stage("Weapons")
	var shooter: CombatShip = game.ships[1]
	shooter.ai_enabled = false
	shooter.position = Vector2.ZERO
	shooter.linear_velocity = Vector2.ZERO
	shooter.weapon = "torpedo"
	game.player.position = Vector2(0, -6000)
	game.fire_weapon(shooter)
	var rapid: CombatProjectile = game.projectiles.back()
	assert(rapid.torpedo_type == "rapid" and shooter.cooldowns.torpedo < 2.8, "ordinary stages must use rapid torpedoes with a shorter reload")
	shooter.torpedo_type = "heavy"
	shooter.energy = 100.0
	shooter.cooldowns.clear()
	game.fire_weapon(shooter)
	var heavy: CombatProjectile = game.projectiles.back()
	heavy._physics_process(0.4)
	assert(not heavy.motor_started and heavy.velocity.length() < rapid.velocity.length(), "heavy ejection must be slower with delayed ignition")
	heavy._physics_process(0.35)
	assert(heavy.motor_started and heavy.velocity.length() < 150.0, "heavy motor must accelerate slowly after ignition")
	assert(heavy.damage >= rapid.damage * 7.0 and heavy.blast_radius >= rapid.blast_radius * 8.0, "heavy warhead must have much greater damage and radius")
	game.player.position = Vector2(400, 0)
	game.player.hp = 1000.0
	rapid.position = Vector2.ZERO
	rapid.explode()
	assert(game.player.hp == 1000.0, "rapid blast must not hit outside its radius")
	heavy.position = Vector2.ZERO
	heavy.explode()
	assert(game.player.hp < 800.0, "heavy blast must damage ships well beyond the rapid blast radius")
	game.camera.position = Vector2.ZERO
	game.shake_time = 0.0
	game.torpedo_blast(Vector2.ZERO, heavy.blast_radius, true)
	var close_strength: float = game.shake_strength
	game.camera.position = Vector2(3000, 0)
	game.shake_time = 0.0
	game.torpedo_blast(Vector2.ZERO, heavy.blast_radius, true)
	assert(game.shake_strength > 0.0 and game.shake_strength < close_strength, "blast shake must fall off with camera distance")
	game.camera.position = Vector2(15000, 0)
	game.shake_time = 0.0
	game.torpedo_blast(Vector2.ZERO, heavy.blast_radius, true)
	assert(is_zero_approx(game.shake_strength), "distant blast must not shake the camera")
	game.state = "won"
	game._process(0.5)
	assert(not game.effects.is_empty() and game.effects.back().time < game.effects.back().duration, "final explosion must animate after mission completion")
	game._process(3.0)
	assert(game.effects.is_empty() and game.camera.offset == Vector2.ZERO, "blast effects and camera shake must settle")
	return true
