class_name JobDefinition
extends Definition
## One courier job: collect `item` at `from_location`, hand it over at `to_location`.
## Locations are world-database ids (see WorldDatabase.locations).

@export var from_location: StringName
@export var to_location: StringName
@export var item := ""
@export var reward := 0

## Optional board consignment; default route resources retain the original chain.
@export var cargo_mass_kg := 0.0
@export var cargo_kind := "standard"

## "cargo": only the Jeep, or a rig towing the Cart, may collect it (urgent colony supplies);
## a save from before the Jeep says "truck", read the same way.
@export var vehicle := ""
