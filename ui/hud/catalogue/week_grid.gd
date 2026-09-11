extends Control
## Draw actual schedule intervals, including short weekly overrides, in a 24-hour week.
signal day_selected(day: int)
var life: IslandLife
var record: Resident
var selected_day:=0
var font: Font
const BOUNDARIES := [0,360,480,600,720,840,960,1080,1200,1320,1440]
const COLORS := {"home":Color("b6c1c8"),"work":Color("dbb483"),"cafe":Color("c7b298"),"market":Color("adc3a6"),"outdoors":Color("afbd8a"),"community":Color("c1b0ca")}

func category(entry: Dictionary) -> String:
	var place:=String(entry.get("place","home"))
	if place in COLORS: return place
	return "community"

func _ready() -> void:
	mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	mouse_filter=Control.MOUSE_FILTER_STOP

func _draw() -> void:
	if life==null or record==null: return
	var left:=48.0; var top:=28.0
	var w: float=(size.x-left)/7.0; var h: float=(size.y-top)/10.0
	var ink:=Color("343831")
	for d in range(7):
		var x:=left+d*w
		if d==selected_day:
			draw_style_box(_style(Color("476a7b")),Rect2(x+1,0,w-2,24))
		draw_string(font,Vector2(x+18,18),IslandLife.DAYS[d].substr(0,3),HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("fff5dc") if d==selected_day else ink)
		for entry in record.schedule_for(d):
			var y: float=top+_row_at(float(entry.at))*h
			var height: float=(_row_at(float(entry.until))-_row_at(float(entry.at)))*h
			draw_style_box(_style(COLORS[category(entry)]),Rect2(x+1,y+.7,w-2,maxf(1,height-1.4)))
			if height>16:
				var tag: String={"home":"Home","work":"Work","cafe":"Table","market":"Market","outdoors":"Outside","community":"Visit"}[category(entry)]
				if entry.activity=="sleep": tag="Sleep"
				draw_string(font,Vector2(x+6,y+minf(height-3,17)),tag,HORIZONTAL_ALIGNMENT_LEFT,w-8,12,Color("4f5147"))
	for i in range(10):
		var y:=top+i*h
		draw_string(font,Vector2(0,y+15),"00–06" if i==0 else "%02d:00" % (BOUNDARIES[i]/60),HORIZONTAL_ALIGNMENT_LEFT,-1,13,ink)
		draw_line(Vector2(left,y),Vector2(size.x,y),Color(.96,.93,.85,.5),1)
	var now: float=top+_row_at(life.minute_of_day())*h
	var nx: float=left+life.day_index()*w
	draw_line(Vector2(nx,now),Vector2(nx+w,now),Color("884c3c"),2)
	draw_circle(Vector2(nx,now),3,Color("884c3c"))

func _style(color: Color) -> StyleBoxFlat:
	var s:=StyleBoxFlat.new(); s.bg_color=color; s.set_corner_radius_all(2); return s

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		selected_day=clampi(int((event.position.x-48)/((size.x-48)/7)),0,6)
		day_selected.emit(selected_day); queue_redraw(); accept_event()

func _get_tooltip(at_position: Vector2) -> String:
	if life==null or record==null or at_position.x<48 or at_position.y<28: return "Select a day to read its complete routine below."
	var day:=clampi(int((at_position.x-48)/((size.x-48)/7)),0,6)
	var row:=clampf((at_position.y-28)/(size.y-28)*10,0,9.9999)
	var band:=int(row)
	var minute:=int(lerpf(BOUNDARIES[band],BOUNDARIES[band+1],row-band))
	for entry in record.schedule_for(day):
		if minute>=entry.at and minute<entry.until:
			return "%s · %02d:%02d–%02d:%02d\n%s" % [IslandLife.DAYS[day],int(entry.at)/60,int(entry.at)%60,int(entry.until)/60,int(entry.until)%60,entry.task]
	return ""

func _row_at(minute: float) -> float:
	# The explicitly labeled overnight band makes space for readable daytime tasks.
	if minute>=1440: return 10.0
	for i in range(10):
		if minute<BOUNDARIES[i+1]:
			return i+(minute-BOUNDARIES[i])/float(BOUNDARIES[i+1]-BOUNDARIES[i])
	return 0.0
