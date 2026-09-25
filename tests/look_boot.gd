extends Node
## Smoke test for the renderer: N frames from the start camera, memory and frame time each 10.
var n := 0
var t := 0
func _process(_d: float) -> void:
	n += 1
	if n % 5 == 0:
		print("[boot] frame %d  %.0f ms  static %.0f MB  video %.0f MB  textures %.0f MB" % [n, (Time.get_ticks_usec() - t) / 5000.0,
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
			Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0])
		t = Time.get_ticks_usec()
	if n >= Game.current.cli.get_int("frames", 30): get_tree().quit(0)
