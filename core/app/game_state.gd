class_name GameState
extends RefCounted
## Session-wide facts that are not owned by any one system: elapsed time, fps stats,
## the autotest contract. Anything persistent goes through SaveManager instead.

var time := 0.0
var fps_acc := 0.0
var fps_n := 0
var autotest := false
var need_deliveries := 1
var max_time := 240.0
var shots_dir := ""
var shot_interval := 4.0


func avg_fps() -> float:
	return fps_acc / maxf(fps_n, 1)
