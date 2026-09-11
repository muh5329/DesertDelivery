extends Control
## Native parchment, sewn spine and hand-drawn botanical page ornaments.
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var leather:=StyleBoxFlat.new()
	leather.bg_color=Color("453827"); leather.border_color=Color("8d7450")
	leather.set_border_width_all(3); leather.set_corner_radius_all(21)
	leather.shadow_color=Color(0,0,0,.5); leather.shadow_size=16
	draw_style_box(leather,Rect2(48,66,1395,724))
	for i in range(7):
		var paper:=StyleBoxFlat.new(); paper.bg_color=Color("c6b48e").lerp(Color("ecdfbf"),i/7.0)
		paper.border_color=Color("9b896c"); paper.set_border_width_all(1); paper.set_corner_radius_all(14)
		draw_style_box(paper,Rect2(67+i*3,79-i,1360-i*4,695))
	var page:=StyleBoxFlat.new(); page.bg_color=Color("eee3c9")
	page.border_color=Color("b4a080"); page.set_border_width_all(1); page.set_corner_radius_all(14)
	draw_style_box(page,Rect2(94,78,634,688)); draw_style_box(page,Rect2(728,78,684,688))
	# Gentle age marks; fixed seed makes the texture stable while UI redraws.
	var rng:=RandomNumberGenerator.new(); rng.seed=19284
	for i in range(6000):
		var p:=Vector2(rng.randf_range(98,1407),rng.randf_range(84,760))
		draw_circle(p,rng.randf_range(.3,1.6),Color(.36,.24,.10,rng.randf_range(.008,.035)))
	for i in range(30):
		var opacity:=pow(1.0-i/30.0,2)*.10
		draw_line(Vector2(728-i,90),Vector2(728-i,753),Color(.29,.19,.09,opacity),1)
		draw_line(Vector2(729+i,90),Vector2(729+i,753),Color(.29,.19,.09,opacity*.7),1)
	for y in [138,310,483,663]:
		draw_arc(Vector2(728,y),5,-1.2,1.2,12,Color("9f8861"),2,true)
	for x in [127,1377]:
		var sign_dir:=1.0 if x<500 else -1.0
		var c:=Color(.39,.40,.25,.18)
		draw_polyline(PackedVector2Array([Vector2(x,726),Vector2(x+4*sign_dir,682),Vector2(x-3*sign_dir,642),Vector2(x+2*sign_dir,591)]),c,1.2,true)
		for j in range(9):
			var y:=714-j*12
			var dir:=sign_dir*(1.0 if j%2==0 else -1.0)
			draw_polyline(PackedVector2Array([Vector2(x,y),Vector2(x+12*dir,y-14),Vector2(x+16*dir,y-19),Vector2(x+5*dir,y-17),Vector2(x,y)]),c,1,true)
