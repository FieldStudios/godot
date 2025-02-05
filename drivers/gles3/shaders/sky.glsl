/* clang-format off */
#[modes]

mode_background =
mode_half_res = #define USE_HALF_RES_PASS
mode_quarter_res = #define USE_QUARTER_RES_PASS
mode_cubemap = #define USE_CUBEMAP_PASS
mode_cubemap_half_res = #define USE_CUBEMAP_PASS \n#define USE_HALF_RES_PASS
mode_cubemap_quarter_res = #define USE_CUBEMAP_PASS \n#define USE_QUARTER_RES_PASS

#[specializations]

#[vertex]

out vec2 uv_interp;
/* clang-format on */

void main() {
	// One big triangle to cover the whole screen
	vec2 base_arr[3] = vec2[](vec2(-1.0, -1.0), vec2(3.0, -1.0), vec2(-1.0, 3.0));
	uv_interp = base_arr[gl_VertexID];
	gl_Position = vec4(uv_interp, 1.0, 1.0);
}

/* clang-format off */
#[fragment]

#define M_PI 3.14159265359

#include "tonemap_inc.glsl"

in vec2 uv_interp;

/* clang-format on */

uniform samplerCube radiance; //texunit:-1
#ifdef USE_CUBEMAP_PASS
uniform samplerCube half_res; //texunit:-2
uniform samplerCube quarter_res; //texunit:-3
#else
uniform sampler2D half_res; //texunit:-2
uniform sampler2D quarter_res; //texunit:-3
#endif

layout(std140) uniform GlobalVariableData { //ubo:1
	vec4 global_variables[MAX_GLOBAL_VARIABLES];
};

layout(std140) uniform SceneData { //ubo:2
	float pad1;
	float pad2;
};

struct DirectionalLightData {
	vec4 direction_energy;
	vec4 color_size;
	bool enabled;
};

layout(std140) uniform DirectionalLights { //ubo:3
	DirectionalLightData data[MAX_DIRECTIONAL_LIGHT_DATA_STRUCTS];
}
directional_lights;

/* clang-format off */

#ifdef MATERIAL_UNIFORMS_USED
layout(std140) uniform MaterialUniforms{ //ubo:4

#MATERIAL_UNIFORMS

};
#endif
/* clang-format on */
#GLOBALS

#ifdef USE_CUBEMAP_PASS
#define AT_CUBEMAP_PASS true
#else
#define AT_CUBEMAP_PASS false
#endif

#ifdef USE_HALF_RES_PASS
#define AT_HALF_RES_PASS true
#else
#define AT_HALF_RES_PASS false
#endif

#ifdef USE_QUARTER_RES_PASS
#define AT_QUARTER_RES_PASS true
#else
#define AT_QUARTER_RES_PASS false
#endif

// mat4 is a waste of space, but we don't have an easy way to set a mat3 uniform for now
uniform mat4 orientation;
uniform vec4 projection;
uniform vec3 position;
uniform float time;

layout(location = 0) out vec4 frag_color;

void main() {
	vec3 cube_normal;
	cube_normal.z = -1.0;
	cube_normal.x = (uv_interp.x + projection.x) / projection.y;
	cube_normal.y = (-uv_interp.y - projection.z) / projection.w;
	cube_normal = mat3(orientation) * cube_normal;
	cube_normal.z = -cube_normal.z;
	cube_normal = normalize(cube_normal);

	vec2 uv = gl_FragCoord.xy; // uv_interp * 0.5 + 0.5;

	vec2 panorama_coords = vec2(atan(cube_normal.x, cube_normal.z), acos(cube_normal.y));

	if (panorama_coords.x < 0.0) {
		panorama_coords.x += M_PI * 2.0;
	}

	panorama_coords /= vec2(M_PI * 2.0, M_PI);

	vec3 color = vec3(0.0, 0.0, 0.0);
	float alpha = 1.0; // Only available to subpasses
	vec4 half_res_color = vec4(1.0);
	vec4 quarter_res_color = vec4(1.0);
	vec4 custom_fog = vec4(0.0);

#ifdef USE_CUBEMAP_PASS
	vec3 inverted_cube_normal = cube_normal;
	inverted_cube_normal.z *= -1.0;
#ifdef USES_HALF_RES_COLOR
	half_res_color = texture(samplerCube(half_res, material_samplers[SAMPLER_LINEAR_WITH_MIPMAPS_CLAMP]), inverted_cube_normal);
#endif
#ifdef USES_QUARTER_RES_COLOR
	quarter_res_color = texture(samplerCube(quarter_res, material_samplers[SAMPLER_LINEAR_WITH_MIPMAPS_CLAMP]), inverted_cube_normal);
#endif
#else
#ifdef USES_HALF_RES_COLOR
	half_res_color = textureLod(sampler2D(half_res, material_samplers[SAMPLER_LINEAR_CLAMP]), uv, 0.0);
#endif
#ifdef USES_QUARTER_RES_COLOR
	quarter_res_color = textureLod(sampler2D(quarter_res, material_samplers[SAMPLER_LINEAR_CLAMP]), uv, 0.0);
#endif
#endif

	{

#CODE : SKY

	}

	// Tonemap before writing as we are writing to an sRGB framebuffer
	color *= exposure;
	color = apply_tonemapping(color, white);
	color = linear_to_srgb(color);

#ifdef USE_BCS
	color = apply_bcs(color, bcs);
#endif

#ifdef USE_COLOR_CORRECTION
	color = apply_color_correction(color, color_correction);
#endif

	frag_color.rgb = color;
	frag_color.a = alpha;
}
