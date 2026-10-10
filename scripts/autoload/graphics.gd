extends Node
## Graphics quality presets. Godot 4 has no hardware ray tracing, so Ultra
## stacks SDFGI, SSR, SSAO, SSIL and volumetric fog at their highest settings.

enum Preset { ULTRA, HIGH, MEDIUM, LOW }

const NAMES := ["Q_ULTRA", "Q_HIGH", "Q_MEDIUM", "Q_LOW"]

const PRESETS := {
	Preset.ULTRA: {
		"sdfgi": true, "sdfgi_rays": RenderingServer.ENV_SDFGI_RAY_COUNT_128,
		"ssr": true, "ssr_steps": 128, "ssr_quality": RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_HIGH,
		"ssao": true, "ssao_quality": RenderingServer.ENV_SSAO_QUALITY_ULTRA,
		"ssil": true, "ssil_quality": RenderingServer.ENV_SSIL_QUALITY_ULTRA,
		"fog": true, "fog_size": 160, "fog_depth": 128,
		"shadow_dir": 8192, "shadow_pos": 8192,
		"shadow_filter": RenderingServer.SHADOW_QUALITY_SOFT_ULTRA,
		"scale": 0.77, "fsr": true, "taa": true, "msaa": Viewport.MSAA_DISABLED,
		"glow": true, "aniso": Viewport.ANISOTROPY_16X,
	},
	Preset.HIGH: {
		"sdfgi": true, "sdfgi_rays": RenderingServer.ENV_SDFGI_RAY_COUNT_64,
		"ssr": true, "ssr_steps": 64, "ssr_quality": RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_MEDIUM,
		"ssao": true, "ssao_quality": RenderingServer.ENV_SSAO_QUALITY_HIGH,
		"ssil": true, "ssil_quality": RenderingServer.ENV_SSIL_QUALITY_MEDIUM,
		"fog": true, "fog_size": 96, "fog_depth": 64,
		"shadow_dir": 4096, "shadow_pos": 4096,
		"shadow_filter": RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
		"scale": 0.67, "fsr": true, "taa": true, "msaa": Viewport.MSAA_DISABLED,
		"glow": true, "aniso": Viewport.ANISOTROPY_8X,
	},
	Preset.MEDIUM: {
		"sdfgi": false, "sdfgi_rays": RenderingServer.ENV_SDFGI_RAY_COUNT_32,
		"ssr": true, "ssr_steps": 32, "ssr_quality": RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_LOW,
		"ssao": true, "ssao_quality": RenderingServer.ENV_SSAO_QUALITY_MEDIUM,
		"ssil": false, "ssil_quality": RenderingServer.ENV_SSIL_QUALITY_LOW,
		"fog": true, "fog_size": 64, "fog_depth": 48,
		"shadow_dir": 4096, "shadow_pos": 2048,
		"shadow_filter": RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
		"scale": 0.59, "fsr": true, "taa": true, "msaa": Viewport.MSAA_DISABLED,
		"glow": true, "aniso": Viewport.ANISOTROPY_4X,
	},
	Preset.LOW: {
		"sdfgi": false, "sdfgi_rays": RenderingServer.ENV_SDFGI_RAY_COUNT_16,
		"ssr": false, "ssr_steps": 16, "ssr_quality": RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_DISABLED,
		"ssao": false, "ssao_quality": RenderingServer.ENV_SSAO_QUALITY_LOW,
		"ssil": false, "ssil_quality": RenderingServer.ENV_SSIL_QUALITY_VERY_LOW,
		"fog": false, "fog_size": 32, "fog_depth": 32,
		"shadow_dir": 2048, "shadow_pos": 1024,
		"shadow_filter": RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		"scale": 1.0, "fsr": false, "taa": false, "msaa": Viewport.MSAA_2X,
		"glow": false, "aniso": Viewport.ANISOTROPY_2X,
	},
}

## Applies the saved preset to the viewport and, if given, a level's Environment.
func apply(viewport: Viewport, env: Environment = null) -> void:
	var p: Dictionary = PRESETS[Settings.graphics_preset]

	viewport.use_taa = p.taa
	viewport.msaa_3d = p.msaa
	viewport.anisotropic_filtering_level = p.aniso
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if p.fsr else Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = p.scale
	viewport.positional_shadow_atlas_size = p.shadow_pos

	RenderingServer.directional_shadow_atlas_set_size(p.shadow_dir, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(p.shadow_filter)
	RenderingServer.positional_soft_shadow_filter_set_quality(p.shadow_filter)
	RenderingServer.environment_set_ssao_quality(p.ssao_quality, false, 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_ssil_quality(p.ssil_quality, false, 0.5, 4, 50.0, 300.0)
	RenderingServer.environment_set_ssr_roughness_quality(p.ssr_quality)
	RenderingServer.environment_set_sdfgi_ray_count(p.sdfgi_rays)
	RenderingServer.environment_set_volumetric_fog_volume_size(p.fog_size, p.fog_depth)

	if env == null:
		return
	env.sdfgi_enabled = p.sdfgi
	env.ssr_enabled = p.ssr
	env.ssr_max_steps = p.ssr_steps
	env.ssao_enabled = p.ssao
	env.ssil_enabled = p.ssil
	env.volumetric_fog_enabled = p.fog
	env.glow_enabled = p.glow
