extends Node
## Quiet place-dependent ambience, authored by tools/audio/island_ambience.py.
## Audio loops run on the mixer; no per-sample work in the game thread.
var _breeze: AudioStreamPlayer
var _shore: AudioStreamPlayer
var _birds: AudioStreamPlayer
var _tick:=0.0
var _coast:=0.0
var _garden:=0.0

func _ready() -> void:
	if DisplayServer.get_name()=="headless": set_process(false); return
	_breeze=_loop("breeze",-28.0)
	_shore=_loop("shore",-60.0)
	_birds=_loop("garden_birds",-25.0)

func _loop(asset: String, volume: float) -> AudioStreamPlayer:
	var stream: AudioStreamWAV=load("res://assets/audio/%s.wav"%asset)
	stream.loop_mode=AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin=0; stream.loop_end=int(stream.get_length()*stream.mix_rate)
	var node:=AudioStreamPlayer.new(); node.stream=stream; node.volume_db=volume
	add_child(node); node.play(); return node

func _process(delta: float) -> void:
	var game:=Game.current
	if not game or not game.life: return
	_tick-=delta
	if _tick<=0:
		_tick=.5
		var p: Vector3=game.rider.courier().global_position
		var water:=0.0
		for i in range(8):
			var probe:=Vector2(p.x,p.z)+Vector2.from_angle(i*TAU/8)*32
			if game.world.terrain.height_at(probe.x,probe.y)<0: water+=.125
		_coast=water*(1-smoothstep(12,48,p.y))
		var hour:=game.life.minute_of_day()/60.0
		_garden=smoothstep(5,7,hour)*(1-smoothstep(18,21,hour))*(1-water*.6)
		if game.rider.active_vehicle()==game.bike and game.bike.airborne: _garden=0
	_shore.volume_db=lerpf(_shore.volume_db,lerpf(-60,-15,_coast),minf(1,delta*2))
	_birds.volume_db=lerpf(_birds.volume_db,lerpf(-60,-23,_garden),minf(1,delta*2))
