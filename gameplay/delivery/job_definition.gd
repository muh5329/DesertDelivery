class_name JobDefinition
extends Definition
## One courier job: collect `item` at `from_location`, hand it over at `to_location`.
## Locations are world-database ids (see WorldDatabase.locations).

@export var from_location: StringName
@export var to_location: StringName
@export var item := ""
@export var reward := 0
