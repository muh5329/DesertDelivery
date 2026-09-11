extends Node
## Integration screenshot + functional journal checks against the actual simulation.
var main: Game
var failures:=0
func _ready() -> void:
	main=Game.current
	await get_tree().process_frame
	var book:=main.catalogue
	book.toggle()
	for i in range(100): await get_tree().process_frame
	_assert(book.is_open(),"Journal opens")
	_assert(book.list.rows[book.list.selected].has_focus(),"Journal opens with selected resident focused")
	book.list.rows[-1].grab_focus()
	for i in range(3): await get_tree().process_frame
	_assert(book.list.follow_focus and book.list.scroll_vertical>0,"Keyboard focus scrolls distant residents into view")
	_assert(main.player_controls.blocked,"Journal blocks player controls")
	Input.action_press("fire")
	var intent:=main.player_controls.read(Controls.Foot.new(),.016)
	_assert(not intent.pressed(Controls.FIRE) and intent.move==Vector2.ZERO,"Journal clicks cannot fire or move")
	Input.action_release("fire")
	_assert(book._portraits.size()>0,"Portraits render from character model")
	book.search.text="Mara"; book._populate()
	_assert(book.shown_ids.size()>0,"Search finds resident")
	_assert(book._name.text.contains("Mara"),"Search updates selected page")
	book._notes.text=""; book._notes.grab_focus()
	book._notes.insert_text_at_caret("Remember the herb delivery.")
	await get_tree().process_frame
	_assert(book._notes_by_id.get(book.selected_id,"")=="Remember the herb delivery.","Editing notes updates saved record")
	var saved:=book.save_state(); book._notes_by_id.clear(); book.load_state(saved)
	_assert(book._notes.text=="Remember the herb delivery.","Notes survive save/load")
	book.search.text="zzzz-no-person"; book._populate()
	_assert(book.shown_ids.is_empty() and book._name.text=="No matches","Empty search has clean state")
	book.search.text=""; book._populate()
	book.selected_id="resident.00.00"; book._populate(); book.day_picker.select(0); book._show_day()
	_assert(is_equal_approx(book._grid._row_at(360),1.0) and is_equal_approx(book._grid._row_at(1440),10.0),"Compressed overnight band preserves exact schedule boundaries")
	var morning_tip: String=book._grid._get_tooltip(Vector2(80,28+((book._grid.size.y-28)/10)*1.75))
	_assert(morning_tip.contains("07:00–12:00"),"Compressed chart tooltip resolves actual task times")
	for entry in book.life.by_id[book.selected_id].weekly:
		if int(entry.day)==0: _assert(book.details.text.contains(entry.task),"Monday itinerary includes weekly override")
	for i in range(4): await get_tree().process_frame
	var output:=main.cli.get_string("out","/tmp/catalogue_review.png")
	get_tree().root.get_texture().get_image().save_png(output)
	print("CATALOGUE_SCREENSHOT "+output)
	get_window().size=Vector2i(1280,720)
	for i in range(8): await get_tree().process_frame
	get_tree().root.get_texture().get_image().save_png(output.replace(".png","_1280.png"))
	print("CATALOGUE_SMALL_SCREENSHOT "+output.replace(".png","_1280.png"))
	var key:=InputEventKey.new(); key.keycode=KEY_ESCAPE; key.pressed=true
	book._input(key)
	_assert(not book.is_open() and book.just_closed,"Escape closes and guards game quit")
	_assert(main.player_controls.blocked,"Closing frame still blocks gameplay")
	for i in range(4): await get_tree().process_frame
	_assert(not main.player_controls.blocked,"Gameplay resumes after closing input clears")
	print("CATALOGUE_TESTS_PASS" if failures==0 else "CATALOGUE_TESTS_FAIL")
	get_tree().quit(0 if failures==0 else 1)
func _assert(condition: bool,label: String) -> void:
	if not condition:
		failures+=1; push_error("CATALOGUE_TEST_FAILED "+label)
	else: print("PASS "+label)
