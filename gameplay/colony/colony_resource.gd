class_name ColonyResource
extends Node3D
var source_id := ""
var item_id := "wood"
var title := ""
var stock := 60
var renewable := false
var renewal := 0.0
func tick(delta: float) -> void:
	# Original source mechanic: exhausted renewable plots regrow 20 after 15 s.
	if renewable and stock==0:
		renewal += delta
		if renewal>=15.0:
			renewal=0.0; stock=20
