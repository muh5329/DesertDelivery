class_name Inventory
extends RefCounted
## Goods somewhere: the courier's pack, the Jeep's bed, a Cart. Red Sea Baron's Inventory, as
## it was: known items only, whole positive quantities, a mass capacity (kg), and transfers that
## commit both sides before either announces the change — a refused transfer leaves both sides
## exactly as they were.
##
##   count(id) / contents() / mass() / is_empty()
##   can_add(id, n) / add(id, n) / remove(id, n)
##   transfer_to(destination, id, n) -> bool
##   transfer_available(destination) -> int     everything that fits
##   commit(move, stage, undo)                  a stock move with a change that must go with it
##   summary() / save_state() / restore_contents(d)

signal changed
var capacity: float = 60
var title := "Inventory"
var _items: Dictionary = {}
var _transaction: bool = false


func _init(p_capacity: float = 60.0, p_title: String = "Inventory") -> void:
	capacity = p_capacity
	title = p_title


func count(id: String) -> int:
	return int(_items.get(id, 0))


func contents() -> Dictionary:
	return _items.duplicate(true)


func is_empty() -> bool:
	return _items.is_empty()


func mass() -> float:
	var result := 0.0
	for id: String in _items:
		result += ItemDefinition.get_item(id).mass * count(id)
	return result


## How many more of `id` fit.
func room_for(id: String) -> int:
	var item := ItemDefinition.get_item(id)
	if item == null: return 0
	return maxi(0, floori((capacity - mass()) / item.mass + 0.0001))


func can_add(id: String, amount: int) -> bool:
	var item := ItemDefinition.get_item(id)
	return item != null and amount > 0 and mass() + item.mass * amount <= capacity + 0.0001


func add(id: String, amount: int) -> bool:
	if _transaction or not can_add(id, amount): return false
	_items[id] = count(id) + amount
	changed.emit()
	return true


func remove(id: String, amount: int) -> bool:
	if _transaction or amount <= 0 or count(id) < amount: return false
	_write(id, count(id) - amount)
	changed.emit()
	return true


func clear() -> void:
	if _transaction: return
	_items.clear()
	changed.emit()


func _write(id: String, amount: int) -> void:
	if amount == 0: _items.erase(id)
	else: _items[id] = amount


func transfer_to(destination: Inventory, id: String, amount: int) -> bool:
	if destination == null or destination == self or _transaction or destination._transaction or amount <= 0 \
			or count(id) < amount or not destination.can_add(id, amount):
		return false
	# Commit both sides before notifications; lock callbacks against reentrant transfers.
	_transaction = true
	destination._transaction = true
	_write(id, count(id) - amount)
	destination._write(id, destination.count(id) + amount)
	_transaction = false
	destination._transaction = false
	changed.emit()
	destination.changed.emit()
	return true


## Apply a change that must happen together with a stock move (Red Sea Baron's Transaction):
## stage it, try the move, undo the stage if the move is refused. Returns whether it happened.
static func commit(move: Callable, stage: Callable, undo: Callable) -> bool:
	stage.call()
	if move.call():
		return true
	undo.call()
	return false


func transfer_available(destination: Inventory) -> int:
	var moved := 0
	for id: String in contents():
		var amount := mini(count(id), destination.room_for(id))
		if amount > 0 and transfer_to(destination, id, amount): moved += amount
	return moved


func summary() -> String:
	var lines: PackedStringArray = []
	for id: String in _items:
		lines.append("%s × %d" % [ItemDefinition.get_item(id).title, count(id)])
	return ", ".join(lines) if not lines.is_empty() else "Empty"


static func valid_contents(data: Variant, limit: float) -> bool:
	if not data is Dictionary: return false
	var total := 0.0
	for id in data:
		if not (id is String or id is StringName) or ItemDefinition.get_item(String(id)) == null: return false
		var amount: Variant = data[id]
		if typeof(amount) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(amount)) or amount < 0 or amount != floor(amount): return false
		total += float(amount) * ItemDefinition.get_item(String(id)).mass
	return total <= limit + 0.0001


func save_state() -> Dictionary:
	return _items.duplicate(true)


func restore_contents(data: Dictionary) -> bool:
	if _transaction or not valid_contents(data, capacity): return false
	_items.clear()
	for id in data:
		if int(data[id]) > 0: _items[String(id)] = int(data[id])
	changed.emit()
	return true
