class_name Definition
extends Resource
## Base of every data definition: a stable id and a display name. Definitions are the game's
## database (read-only at runtime); runtime state lives in entities and in the save file.

@export var id: StringName
@export var display_name: String


func label() -> String:
	return display_name if display_name != "" else String(id)
