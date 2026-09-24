class_name CharacterLook
extends RefCounted
## What a townsperson looks like, decided deterministically from a seed, a town style and an
## occupation, and applied to a RiderModel as a procedurally built, skinned body
## (entities/people: PersonBuilder). Nothing is stored: the same inputs give the same person.
##
## Interface:
##   CharacterLook.from_seed(seed, &"puerto", "dockworker"[, sex])  -> look Dictionary
##   CharacterLook.spawn(seed, style, occupation)                   -> a ready RiderModel
##   CharacterLook.apply(model, look)                               -> dress an existing model
##   CharacterLook.for_resident(record)                             -> the look of an islander
##   CharacterLook.signature(look)                                  -> (hair, hair colour, top, top colour)
##   CharacterLook.STYLES                                           -> the town styles
##
## Axes: sex, age (adults and elders: grey hair, a stoop), height 0.9-1.1, build -1..1
## (slim / average / heavy: girth, belly, limb thickness), skin tone (ten-step realistic
## ramp), face (jaw, chin, nose length/width/bridge/projection/tip, brow ridge, cheekbones,
## lips, mouth width, eye size/spacing/tilt, face length, forehead, ears), eye colour, brows,
## facial hair (stubble, moustache, goatee, beard, full beard), 13 hair styles in 12 colours,
## 11 garments with fabrics (cotton, linen, wool, knit, denim, leather) and patterns
## (stripes, pinstripe, checks, plaid, dots, cable, rib, bands), trousers / shorts / skirts,
## shoes / boots / sandals, hats, aprons, glasses, neckerchiefs and satchels.

const STYLES: Array[StringName] = [&"island", &"puerto", &"valdoro", &"sarmada", &"isola", &"campo"]

const HAIR_STYLES: Array[String] = ["crop", "buzz", "side_part", "textured", "afro", "curly", "long_straight",
	"long_wavy", "bun", "ponytail", "braid", "balding", "bald", "headscarf"]
const TOPS: Array[String] = ["shirt", "tshirt", "blouse", "sweater", "vest", "jacket", "coat", "dress", "overalls", "tunic", "robe"]

## Monk-style skin tone ramp, lightest to deepest.
const SKIN_RAMP := ["f2d6c2", "ebc7ab", "e2b894", "d4a47e", "c38f68", "a57452", "885a3e", "6b4430", "503225", "3b251b"]
const HAIR_COLORS := {"black": "1b1512", "dark_brown": "33241b", "brown": "553a28", "chestnut": "74432a", "auburn": "7c3420",
	"copper": "9c4f27", "dark_blonde": "9a7a4a", "blonde": "c9a86c", "platinum": "ddd0ae", "salt_pepper": "5e5a55", "grey": "908c86", "white": "e4e1da"}
const EYE_COLORS := {"dark_brown": "3a2416", "brown": "5b3a22", "hazel": "7a5a2c", "green": "5d7a4a", "blue": "4f7aa6", "grey": "74828a"}

const FEMALE_NAMES := ["Mara", "Ines", "Rosa", "Nora", "Ada", "Celia", "Elsa", "Greta", "Iris", "Kira", "Mina", "Olive",
	"Sana", "Uma", "Willa", "Yara", "Alma", "Clara", "Flora", "Hana", "Ida", "Lena", "Nina", "Pia", "Sara", "Vera",
	"Bea", "Dina", "Faye", "Hope", "Wren", "Quinn"]

const DISTRICT_STYLE := {"Villa Rosa": &"island", "Hilltop Farm": &"campo", "Harbour": &"puerto", "Dunes": &"sarmada",
	"San Telmo": &"island", "Marble Quarry": &"valdoro", "Cala Blanca": &"isola", "Salinas": &"island"}

## Per town: skin tone (mean, spread on the ramp), dark-hair bias, garment weights by sex,
## palette (name -> hex), bottoms, fabric and pattern weights, hats, shoes.
const STYLE_DATA := {
	&"island": {
		"skin": [4.0, 1.6], "dark": .6,
		"tops_m": {"shirt": 4, "tshirt": 2, "vest": 1, "sweater": 1, "jacket": 1, "tunic": 1},
		"tops_f": {"dress": 4, "blouse": 3, "shirt": 1, "sweater": 1, "tshirt": 1},
		"colors": {"cream": "efe8da", "white": "f7f5ef", "sand": "c9b28a", "terracotta": "b8603c", "olive": "7d8b5a",
			"sage": "9fb59a", "sky": "7aa2c6", "indigo": "3f5a7a", "ochre": "d0a24a", "rose": "d99a9a", "teal": "4f7f8c", "brick": "8c4b3f"},
		"bottoms": {"linen": "d8ccb0", "khaki": "b89c72", "navy": "3f4d66", "brown": "6b5a48", "white": "e8e2d4", "olive": "6d7a4c", "charcoal": "3a3a3a", "denim": "4a6285"},
		"fabrics": {"linen": 4, "cotton": 5, "denim": 1}, "patterns": {"plain": 10, "stripes": 2, "checks": 2, "pinstripe": 1, "dots": 1, "plaid": 1},
		"hats_m": {"": 10, "straw": 3, "flat_cap": 2, "beret": 1}, "hats_f": {"": 12, "straw": 2, "sunhat": 2},
		"shoes": {"sandals": 3, "shoes": 5, "boots": 2}},
	&"puerto": {
		"skin": [4.2, 2.3], "dark": .6,
		"tops_m": {"shirt": 3, "tshirt": 3, "vest": 2, "jacket": 2, "sweater": 1, "coat": 1},
		"tops_f": {"blouse": 3, "dress": 3, "sweater": 1, "coat": 1, "shirt": 1, "tshirt": 1},
		"colors": {"navy": "22324d", "cream": "efe6cf", "white": "f6f4ee", "slate": "5d6d7e", "charcoal": "3a3d42",
			"burgundy": "7a2e35", "mustard": "c9962b", "sky": "8fb1cf", "brick": "9a4a3a", "tile_blue": "2f5f8a"},
		"bottoms": {"navy": "26324a", "charcoal": "3a3a3e", "khaki": "a8956b", "denim": "3f5a80", "grey": "7b7d80", "brown": "5a4533"},
		"fabrics": {"cotton": 6, "wool": 2, "linen": 2, "denim": 1}, "patterns": {"plain": 8, "stripes": 5, "pinstripe": 2, "checks": 1},
		"hats_m": {"": 8, "flat_cap": 4, "knit": 1, "beret": 2}, "hats_f": {"": 12, "beret": 1, "kerchief": 1},
		"shoes": {"shoes": 7, "boots": 3}},
	&"valdoro": {
		"skin": [2.0, 1.2], "dark": .35,
		"tops_m": {"sweater": 3, "vest": 3, "jacket": 2, "coat": 1, "shirt": 2},
		"tops_f": {"dress": 3, "sweater": 2, "blouse": 2, "coat": 1},
		"colors": {"loden": "4d5e3a", "forest": "2f4a33", "burgundy": "6e2a2c", "charcoal": "3c3c3a", "brown": "5b4331",
			"cream": "e9e0c8", "red": "a83a32", "grey": "8a8a84", "mustard": "b48a2c", "pine": "1f3a33"},
		"bottoms": {"charcoal": "3a3a38", "brown": "54402f", "loden": "46553a", "grey": "6f6f6b", "leather": "5a3f2a"},
		"fabrics": {"wool": 6, "knit": 2, "cotton": 2, "linen": 1}, "patterns": {"plain": 7, "checks": 3, "plaid": 3, "herringbone": 2, "cable": 1},
		"hats_m": {"": 6, "felt": 4, "knit": 2, "flat_cap": 1}, "hats_f": {"": 9, "felt": 2, "knit": 2, "kerchief": 1},
		"shoes": {"boots": 7, "shoes": 3}},
	&"sarmada": {
		"skin": [5.7, 1.5], "dark": .85,
		"tops_m": {"tunic": 3, "robe": 3, "shirt": 2, "vest": 1},
		"tops_f": {"robe": 3, "dress": 3, "tunic": 2, "blouse": 1},
		"colors": {"white": "f1ece0", "sand": "d8c29a", "ochre": "c8923a", "terracotta": "b25a37", "rust": "8f3f25",
			"indigo": "2b3a6b", "saffron": "e0a526", "olive": "6f6b3a", "camel": "b58a55", "deep_blue": "1f4f7a"},
		"bottoms": {"sand": "cdb88f", "white": "e9e2d2", "indigo": "2d3b66", "brown": "6b4e36", "olive": "66633a"},
		"fabrics": {"linen": 5, "cotton": 5}, "patterns": {"plain": 9, "bands": 3, "stripes": 2, "pinstripe": 1},
		"hats_m": {"": 5, "headwrap": 5}, "hats_f": {"": 10},
		"shoes": {"sandals": 8, "shoes": 2}},
	&"isola": {
		"skin": [3.6, 1.6], "dark": .55,
		"tops_m": {"sweater": 3, "shirt": 3, "tshirt": 2, "overalls": 1, "vest": 1},
		"tops_f": {"dress": 5, "blouse": 2, "sweater": 1, "tshirt": 1},
		"colors": {"pink": "e8b4b8", "mint": "a8d5ba", "butter": "f3dd8e", "powder": "a7c7e7", "lavender": "c3b1e1",
			"white": "f8f6f0", "coral": "f08a6c", "navy": "263a57", "cream": "efe6d2", "seafoam": "8fc9c0"},
		"bottoms": {"white": "ece8dc", "navy": "2c3d5a", "khaki": "b3a07a", "sky": "8fb1cf", "denim": "5a7aa0"},
		"fabrics": {"cotton": 6, "linen": 3, "knit": 1}, "patterns": {"plain": 8, "stripes": 3, "checks": 2, "dots": 2},
		"hats_m": {"": 8, "straw": 4, "knit": 2}, "hats_f": {"": 9, "straw": 3, "sunhat": 3},
		"shoes": {"sandals": 5, "shoes": 4, "boots": 1}},
	&"campo": {
		"skin": [3.8, 1.8], "dark": .5,
		"tops_m": {"shirt": 4, "overalls": 3, "vest": 1, "tshirt": 1, "jacket": 1},
		"tops_f": {"dress": 3, "blouse": 3, "overalls": 1, "shirt": 1},
		"colors": {"denim": "3c5a80", "khaki": "a8956b", "brown": "6e5237", "faded_red": "a5473b", "wheat": "d9c28e",
			"green": "5d7a44", "cream": "ece3cd", "rust": "9a5530", "sky": "86a9c9", "plum": "6c3f55"},
		"bottoms": {"denim": "3d5578", "khaki": "9c8a62", "brown": "5d4632", "olive": "5f6b40", "charcoal": "404040"},
		"fabrics": {"cotton": 6, "denim": 2, "linen": 2}, "patterns": {"plain": 7, "plaid": 4, "checks": 3, "stripes": 1},
		"hats_m": {"": 6, "flat_cap": 3, "straw": 3}, "hats_f": {"": 9, "straw": 2, "kerchief": 2},
		"shoes": {"boots": 6, "shoes": 4}},
}

## Occupation cues: garment weights, fixed colours, hats, aprons, extras.
const OCCUPATIONS := {
	"baker": {"tops_m": {"shirt": 3, "tshirt": 2}, "tops_f": {"blouse": 2, "dress": 2, "shirt": 1}, "colors": {"flour": "f2ede0", "white": "fbfaf6", "cream": "ece4d0"},
		"apron": ["bib", .9, ["f7f4ec", "ece6d6"]], "hats": {"baker": 5, "": 3, "kerchief": 1}, "sleeves": "rolled"},
	"fisher": {"tops_m": {"sweater": 4, "overalls": 2, "tshirt": 1, "jacket": 1}, "tops_f": {"sweater": 3, "overalls": 1, "blouse": 1},
		"colors": {"navy": "263a57", "cream_knit": "e8dfc8", "oilskin": "d8b43a", "slate": "4f5f6f"}, "hats": {"knit": 5, "": 3, "straw": 1},
		"shoes": "boots", "pattern": "cable"},
	"farmer": {"tops_m": {"overalls": 3, "shirt": 3, "vest": 1}, "tops_f": {"overalls": 2, "blouse": 2, "dress": 1},
		"hats": {"straw": 4, "flat_cap": 2, "": 2}, "shoes": "boots", "pattern": "plaid"},
	"dockworker": {"tops_m": {"tshirt": 3, "shirt": 2, "vest": 1, "jacket": 1}, "tops_f": {"shirt": 2, "tshirt": 1, "overalls": 1},
		"colors": {"work_blue": "2f4e78", "navy": "22324d", "cream": "efe6cf", "rust": "8f4a2e"}, "hats": {"flat_cap": 4, "knit": 2, "": 3},
		"shoes": "boots", "build": .35, "sleeves": "rolled", "pattern": "stripes"},
	"merchant": {"tops_m": {"vest": 3, "shirt": 2, "jacket": 1}, "tops_f": {"blouse": 3, "dress": 2, "vest": 1},
		"apron": ["waist", .4, ["e9e2cf", "5b4a3a", "2f3d52"]], "hats": {"": 6, "flat_cap": 1}},
	"mechanic": {"tops_m": {"overalls": 5, "tshirt": 1}, "tops_f": {"overalls": 4, "shirt": 1},
		"colors": {"work_blue": "3a5577", "grey": "6d7275", "khaki": "8f8360", "navy": "2a3547"}, "hats": {"flat_cap": 3, "": 4}, "shoes": "boots", "sleeves": "rolled"},
	"teacher": {"tops_m": {"jacket": 3, "sweater": 2, "shirt": 2, "vest": 1}, "tops_f": {"blouse": 3, "dress": 2, "sweater": 2, "jacket": 1},
		"glasses": .55, "satchel": .5},
	"gardener": {"tops_m": {"shirt": 3, "tshirt": 2, "overalls": 1}, "tops_f": {"blouse": 2, "shirt": 2, "overalls": 1},
		"apron": ["waist", .6, ["6f7a4a", "8a7a58", "5a6b52"]], "hats": {"straw": 5, "": 2, "sunhat": 1}},
	"shepherd": {"tops_m": {"vest": 2, "sweater": 2, "shirt": 1, "coat": 1}, "tops_f": {"sweater": 2, "dress": 1, "coat": 1},
		"hats": {"felt": 3, "straw": 2, "": 2}, "shoes": "boots", "satchel": .5, "pattern": "plain"},
	"ranger": {"tops_m": {"jacket": 3, "shirt": 2}, "tops_f": {"jacket": 3, "shirt": 2},
		"colors": {"khaki": "8c7f55", "olive": "5a6440", "forest": "34493a"}, "hats": {"felt": 4, "": 2}, "shoes": "boots"},
	"stonemason": {"tops_m": {"tshirt": 3, "shirt": 2}, "tops_f": {"shirt": 2, "tshirt": 1},
		"colors": {"dust": "cfc6b4", "grey": "8b8a85", "ochre": "b5904f", "white": "efece4"}, "hats": {"flat_cap": 3, "": 4},
		"apron": ["leather", .5, ["6b4a30", "5a3d28"]], "shoes": "boots", "build": .35, "sleeves": "rolled"},
	"courier": {"tops_m": {"shirt": 2, "vest": 2, "jacket": 1}, "tops_f": {"shirt": 2, "blouse": 1, "vest": 1},
		"hats": {"flat_cap": 4, "": 3}, "satchel": .8},
	"driver": {"tops_m": {"shirt": 2, "jacket": 2, "vest": 1}, "tops_f": {"blouse": 2, "jacket": 1, "shirt": 1}, "hats": {"flat_cap": 3, "": 4}},
	"weaver": {"tops_m": {"tunic": 2, "shirt": 2}, "tops_f": {"dress": 2, "blouse": 2}, "apron": ["waist", .4, ["c8923a", "2b3a6b"]]},
	"vendor": {"tops_m": {"shirt": 2, "vest": 2, "tunic": 1}, "tops_f": {"blouse": 2, "dress": 2}, "apron": ["waist", .5, ["e9e2cf", "b25a37"]]},
	"porter": {"tops_m": {"tshirt": 2, "tunic": 2}, "tops_f": {"tunic": 2}, "build": .3, "sleeves": "rolled"},
	"cook": {"tops_m": {"tshirt": 2, "shirt": 2}, "tops_f": {"blouse": 2, "dress": 1}, "apron": ["bib", .8, ["f7f4ec"]], "hats": {"baker": 2, "": 2, "kerchief": 1}},
}
const OCCUPATION_ALIASES := {"produce driver": "driver", "shopkeeper": "merchant", "fisherman": "fisher", "fisherwoman": "fisher",
	"shop": "merchant", "trader": "merchant", "docker": "dockworker", "stevedore": "dockworker", "farmhand": "farmer",
	"market seller": "vendor", "grocer": "merchant", "butcher": "merchant", "carter": "driver", "innkeeper": "merchant", "chef": "cook"}

static var _resident_cache: Dictionary = {}


# ------------------------------------------------------------------ public API
static func from_seed(seed: int, style: StringName = &"island", occupation: String = "", sex: String = "") -> Dictionary:
	if not STYLE_DATA.has(style): style = &"island"
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, String(style), occupation])
	var st: Dictionary = STYLE_DATA[style]
	var occ_key := _occupation_key(occupation)
	var occ: Dictionary = OCCUPATIONS.get(occ_key, {})
	var look := {"seed": seed, "style": style, "occupation": occupation}
	# who
	var female := (sex == "f") if sex != "" else rng.randf() < .5
	look.sex = "f" if female else "m"
	var roll := rng.randf()
	var age := rng.randi_range(19, 34) if roll < .34 else (rng.randi_range(35, 57) if roll < .78 else rng.randi_range(58, 84))
	look.age = age
	var elder := age >= 62
	look.height = clampf((.955 if female else 1.035) + rng.randfn(0.0, .035) - (.02 if elder else 0.0), .9, 1.1)
	var build := clampf(rng.randfn(.05, .45) + (.15 if age > 45 else 0.0) + float(occ.get("build", 0.0)), -1.0, 1.0)
	look.build = build
	look.build_class = "slim" if build < -.3 else ("heavy" if build > .38 else "average")
	look.stoop = (rng.randf_range(.08, .2) if elder else 0.0)
	# townsfolk carry their arms clear of hips, skirts and bellies (the courier's pose holds
	# them 6 degrees in); heavier people further out
	look.arm_spread = deg_to_rad(12.0 + maxf(build, 0.0) * 6.0 + (2.0 if female else 0.0) + (3.0 if look.build_class == "heavy" else 0.0))
	# skin, eyes
	var tone := clampf(rng.randfn(float(st.skin[0]), float(st.skin[1])), 0.0, 9.0)
	look.skin_tone = tone
	var i0 := floori(tone); var i1 := mini(i0 + 1, 9)
	var skin := Color(SKIN_RAMP[i0]).lerp(Color(SKIN_RAMP[i1]), tone - float(i0))
	# undertone: a little warmer, rosier or more olive
	var under := rng.randf_range(-1.0, 1.0)
	skin = Color(skin.r * (1.0 + .025 * under), skin.g * (1.0 - .01 * absf(under)), skin.b * (1.0 - .03 * under))
	look.skin = skin
	var eye_w := {"dark_brown": 3.0, "brown": 3.0, "hazel": 1.5, "green": 1.0, "blue": 1.2, "grey": .6}
	if tone > 4.5:
		eye_w = {"dark_brown": 6.0, "brown": 3.0, "hazel": 1.0, "green": .3, "blue": .1, "grey": .1}
	elif tone < 2.5:
		eye_w = {"dark_brown": 1.0, "brown": 2.0, "hazel": 1.5, "green": 1.5, "blue": 3.0, "grey": 1.2}
	var eye_name: String = _pick(rng, eye_w)
	look.eye_name = eye_name
	look.eyes = Color(EYE_COLORS[eye_name])
	# hair
	var hc := _hair_color(rng, tone, float(st.dark), age, style)
	look.hair_color_name = hc
	look.hair_color = _jitter(rng, Color(HAIR_COLORS[hc]), .012, .06)
	var brow := Color(HAIR_COLORS[hc])
	if hc in ["grey", "white", "salt_pepper"]: brow = Color(HAIR_COLORS["salt_pepper"]).lerp(Color(HAIR_COLORS[hc]), .5)
	if hc in ["platinum", "blonde"]: brow = brow.darkened(.3)
	look.brow_color = brow.darkened(.1)
	look.hair = _hair_style(rng, female, age, tone, style)
	look.hair_len = rng.randf_range(.24, .36)
	look.recede = rng.randf_range(.0, .02) if not female and age > 40 else 0.0
	# face
	var s := func(mean: float, sd: float) -> float: return clampf(rng.randfn(mean, sd), mean - 2.2 * sd, mean + 2.2 * sd)
	look.face = {
		"jaw": s.call(1.07 if not female else .95, .06), "chin": s.call(1.1 if not female else .9, .25),
		"nose_len": s.call(1.0 + (.05 if elder else 0.0), .07), "nose_width": s.call(1.05 if not female else .94, .1) + (tone - 4.0) * .015,
		"nose_bridge": s.call(.4, .6), "nose_proj": s.call(1.05 if not female else .94, .12), "nose_tip": s.call(0.0, .8),
		"brow": s.call(1.35 if not female else .7, .25), "brow_thick": s.call(1.15 if not female else .82, .15), "brow_arch": s.call(.8 if not female else 1.15, .25),
		"cheek": s.call(1.0, .3), "lips": s.call(.95 if not female else 1.18, .15) - (.12 if elder else 0.0), "mouth_w": s.call(1.0, .06),
		"eye_size": s.call(1.0 if not female else 1.05, .06), "eye_gap": s.call(1.0, .035), "eye_tilt": s.call(0.0, .8),
		"face_len": s.call(1.0, .035), "forehead": s.call(1.0, .035), "ear": s.call(1.0 + (.08 if elder else 0.0), .08), "width": s.call(1.0, .03)}
	var fh := "none"
	if not female:
		var w := {"none": 5.0, "stubble": 3.0, "moustache": 2.0, "beard": 2.0, "full_beard": 1.0, "goatee": .6}
		if style == &"sarmada": w = {"none": 3.0, "stubble": 2.0, "moustache": 2.0, "beard": 3.0, "full_beard": 2.0, "goatee": .5}
		if style == &"valdoro": w = {"none": 4.0, "stubble": 2.0, "moustache": 2.0, "beard": 2.0, "full_beard": 2.0, "goatee": .3}
		fh = _pick(rng, w)
	look.facial_hair = fh
	_dress(look, rng, st, occ, female, elder, style)
	look.key = "%d|%s|%s" % [seed, String(style), occupation]
	return look


static func spawn(seed: int, style: StringName, occupation: String = "") -> RiderModel:
	var model := RiderModel.new()
	apply(model, from_seed(seed, style, occupation))
	return model


## Dress `model` as `look`. Before the model enters the tree this only records the look;
## afterwards it swaps the meshes (the rig is shared) and the body scale.
static func apply(model: RiderModel, look: Dictionary) -> void:
	model.set_look(look)


static func signature(look: Dictionary) -> Array:
	return [look.hair, look.hair_color_name, look.top, look.top_color_name]


## The look of one of the 64 residents: style from the district, sex from the first name,
## seed from the stable id. Looks are resolved together so no two residents share a
## signature (a clash re-rolls the later resident's seed, deterministically).
static func for_resident(record) -> Dictionary:
	if _resident_cache.is_empty(): _resolve_residents()
	var id := String(record.id)
	if _resident_cache.has(id): return _resident_cache[id]
	return from_seed(absi(id.hash()), style_for_district(String(record.district)), String(record.occupation), sex_for_name(String(record.name)))


static func style_for_district(district: String) -> StringName:
	return DISTRICT_STYLE.get(district, &"island")


static func sex_for_name(full_name: String) -> String:
	var first := full_name.get_slice(" ", 0)
	return "f" if first in FEMALE_NAMES else ("m" if first != "" else "")


static func _resolve_residents() -> void:
	var text := FileAccess.get_file_as_string("res://data/life/residents.json")
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary: return
	var seen: Dictionary = {}
	var sources: Array = (parsed.residents as Array).duplicate()
	sources.sort_custom(func(a, b): return String(a.id) < String(b.id))
	for src in sources:
		var id := String(src.id)
		var style := style_for_district(String(src.get("district", "")))
		var sex := sex_for_name(String(src.get("name", "")))
		var seed := absi(id.hash())
		var look := from_seed(seed, style, String(src.get("occupation", "")), sex)
		var tries := 0
		while seen.has(str(signature(look))) and tries < 40:
			tries += 1
			look = from_seed(seed + tries * 7919, style, String(src.get("occupation", "")), sex)
		seen[str(signature(look))] = id
		_resident_cache[id] = look


# ------------------------------------------------------------------ choices
static func _occupation_key(occupation: String) -> String:
	var key := occupation.to_lower().strip_edges()
	return OCCUPATION_ALIASES.get(key, key)


static func _pick(rng: RandomNumberGenerator, weights: Dictionary):
	var total := 0.0
	for k in weights: total += float(weights[k])
	var r := rng.randf() * total
	for k in weights:
		r -= float(weights[k])
		if r <= 0.0: return k
	return weights.keys()[-1]


static func _jitter(rng: RandomNumberGenerator, c: Color, hue: float, amount: float) -> Color:
	var h := fposmod(c.h + rng.randf_range(-hue, hue), 1.0)
	var s := clampf(c.s * rng.randf_range(1.0 - amount * 1.6, 1.0 + amount * 1.6), 0.0, 1.0)
	var v := clampf(c.v * rng.randf_range(1.0 - amount, 1.0 + amount * .6), 0.0, 1.0)
	return Color.from_hsv(h, s, v)


static func _hair_color(rng: RandomNumberGenerator, tone: float, dark: float, age: int, style: StringName) -> String:
	if age >= 56 and rng.randf() < clampf((float(age) - 50.0) / 22.0, .3, .95):
		return _pick(rng, {"grey": 3.0, "white": 2.0 if age > 66 else .6, "salt_pepper": 2.5})
	var w := {"black": 2.0, "dark_brown": 3.0, "brown": 2.5, "chestnut": 1.2, "auburn": .6, "copper": .3, "dark_blonde": .8, "blonde": .5, "platinum": .1}
	if tone > 5.0:
		w = {"black": 6.0, "dark_brown": 3.0, "brown": .8, "chestnut": .2}
	elif tone < 2.6 or style == &"valdoro":
		w = {"black": .6, "dark_brown": 1.5, "brown": 2.5, "chestnut": 1.5, "auburn": 1.0, "copper": .6, "dark_blonde": 2.0, "blonde": 1.6, "platinum": .5}
	if dark > .7 and tone > 3.5: w["black"] = float(w.get("black", 0.0)) + 2.0
	return _pick(rng, w)


static func _hair_style(rng: RandomNumberGenerator, female: bool, age: int, tone: float, style: StringName) -> String:
	var w: Dictionary
	if female:
		w = {"long_straight": 3.0, "long_wavy": 3.0, "bun": 3.0, "ponytail": 2.5, "braid": 1.5, "curly": 1.5, "crop": .6, "side_part": .8, "textured": .4}
		if age > 58: w = {"bun": 4.0, "crop": 2.0, "curly": 1.5, "side_part": 1.5, "textured": 1.0, "headscarf": 1.0}
		if tone > 5.0: w["afro"] = 1.8; w["curly"] = float(w.get("curly", 0.0)) + 1.5; w["braid"] = float(w.get("braid", 0.0)) + 1.0
		if style == &"sarmada": w["headscarf"] = 7.0
		elif style in [&"campo", &"isola"]: w["headscarf"] = float(w.get("headscarf", 0.0)) + (1.5 if age > 45 else .4)
	else:
		w = {"crop": 4.0, "side_part": 3.0, "textured": 2.5, "buzz": 1.2, "curly": 1.0, "long_straight": .4, "ponytail": .3}
		if age > 42: w["balding"] = 2.0 + float(age - 42) * .08; w["bald"] = .8
		if tone > 5.0: w["afro"] = 1.2; w["textured"] = 3.5; w["buzz"] = 2.5
	return _pick(rng, w)


static func _palette_pick(rng: RandomNumberGenerator, palette: Dictionary) -> String:
	var keys := palette.keys()
	return keys[rng.randi() % keys.size()]


static func _dress(look: Dictionary, rng: RandomNumberGenerator, st: Dictionary, occ: Dictionary, female: bool, elder: bool, style: StringName) -> void:
	var tops: Dictionary = occ.get("tops_f" if female else "tops_m", st["tops_f" if female else "tops_m"])
	# town flavour stays in the mix even for an occupation
	if not occ.is_empty():
		tops = tops.duplicate()
		for k in st["tops_f" if female else "tops_m"]:
			tops[k] = float(tops.get(k, 0.0)) + float(st["tops_f" if female else "tops_m"][k]) * .15
	var top: String = _pick(rng, tops)
	if top == "overalls" and style == &"sarmada": top = "tunic"
	look.top = top
	var palette: Dictionary = st.colors.duplicate()
	if occ.has("colors") and rng.randf() < .8:
		palette = occ.colors
	var color_name := _palette_pick(rng, palette)
	look.top_color_name = color_name
	var top_color := _jitter(rng, Color(palette[color_name]), .01, .06)
	look.top_color = top_color
	# fabric and pattern
	var fabric_name: String = _pick(rng, st.fabrics)
	if top in ["sweater"]: fabric_name = "knit"
	elif top == "overalls": fabric_name = "denim" if rng.randf() < .7 else "cotton"
	elif top in ["coat", "jacket"] and style in [&"valdoro", &"puerto"]: fabric_name = "wool"
	elif top in ["robe", "tunic"]: fabric_name = "linen" if rng.randf() < .6 else "cotton"
	elif fabric_name == "knit": fabric_name = "wool"
	elif fabric_name == "denim" and top in ["dress", "blouse"]: fabric_name = "cotton"
	look.top_fabric = _mat(fabric_name)
	var pattern_name: String = _pick(rng, st.patterns)
	if occ.has("pattern") and rng.randf() < .5: pattern_name = occ.pattern
	if top == "sweater": pattern_name = "cable" if (style in [&"isola", &"valdoro"] or occ.get("pattern", "") == "cable") and rng.randf() < .6 else "rib"
	if top in ["overalls", "coat"] and pattern_name in ["stripes", "dots", "checks", "plaid"]: pattern_name = "plain"
	if pattern_name == "dots" and not female: pattern_name = "plain"
	if pattern_name == "bands" and not top in ["robe", "tunic", "dress"]: pattern_name = "plain"
	if pattern_name == "cable" and top != "sweater": pattern_name = "plain"
	look.top_pattern = _pattern(pattern_name)
	var second := _second_color(rng, top_color, pattern_name, palette)
	look.top_color2 = second
	# what shows under an open or bibbed top
	look.under = ""
	look.under_color = top_color
	look.under_fabric = look.top_fabric
	look.under_pattern = 0
	look.under_color2 = second
	if top in ["vest", "jacket", "coat", "overalls"]:
		var under: String = "shirt"
		if top == "overalls" and rng.randf() < .4: under = "tshirt"
		if top == "coat" and rng.randf() < .35: under = "sweater"
		if top == "jacket" and female and rng.randf() < .5: under = "blouse"
		look.under = under
		var light := {"white": "f4f1e8", "cream": "ece3cd", "pale_blue": "c9d8e6", "ecru": "e0d6bd", "pale_stripe": "eeeae0"}
		if under == "sweater": light = {"cream": "e6dcc4", "grey": "8d8b86", "navy": "2c3a52", "moss": "5e6b45"}
		if top == "overalls" and under == "tshirt": light = {"white": "f2efe6", "red": "a8463a", "grey": "8e8e8a", "navy": "2f3d56"}
		var under_name := _palette_pick(rng, light)
		look.under_color = _jitter(rng, Color(light[under_name]), .01, .04)
		look.under_fabric = _mat("knit" if under == "sweater" else ("linen" if rng.randf() < .3 else "cotton"))
		var up := "plain"
		var r := rng.randf()
		if under in ["shirt", "blouse"] and r < .22: up = "pinstripe"
		elif under in ["shirt", "blouse"] and r < .34: up = "checks"
		elif under == "tshirt" and r < .3: up = "stripes"
		elif under == "sweater": up = "rib"
		look.under_pattern = _pattern(up)
		look.under_color2 = Color(look.under_color).darkened(.45) if up != "plain" else look.under_color
		if top == "overalls": look.top_color_name = color_name
	# sleeves and neckline
	var sleeves := "long"
	var sr := rng.randf()
	match top:
		"shirt", "blouse": sleeves = "rolled" if sr < .4 else ("short" if sr < .55 else "long")
		"tshirt": sleeves = "short"
		"dress": sleeves = "short" if sr < .55 else ("long" if sr < .85 else "rolled")
		"tunic": sleeves = "long" if sr < .5 else "rolled"
		"vest", "overalls": sleeves = "rolled" if sr < .55 else ("short" if sr < .7 else "long")
	if occ.has("sleeves") and rng.randf() < .7 and not top in ["jacket", "coat", "sweater"]: sleeves = occ.sleeves
	if style == &"valdoro" and sleeves == "short": sleeves = "long"
	look.sleeves = sleeves
	var neck := "crew"
	match top:
		"shirt": neck = "open" if rng.randf() < .6 else "collar"
		"blouse": neck = ["scoop", "v", "collar", "open"][rng.randi() % 4]
		"sweater": neck = "turtle" if rng.randf() < (.35 if style in [&"valdoro", &"isola"] else .12) else "crew"
		"dress": neck = ["scoop", "v", "crew", "collar"][rng.randi() % 4]
		"tunic", "robe": neck = "v" if rng.randf() < .6 else "crew"
		"tshirt": neck = "crew"
		"vest", "jacket", "coat", "overalls":
			match String(look.under):
				"shirt", "blouse": neck = "open" if rng.randf() < .55 else "collar"
				"sweater": neck = "crew"
				"tshirt": neck = "crew"
	look.neck = neck
	# bottoms
	var bottom := "trousers"
	if top in ["dress", "robe"]: bottom = "none"
	elif female and top in ["blouse", "sweater", "shirt", "tshirt", "vest", "jacket", "coat"]:
		bottom = "skirt" if rng.randf() < (.6 if not style in [&"campo"] else .45) else "trousers"
	elif top == "overalls": bottom = "trousers"
	elif not female and style in [&"isola", &"island"] and top in ["tshirt", "shirt"] and rng.randf() < .12 and not elder:
		bottom = "shorts"
	look.bottom = bottom
	var bottoms: Dictionary = st.bottoms
	var bname := _palette_pick(rng, bottoms)
	var bcol := _jitter(rng, Color(bottoms[bname]), .01, .05)
	if top == "overalls": bcol = top_color
	# a skirt may take a palette colour instead
	if bottom == "skirt" and rng.randf() < .5:
		bcol = _jitter(rng, Color(palette[_palette_pick(rng, palette)]), .01, .05)
	var tries := 0
	while top != "overalls" and absf(bcol.get_luminance() - top_color.get_luminance()) < .06 and absf(bcol.h - top_color.h) < .06 and tries < 6:
		bcol = _jitter(rng, Color(bottoms[_palette_pick(rng, bottoms)]), .01, .05); tries += 1
	look.bottom_color = bcol
	var bfabric := "cotton"
	if bname == "denim" or top == "overalls": bfabric = "denim" if top != "overalls" else fabric_name
	elif bname == "leather": bfabric = "leather"
	elif style == &"valdoro" or (top in ["jacket", "coat"] and rng.randf() < .5): bfabric = "wool"
	elif rng.randf() < .35: bfabric = "linen"
	look.bottom_fabric = _mat(bfabric)
	var bpat := "plain"
	if bottom == "skirt":
		var pr := rng.randf()
		bpat = "checks" if pr < .15 else ("plaid" if pr < .25 else ("stripes" if pr < .3 else "plain"))
	elif bfabric == "wool" and rng.randf() < .2: bpat = "herringbone"
	elif rng.randf() < .08 and not female: bpat = "pinstripe"
	look.bottom_pattern = _pattern(bpat)
	look.bottom_color2 = bcol.darkened(.4) if bpat != "plain" else bcol
	# hems
	var hem := .5
	if top == "robe": hem = rng.randf_range(.07, .12)
	elif top == "dress": hem = rng.randf_range(.12, .22) if (elder or style == &"sarmada" or rng.randf() < .3) else rng.randf_range(.36, .5)
	elif bottom == "skirt": hem = rng.randf_range(.14, .24) if (elder or rng.randf() < .35) else rng.randf_range(.34, .46)
	elif top == "tunic": hem = rng.randf_range(.45, .62) if rng.randf() < .6 else .9
	elif top == "coat": hem = rng.randf_range(.44, .56)
	look.hem = hem
	# feet
	var shoes: String = occ.get("shoes", _pick(rng, st.shoes))
	if occ.has("shoes") and rng.randf() < .2: shoes = _pick(rng, st.shoes)
	look.shoes = shoes
	var leathers := ["3a2a1e", "5a3b24", "7a5334", "1f1b19", "8a6a48", "6b3a26"]
	look.shoe_color = _jitter(rng, Color(leathers[rng.randi() % leathers.size()]), .01, .06)
	look.tucked = shoes == "boots" and rng.randf() < .45 and bottom == "trousers"
	look.socks = bottom in ["shorts", "skirt"] and rng.randf() < (.6 if style == &"valdoro" else .2)
	look.sock_color = Color(["e8e2d4", "3a3a3a", "8a2f2f", "4d5e3a", "d9d2c0"][rng.randi() % 5])
	# belt
	look.belt = bottom in ["trousers", "shorts"] and rng.randf() < .65
	look.belt_color = Color(leathers[rng.randi() % leathers.size()]).darkened(.1)
	# apron
	look.apron = ""
	look.apron_color = Color("efe9da")
	if occ.has("apron"):
		var spec: Array = occ.apron
		if rng.randf() < float(spec[1]):
			look.apron = spec[0]
			var cols: Array = spec[2]
			look.apron_color = _jitter(rng, Color(cols[rng.randi() % cols.size()]), .01, .03)
	if top in ["robe", "coat"] and look.apron == "bib": look.apron = "waist"
	# head
	var hats: Dictionary = occ.get("hats", st["hats_f" if female else "hats_m"])
	var hat: String = _pick(rng, hats)
	if female and hat == "flat_cap" and rng.randf() < .7: hat = ""
	if not female and hat in ["sunhat", "kerchief"]: hat = ""
	if look.hair == "headscarf" or (look.hair == "afro" and hat != "headwrap"): hat = ""
	if hat == "kerchief":
		look.hair = "headscarf"; hat = ""
	if hat == "baker" and female and rng.randf() < .5:
		hat = ""; look.hair = "headscarf"
	look.hat = hat
	var hat_cols := {"straw": ["d8c48e", "cdb477", "e2d3a4"], "sunhat": ["e6d6a8", "efe6d0", "d9c7a0"], "flat_cap": ["4a4a48", "5b4a38", "3d4a5c", "6b6a5c", "7a6a52"],
		"felt": ["3f4a33", "4a3a2c", "2f2f2f", "5a4a3a"], "knit": ["263a57", "8a2f2f", "e8dfc8", "4d5e3a", "c9962b", "3a3a3a"],
		"beret": ["22324d", "2f2f2f", "7a2e35", "4d5e3a"], "baker": ["f8f6f0"], "headwrap": ["f1ece0", "2b3a6b", "c8923a", "b25a37", "d8c29a", "1f4f7a"], "": ["000000"]}
	var hc_list: Array = hat_cols.get(hat, ["000000"])
	look.hat_color = _jitter(rng, Color(hc_list[rng.randi() % hc_list.size()]), .01, .04)
	look.hat_color2 = Color(["7a2e35", "22324d", "2f2f2f", "c8923a", "4d5e3a", "a8463a"][rng.randi() % 6])
	look.hat_fabric = _mat({"straw": "straw", "sunhat": "straw", "felt": "wool", "knit": "knit", "flat_cap": "wool", "beret": "wool", "baker": "linen", "headwrap": "cotton"}.get(hat, "cotton"))
	look.hat_pattern = _pattern("weave" if hat in ["straw", "sunhat"] else ("rib" if hat == "knit" else ("herringbone" if hat == "flat_cap" and rng.randf() < .5 else "plain")))
	look.pompom = hat == "knit" and rng.randf() < .3
	var scarf_cols := ["b04a3a", "c8923a", "2b3a6b", "4f7f8c", "e8b4b8", "a83a32", "6f6b3a", "efe6d2", "7a2e35"]
	look.scarf_head_color = _jitter(rng, Color(scarf_cols[rng.randi() % scarf_cols.size()]), .01, .05)
	look.scarf_head_pattern = _pattern(["plain", "dots", "checks", "plain", "bands"][rng.randi() % 5])
	# accessories
	look.glasses = rng.randf() < float(occ.get("glasses", .14 + (.25 if elder else 0.0)))
	look.glasses_metal = rng.randf() < .4
	look.glasses_color = Color("b59b62") if look.glasses_metal else Color(["2a211c", "4a3322", "1c1c1e"][rng.randi() % 3])
	look.scarf = rng.randf() < (.3 if style in [&"puerto", &"sarmada", &"campo"] else .12) and not look.neck in ["turtle"] and top != "robe"
	look.scarf_color = _jitter(rng, Color(scarf_cols[rng.randi() % scarf_cols.size()]), .01, .05)
	look.scarf_pattern = _pattern(["plain", "dots", "checks", "plain"][rng.randi() % 4])
	look.satchel = rng.randf() < float(occ.get("satchel", .06))
	look.satchel_color = Color(leathers[rng.randi() % leathers.size()])


static func _mat(fabric: String) -> int:
	return {"cotton": CharacterMesh.Mat.COTTON, "linen": CharacterMesh.Mat.LINEN, "wool": CharacterMesh.Mat.WOOL,
		"knit": CharacterMesh.Mat.KNIT, "denim": CharacterMesh.Mat.DENIM, "leather": CharacterMesh.Mat.LEATHER,
		"straw": CharacterMesh.Mat.STRAW}.get(fabric, CharacterMesh.Mat.COTTON)


static func _pattern(pattern: String) -> int:
	return {"plain": 0, "stripes": 1, "pinstripe": 2, "checks": 3, "plaid": 4, "rib": 5, "cable": 6, "weave": 7,
		"dots": 8, "herringbone": 9, "bands": 10}.get(pattern, 0)


static func _second_color(rng: RandomNumberGenerator, base: Color, pattern: String, palette: Dictionary) -> Color:
	match pattern:
		"stripes":
			# Breton: dark on light or light on dark
			return Color("22324d") if base.get_luminance() > .5 and rng.randf() < .7 else (Color("f2ede0") if base.get_luminance() < .4 else base.darkened(.45))
		"checks", "plaid":
			var other := Color(palette[_palette_pick(rng, palette)])
			return other if absf(other.get_luminance() - base.get_luminance()) > .12 else base.darkened(.45)
		"dots": return Color("f6f2e8") if base.get_luminance() < .6 else base.darkened(.5)
		"pinstripe": return base.lightened(.45) if base.get_luminance() < .4 else base.darkened(.4)
		"bands": return Color(palette[_palette_pick(rng, palette)]).darkened(.1)
	return base
