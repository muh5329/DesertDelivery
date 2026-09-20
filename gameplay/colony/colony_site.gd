class_name ColonySite
extends Node3D
signal completed
var site_id := ""
var blueprint := "Depot"
var built := false
var inventory: Dictionary = {}
var field: ColonyResource
func receive(item: String, amount: int) -> void:
	inventory[item] = int(inventory.get(item,0)) + amount
	if not built and int(inventory.get("wood",0)) >= 10:
		inventory.wood -= 10
		built = true
		completed.emit()
