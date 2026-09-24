extends Node
## Combat checks, driven through the ControlIntent seam and the systems' interfaces:
## the Garand's clip (8 shots -> ping -> reload -> fires again, manual reload of a part clip),
## hip vs aimed spread, shooting a bandit (damage, falloff, headshot x2.5, kill), a camp that
## notices the courier and shoots back, being knocked out and waking by a road, camps
## streaming in and out by distance, a cleared camp surviving save/load, a road ambush and
## the old tin cans.
## Run: godot --headless --path . -- --test=combat_tests

var game: Game
var sc: Controls.Scripted
var phase := 0
var pt := 0.0
var fails := 0
var mark: Dictionary = {}
var range_at := Vector3.ZERO
var pings := 0
var target: Enemy
var min_health := 100.0


func _ready() -> void:
	game = Game.current
	Events.clip_pinged.connect(func(): pings += 1)


func _check(cond: bool, label: String) -> void:
	print(("  PASS " if cond else "  FAIL ") + label)
	if not cond: fails += 1


func _next() -> void:
	phase += 1
	pt = 0.0


func _aim_at(p: Vector3) -> void:
	var d: Vector3 = p - game.cam.global_position
	game.cam.set_look(atan2(-d.x, -d.z), -atan2(d.y, Vector2(d.x, d.z).length()))


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, game.world.terrain.height_at(x, z) + 0.08, z)


## A one-man test camp `dist` metres ahead of the courier, facing him.
func _test_camp(id: StringName, dist: float, size: int, side: float = 0.0) -> Array:
	var pl: Player = game.player
	var f: Vector3 = pl.flat_forward()
	var r := f.cross(Vector3.UP).normalized()
	var p: Vector3 = pl.global_position + f * dist + r * side
	p = _ground(p.x, p.z)
	game.encounters.add_camp(id, &"bandit", p, -f, size, &"squad")
	game.encounters.spawn_camp(id)
	return game.encounters.enemies_of(id)


func _physics_process(delta: float) -> void:
	pt += delta
	var gun: GunSystem = game.gun
	var pl: Player = game.player
	var rider: Rider = game.rider
	var dir: EncounterDirector = game.encounters
	var vit: PlayerVitals = game.vitals
	if sc == null:
		sc = game.use_scripted_controls()
		dir.ambush_enabled = false
	match phase:
		0:  # on foot on the salt flats (open, flat, no camp in reach)
			if pt > 0.5:
				_check(gun.has_gun and gun.ammo == GunSystem.CLIP, "the courier starts with a loaded Garand (8 in the clip)")
				_check(pl.model.slung_gun != null and pl.model.long_gun != null, "the Garand rides on the courier's model (held + slung)")
				rider.request_dismount()
				var s: Vector3 = game.world.database.location_pos(&"salinas")
				range_at = _ground(s.x + 30.0, s.z - 25.0)
				pl.place(range_at, Vector3(0, 0, -1))
				game.cam.snap_to_target()
				gun.reserve_clips = 4
				vit.health.invulnerable = 999.0
				_next()
		1:  # hip vs aimed spread
			if pt > 1.0 and not mark.has("hip"):
				mark.hip = gun.current_spread()
				sc.intent.aim = true
			if pt > 2.0:
				var ads := gun.current_spread()
				print("[test] spread hip %.2f deg, aimed %.2f deg" % [mark.hip, ads])
				_check(ads < mark.hip * 0.35, "aimed spread is much tighter than hip fire")
				_check(game.cam.is_aiming() and game.cam.fov < 50.0, "aiming zooms the over-the-shoulder view")
				_check(pl.model.gun_raise > 0.9 and pl.model.long_gun.visible and not pl.model.slung_gun.visible, "aiming shoulders the rifle (slung one hidden)")
				var dot: float = gun.barrel_direction().dot(game.cam.view_ray().direction)
				print("[test] barrel·view = %.3f" % dot)
				_check(dot > 0.9, "the rifle's barrel points along the view ray")
				_next()
		2:  # fire the whole clip
			_aim_at(range_at + Vector3(0, -1.5, -40))
			if pt > 0.2 and int(pt / 0.25) > int((pt - delta) / 0.25) and gun.shots_fired - int(mark.get("shots0", gun.shots_fired)) < 8:
				if not mark.has("shots0"): mark.shots0 = gun.shots_fired
				sc.press("fire")
			if mark.has("shots0") and gun.shots_fired - int(mark.shots0) >= 8 and not mark.has("empty_at"):
				mark.empty_at = pt
				_check(gun.ammo == 0, "eight shots empty the clip")
				_check(pings == 1 and gun.clips_pinged == 1 and gun.sounds.has_played(&"ping"), "the 8th shot ejects the clip with its ping")
				_check(gun.last_shot.surface != &"", "shots hit the ground and throw up an impact (%s)" % gun.last_shot.surface)
				_check(gun.fx.tracers >= 8, "every shot draws a tracer")
			if mark.has("empty_at") and pt > float(mark.empty_at) + 0.7 and not mark.has("reload_seen"):
				mark.reload_seen = true
				_check(gun.reloading, "an empty Garand reloads on its own when there are clips")
			if mark.has("empty_at") and pt > float(mark.empty_at) + GunSystem.RELOAD_TIME + 0.8:
				_check(gun.ammo == 8 and gun.reserve_clips == 3 and not gun.reloading, "reload presses a fresh clip in (8 rounds, one clip fewer)")
				_check(gun.sounds.has_played(&"clip_in") and gun.sounds.has_played(&"bolt"), "reload plays the clip going in and the bolt slamming home")
				var before := gun.ammo
				sc.press("fire")
				mark.before = before
				_next()
		3:
			if pt > 0.2 and not mark.has("partial"):
				mark.partial = true
				_check(gun.ammo == int(mark.before) - 1, "the reloaded rifle fires again")
				pings = 0
				sc.press("reload")
			if pt > 0.4 and not mark.has("partial_checked"):
				mark.partial_checked = true
				_check(pings == 1 and gun.reloading and gun.loose_rounds == 7, "a manual reload pings the part clip out and keeps its 7 rounds")
			if pt > GunSystem.RELOAD_TIME + 0.8:
				_check(gun.ammo == 8 and gun.reserve_clips == 2, "manual reload finishes with a full clip")
				gun.add_ammo(0, 1)
				_check(gun.loose_rounds == 0 and gun.reserve_clips == 3, "loose rounds are packed back into clips")
				sc.intent.aim = false
				_next()
		4:  # a bandit on the range: body shots, falloff, headshot, kill
			if pt > 0.3 and target == null:
				var men := _test_camp(&"camp.test.range", 22.0, 1)
				_check(men.size() == 1 and men[0] is Enemy, "a test camp spawns its bandit")
				target = men[0]
				_check(game.entities.get_entity(target.enemy_id) == target and String(target.enemy_id).begins_with("enemy.camp_test_range."), "the bandit is registered by stable id (%s)" % target.enemy_id)
			if pt > 1.5 and target and not mark.has("frozen"):
				mark.frozen = true
				target.set_physics_process(false)      # hold still for the marksmanship checks
				sc.intent.aim = true
			if mark.has("frozen") and pt > 2.6 and pt < 3.4:
				_aim_at(target.model.torso.global_position + Vector3(0, 0.3, 0))
			if pt > 3.4 and not mark.has("body"):
				mark.body = true
				mark.hp0 = target.health.current
				mark.markers = game.hud.combat.marker_count
				sc.press("fire")
			if pt > 3.6 and not mark.has("body_checked"):
				mark.body_checked = true
				var taken: float = float(mark.hp0) - target.health.current
				print("[test] body shot: %s (%s) took %.1f" % [gun.last_shot.collider, gun.debug_last, taken])
				var expect := gun.damage_at(gun.muzzle_position().distance_to(target.global_position))
				_check(taken > 0.0 and absf(taken - expect) < 0.5, "a body shot does the Garand's damage at that range (%.0f)" % expect)
				_check(game.hud.combat.marker_count > int(mark.markers), "the HUD shows a hit marker")
				_check(gun.damage_at(250.0) < gun.damage_at(40.0) and gun.damage_at(40.0) == GunSystem.DAMAGE, "damage falls off with range")
				target.health.current = target.health.max_health
			if mark.has("body_checked") and pt > 4.0 and pt < 4.8:
				_aim_at(target.model.head.global_position + Vector3(0, 0.05, 0))
			if pt > 4.8 and not mark.has("head"):
				mark.head = true
				mark.kills0 = dir.stats.kills
				sc.press("fire")
			if pt > 5.2:
				print("[test] head shot: %s headshot=%s dmg=%.1f dead=%s" % [gun.last_shot.collider, gun.last_shot.headshot, gun.last_shot.damage, target.is_dead()])
				_check(gun.last_shot.headshot and absf(float(gun.last_shot.damage) / gun.damage_at(gun.muzzle_position().distance_to(target.global_position)) - GunSystem.HEADSHOT) < 0.05, "a headshot does x2.5")
				_check(target.is_dead() and dir.stats.kills == int(mark.kills0) + 1 and dir.stats.headshots >= 1, "the headshot kills; the kill is counted")
				_check(game.entities.get_entity(target.enemy_id) != null, "the body stays until the camp despawns")
				_check(dir.is_cleared(&"camp.test.range"), "a camp with nobody left standing is cleared")
				sc.intent.aim = false
				dir.remove_camp(&"camp.test.range")
				target = null
				mark.clear()
				_next()
		5:  # a camp that notices him and shoots back
			if pt > 0.5 and target == null:
				vit.health.invulnerable = 0.0
				vit.health.reset()
				min_health = 100.0
				var men := _test_camp(&"camp.test.fight", 28.0, 3)
				target = men[0]
				mark.shots0 = 0
			if target:
				min_health = minf(min_health, vit.health.current)
				var alerted := 0
				var shots := 0
				for e in dir.enemies_of(&"camp.test.fight"):
					if e.state == Enemy.State.COMBAT: alerted += 1
					shots += e.shots
				if (min_health < 100.0 and alerted >= 2) or pt > 30.0:
					print("[test] after %.1f s: %d in combat, %d shots, health low %.0f, rays %d" % [pt, alerted, shots, min_health, Enemy.rays_total])
					_check(alerted >= 2, "bandits spot the courier and the camp is alerted together")
					_check(shots > 0, "they shoot back")
					_check(min_health < 100.0, "the courier gets hurt (health drops)")
					var covered := 0
					for e in dir.enemies_of(&"camp.test.fight"):
						if e.sub in [Enemy.Sub.MOVE_COVER, Enemy.Sub.HIDE, Enemy.Sub.PEEK]: covered += 1
					print("[test] %d of them working from cover" % covered)
					_next()
		6:  # knocked out -> fade -> woken by a road with a small fine
			if pt > 0.1 and not mark.has("down"):
				mark.down = true
				game.gm.coins = 100
				vit.health.invulnerable = 0.0
				vit.hit(1000.0, pl.global_position + Vector3(0, 1, -5), &"test")
				_check(vit.is_down() and rider.hold, "lethal damage knocks the courier down; controls held")
			if pt > 0.7 and not mark.has("faded"):
				mark.faded = true
				_check(vit.fade > 0.4, "the screen fades out")
			if pt > PlayerVitals.RESPAWN_AT + 0.4 and not mark.has("up"):
				mark.up = true
				var courier: Node3D = rider.courier()
				var road: Dictionary = game.world.nearest_road(courier.global_position)
				var off := Vector2(courier.global_position.x - road.point.x, courier.global_position.z - road.point.z).length()
				print("[test] woke at %s, %.1f m from the road, coins %d" % [courier.global_position, off, game.gm.coins])
				_check(not vit.is_down() and not rider.hold and vit.health.current == vit.health.max_health, "he wakes at full health with control back")
				_check(off < 6.0, "he wakes by a road")
				_check(game.gm.coins == 90, "a small coin penalty (10%)")
				_check(vit.health.invulnerable > 0.0 and vit.hit(10.0, Vector3.ZERO) == 0.0, "a moment of invulnerability after waking")
				dir.remove_camp(&"camp.test.fight")
				target = null
				_next()
		7:  # camps stream in near and out far
			if pt > 0.2 and not mark.has("stream"):
				mark.stream = true
				_check(dir.camps.has(&"camp.bandit.0") and dir.camps.has(&"camp.pirate.0"), "the outer world's plan camps are known (bandit and pirate)")
				_check(dir.camps.has(&"camp.core.badlands") and dir.camps.has(&"camp.core.cove"), "two camps near the core (badlands, the cove)")
				rider.request_dismount()
				var p: Vector3 = _ground(range_at.x, range_at.z)
				pl.place(p, Vector3(0, 0, -1))
				game.world.set_focus(pl)
				dir.add_camp(&"camp.test.stream", &"pirate", _ground(p.x + 150.0, p.z), Vector3(-1, 0, 0), 3)
			if pt > 1.0 and not mark.has("near"):
				mark.near = true
				_check(dir.is_spawned(&"camp.test.stream") and dir.enemies_of(&"camp.test.stream").size() == 3, "a camp 150 m away is built with its men")
				var p2: Vector3 = _ground(range_at.x - 260.0, range_at.z - 60.0)
				pl.place(p2, Vector3(0, 0, -1))
			if pt > 2.0 and not mark.has("far"):
				mark.far = true
				_check(not dir.is_spawned(&"camp.test.stream"), "and freed again when the courier is far")
				_check(game.entities.entities_of(&"enemy").filter(func(e): return String(e.get_meta("entity_id", "")).contains("camp_test_stream")).is_empty(), "its men are gone from the entity registry")
				dir.remove_camp(&"camp.test.stream")
				pl.place(range_at, Vector3(0, 0, -1))
				_next()
		8:  # a cleared camp survives save / load
			if pt > 0.5 and not mark.has("clear"):
				mark.clear = true
				var men := _test_camp(&"camp.test.clear", 30.0, 2)
				dir.camps[&"camp.test.clear"].transient = false
				for e in men: e.take_hit(1000.0, false, e.global_position, pl.global_position, &"test")
				_check(dir.is_cleared(&"camp.test.clear"), "killing every man clears the camp")
				mark.kills = dir.stats.kills
				_check(Saves.save_game("combat_test"), "save")
				dir.load_state({})
				_check(not dir.is_cleared(&"camp.test.clear"), "(state reset)")
				_check(Saves.load_game("combat_test"), "load")
			if pt > 1.0 and not mark.has("loaded"):
				mark.loaded = true
				_check(dir.is_cleared(&"camp.test.clear") and dir.stats.kills == int(mark.kills), "the cleared camp and the kill count come back from the save")
				dir.despawn_camp(&"camp.test.clear")
				dir.spawn_camp(&"camp.test.clear")
				_check(dir.is_spawned(&"camp.test.clear") and dir.enemies_of(&"camp.test.clear").is_empty(), "a cleared camp rebuilds its tents but nobody in them")
				dir.remove_camp(&"camp.test.clear")
				_next()
		9:  # a road ambush on an outer highway
			if pt > 0.2 and not mark.has("ambush"):
				mark.ambush = true
				var outer: OuterWorld = game.world.outer
				var road: Dictionary = {}
				var k := -1
				# a stretch of highway with no bridge within ~250 m either way
				for e: Dictionary in outer.roads.roads:
					if e.cls != "highway": continue
					var br: PackedByteArray = e.bridge
					for kk in range(80, (e.pts as PackedVector3Array).size() - 80, 20):
						var clear := true
						for j in range(kk - 70, kk + 70):
							if j < br.size() and br[j] == 1: clear = false; break
						if clear: k = kk; break
					if k >= 0: road = e; break
				var pts: PackedVector3Array = road.pts
				var at := pts[k]
				var fwd := pts[k + 1] - pts[k - 1]; fwd.y = 0.0
				var side := Vector3(-fwd.z, 0, fwd.x).normalized()
				game.bike.place(at + Vector3.UP * 0.5, fwd.normalized())
				pl.place(at + side * 1.5 + Vector3.UP * 0.3, fwd.normalized())
				game.world.set_focus(pl)
				mark.id = dir.spawn_ambush_ahead(true)
				mark.at = at
			if pt > 0.6 and not mark.has("ambush_checked"):
				mark.ambush_checked = true
				var id: StringName = mark.id
				if id == &"": print("[test] no roadblock: courier at %s: %s" % [rider.courier().global_position, dir.ambush_note])
				_check(id != &"" and dir.camps.has(id) and dir.camp(id).layout == &"roadblock", "a roadblock can be set up ahead on an outer highway")
				if id != &"":
					var d := Vector2(dir.camp(id).pos.x - mark.at.x, dir.camp(id).pos.z - mark.at.z).length()
					print("[test] roadblock %.0f m ahead" % d)
					_check(d > 120.0 and d < 260.0, "the roadblock is on the road ahead")
					dir.spawn_camp(id)
					_check(dir.enemies_of(id).size() >= 3, "three or four bandits man it")
					dir.remove_camp(id)
				pl.place(range_at, Vector3(0, 0, -1))
				game.world.set_focus(pl)
				_next()
		10:  # the tin cans still pop
			if pt > 0.5 and not mark.has("can"):
				mark.can = true
				var t: Area3D = gun.targets()[0]
				var stand: Vector3 = t.global_position + Vector3(0, 0, 7.0)
				stand.y = game.world.terrain.height_at(stand.x, stand.z) + 0.1
				pl.place(stand, Vector3(0, 0, -1))
				game.world.set_focus(pl)
				game.cam.snap_to_target()
				mark.hit0 = gun.targets_hit
				sc.intent.aim = true
			if mark.has("can") and pt > 1.0 and pt < 2.4:
				_aim_at(gun.targets()[0].global_position + Vector3(0, 0.13, 0))
			if pt > 2.4 and not mark.has("can_fired"):
				mark.can_fired = true
				sc.press("fire")
			if pt > 2.8:
				print("[test] ", gun.debug_last)
				_check(gun.targets_hit == int(mark.hit0) + 1, "the tin cans still pop")
				_next()
		11:
			print("COMBAT TESTS: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
			get_tree().quit(0 if fails == 0 else 1)
