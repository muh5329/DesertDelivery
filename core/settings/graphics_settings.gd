class_name GraphicsSettings
extends RefCounted
## Quality presets for the Forward+ renderer (m-16): Low / Medium / High / Ultra, applied at boot
## and from the graphics menu (F10), saved in user://graphics.cfg. `--quality=<name>` on the
## command line overrides the saved choice for one run (renders, benchmarks).
##
## What a preset sets: the post stack (SSAO, SSIL, volumetric fog: quality and on/off), the sun's
## shadow cascades and atlas, anti-aliasing (FXAA / TAA / MSAA, and FSR 2 upscaling on a Retina
## screen at High), mesh LOD bias, anisotropic filtering, and the night-light budget (how many
## lamps cast real light near the camera, and whether the courier's headlight casts shadows).
## The Compatibility renderer and headless runs only take the light budget.
##
## The default is High: tuned for an M4 Pro at a Retina window (FSR 2 renders ~0.77 of the 2x
## backbuffer, TAA-quality edges, every effect on at medium quality).

const PATH := "user://graphics.cfg"
const NAMES := ["Low", "Medium", "High", "Ultra"]
const LOW := 0
const MEDIUM := 1
const HIGH := 2
const ULTRA := 3
const DEFAULT := HIGH

const PRESETS := [
	{"ssao": false, "ssao_q": 0, "ssil": false, "ssil_q": 0, "vol_fog": false, "vol_size": 64, "vol_depth": 32,
		"cascades": 2, "shadow_dist": 260.0, "atlas": 2048, "soft": 1, "aa": "fxaa", "msaa": 0, "scale": 0.77,
		"lod": 2.0, "aniso": 2, "lights": 4, "spot_shadows": false, "glow": true},
	{"ssao": true, "ssao_q": 0, "ssil": false, "ssil_q": 0, "vol_fog": true, "vol_size": 64, "vol_depth": 48,
		"cascades": 4, "shadow_dist": 400.0, "atlas": 4096, "soft": 2, "aa": "taa", "msaa": 0, "scale": 1.0,
		"lod": 1.5, "aniso": 4, "lights": 8, "spot_shadows": false, "glow": true},
	{"ssao": true, "ssao_q": 1, "ssil": true, "ssil_q": 0, "vol_fog": true, "vol_size": 96, "vol_depth": 64,
		"cascades": 4, "shadow_dist": 520.0, "atlas": 4096, "soft": 3, "aa": "taa_or_fsr", "msaa": 0, "scale": 0.77,
		"lod": 1.0, "aniso": 8, "lights": 12, "spot_shadows": true, "glow": true},
	{"ssao": true, "ssao_q": 2, "ssil": true, "ssil_q": 1, "vol_fog": true, "vol_size": 128, "vol_depth": 96,
		"cascades": 4, "shadow_dist": 640.0, "atlas": 8192, "soft": 4, "aa": "taa", "msaa": 2, "scale": 1.0,
		"lod": 0.6, "aniso": 16, "lights": 20, "spot_shadows": true, "glow": true},
]

static var level := DEFAULT
static var _loaded := false


static func load_saved() -> int:
	if _loaded: return level
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK: level = clampi(int(cfg.get_value("graphics", "preset", DEFAULT)), LOW, ULTRA)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--quality="):
			var want := a.substr(10).to_lower()
			for i in range(NAMES.size()):
				if NAMES[i].to_lower() == want: level = i
	return level


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "preset", level)
	cfg.save(PATH)


## Apply `lvl` (or the saved preset) to the running world.
static func apply(world: WorldManager, lvl := -1) -> void:
	if lvl < 0: lvl = load_saved()
	level = clampi(lvl, LOW, ULTRA)
	var P: Dictionary = PRESETS[level]
	# the night lights exist in every renderer
	VehicleLights.spot_shadows = P.spot_shadows
	if world and world.day_night and world.day_night.lights:
		world.day_night.lights.set_budget(P.lights)
	if DisplayServer.get_name() == "headless" or not WorldKit.forward_plus(): return
	var env: Environment = null
	var sun: DirectionalLight3D = null
	if world:
		for c in world.environment.get_children():
			if c is WorldEnvironment: env = (c as WorldEnvironment).environment
			elif c is DirectionalLight3D and sun == null: sun = c
	if env:
		env.ssao_enabled = P.ssao
		env.ssil_enabled = P.ssil
		env.volumetric_fog_enabled = P.vol_fog
		env.glow_enabled = P.glow
		# half-size SSAO / SSIL below Ultra (the blur hides it; 4x fewer samples)
		RenderingServer.environment_set_ssao_quality([RenderingServer.ENV_SSAO_QUALITY_LOW, RenderingServer.ENV_SSAO_QUALITY_MEDIUM, RenderingServer.ENV_SSAO_QUALITY_HIGH][P.ssao_q],
			level < ULTRA, 0.5, 2, 50.0, 300.0)
		RenderingServer.environment_set_ssil_quality([RenderingServer.ENV_SSIL_QUALITY_LOW, RenderingServer.ENV_SSIL_QUALITY_MEDIUM][P.ssil_q],
			true, 0.5, 4, 50.0, 300.0)
		RenderingServer.environment_set_volumetric_fog_volume_size(P.vol_size, P.vol_depth)
		RenderingServer.environment_set_volumetric_fog_filter_active(true)
	if sun:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if P.cascades == 4 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = P.shadow_dist
	RenderingServer.directional_shadow_atlas_set_size(P.atlas, true)
	var soft: int = [RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][P.soft]
	RenderingServer.directional_soft_shadow_filter_set_quality(soft)
	RenderingServer.positional_soft_shadow_filter_set_quality(soft)
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null: return
	var vp := tree.root
	_apply_aa(vp, P)
	vp.mesh_lod_threshold = P.lod
	if "anisotropic_filtering_level" in vp:
		vp.set("anisotropic_filtering_level", {2: 1, 4: 2, 8: 3, 16: 4}.get(int(P.aniso), 2))


static func _apply_aa(vp: Viewport, P: Dictionary) -> void:
	var aa: String = P.aa
	var retina := DisplayServer.screen_get_scale() > 1.5
	vp.msaa_3d = {0: Viewport.MSAA_DISABLED, 2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X}[int(P.msaa)]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == "fxaa" else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = aa == "taa" or (aa == "taa_or_fsr" and not retina)
	if aa == "taa_or_fsr" and retina:
		# FSR 2 is temporal AA and upscaling in one; on a 2x backbuffer 0.77 is still ~1.5x the
		# window's point size
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		vp.scaling_3d_scale = P.scale
		vp.fsr_sharpness = 0.35
	elif aa == "fxaa" and P.scale < 1.0:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		vp.scaling_3d_scale = P.scale
		vp.fsr_sharpness = 0.4
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = 1.0
	# TAA softens: a little mip bias back toward sharp textures
	vp.texture_mipmap_bias = -0.25 if vp.use_taa else 0.0


static func describe(lvl: int) -> String:
	var P: Dictionary = PRESETS[clampi(lvl, LOW, ULTRA)]
	var fx := []
	if P.ssao: fx.append("SSAO")
	if P.ssil: fx.append("SSIL")
	if P.vol_fog: fx.append("volumetric fog")
	var aa: String = {"fxaa": "FXAA", "taa": "TAA", "taa_or_fsr": "FSR 2 on Retina, else TAA"}[P.aa]
	if P.msaa > 0: aa += " + MSAA %dx" % P.msaa
	return "%s · %d shadow cascades to %d m · %s · %d lamp lights" % [", ".join(fx) if not fx.is_empty() else "no screen-space effects",
		P.cascades, int(P.shadow_dist), aa, P.lights]
