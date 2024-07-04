//
// Volumetric Clouds Experiment
//
//                 _                                  
//               (`  ).                   _           
//              (     ).              .:(`  )`.       
// )           _(       '`.          :(   .    )      
//         .=(`(      .   )     .--  `.  (    ) )      
//        ((    (..__.:'-'   .+(   )   ` _`  ) )                 
// `.     `(       ) )       (   .  )     (   )  ._   
//   )      ` __.:'   )     (   (   ))     `-'.-(`  ) 
// )  )  ( )       --'       `- __.'         :(      )) 
// .-'  (_.'          .')                    `(    )  ))
//                   (_  )                     ` __.:'          
//                                         
// --..,___.--,--'`,---..-.--+--.,,-,,..._.--..-._.-a:f--.
//
// A mashup of ideas from different sources:
// * Magnus Wrenninge - Production Volume Rendering 
//	 http://magnuswrenninge.com/productionvolumerendering
// * Andrew Schneider - The Real-time Volumetric Cloudscapes of Horizon: Zero Dawn
//   http://advances.realtimerendering.com/s2015/The%20Real-time%20Volumetric%20Cloudscapes%20of%20Horizon%20-%20Zero%20Dawn%20-%20ARTR.pdf
// * Scratchapixel - Simulating the Colors of the Sky
//   https://www.scratchapixel.com/lessons/procedural-generation-virtual-worlds/simulating-sky
// * Ian McEwan, Ashima Arts - Array and textureless GLSL 2D/3D/4D simplex 
//   https://github.com/ashima/webgl-noise
// * and of course lots of iteration and tweaking
//   https://github.com/valentingalea/shaderbox
//	
#define SHADERTOY

#ifdef __cplusplus
#define _in(T) const T &
#define _inout(T) T &
#define _out(T) T &
#define _begin(type) type {
#define _end }
#define _mutable(T) T
#define _constant(T) const T
#define mul(a, b) (a) * (b)
#endif

#if defined(GL_ES) || defined(GL_SHADING_LANGUAGE_VERSION)
#define _in(T) const in T
#define _inout(T) inout T
#define _out(T) out T
#define _begin(type) type (
#define _end )
#define _mutable(T) T
#define _constant(T) const T
#define mul(a, b) (a) * (b)
precision mediump float;
#endif

#ifdef HLSL
#define _in(T) const in T
#define _inout(T) inout T
#define _out(T) out T
#define _begin(type) {
#define _end }
#define _mutable(T) static T
#define _constant(T) static const T
#define vec2 float2
#define vec3 float3
#define vec4 float4
#define mat2 float2x2
#define mat3 float3x3
#define mat4 float4x4
#define mix lerp
#define fract frac
#define mod fmod
#pragma pack_matrix(row_major)
#endif

#ifdef HLSLTOY
cbuffer uniforms : register(b0) {
	float2 u_res;
	float u_time;
	float2 u_mouse;
};
void mainImage(_out(float4) fragColor, _in(float2) fragCoord);
float4 main(float4 uv : SV_Position) : SV_Target{ float4 col; mainImage(col, uv.xy); return col; }
#endif

#if defined(__cplusplus) || defined(SHADERTOY)
#define u_res iResolution
#define u_time iTime
#define u_mouse iMouse
#endif

#ifdef GLSLSANDBOX
uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;
#define u_res resolution
#define u_time time
#define u_mouse mouse
void mainImage(_out(vec4) fragColor, _in(vec2) fragCoord);
void main() { mainImage(gl_FragColor, gl_FragCoord.xy); }
#endif

#ifdef UE4
_constant(vec2) u_res = vec2(0, 0);
_constant(vec2) u_mouse = vec2(0, 0);
_mutable(float) u_time = 0;
#endif

#define PI 3.14159265359

struct ray_t {
	vec3 origin;
	vec3 direction;
};
#define BIAS 1e-4 // small offset to avoid self-intersections

struct sphere_t {
	vec3 origin;
	float radius;
	int material;
};

struct plane_t {
	vec3 direction;
	float distance;
	int material;
};

struct hit_t {
	float t;
	int material_id;
	vec3 normal;
	vec3 origin;
};
#define max_dist 1e8
_constant(hit_t) no_hit = _begin(hit_t)
	float(max_dist + 1e1), // 'infinite' distance
	-1, // material id
	vec3(0., 0., 0.), // normal
	vec3(0., 0., 0.) // origin
_end;

// ----------------------------------------------------------------------------
// Various 3D utilities functions
// ----------------------------------------------------------------------------

ray_t get_primary_ray(
	_in(vec3) cam_local_point,
	_inout(vec3) cam_origin,
	_inout(vec3) cam_look_at
){
	vec3 fwd = normalize(cam_look_at - cam_origin);
	vec3 up = vec3(0, 1, 0);
	vec3 right = cross(up, fwd);
	up = cross(fwd, right);

	ray_t r = _begin(ray_t)
		cam_origin,
		normalize(fwd + up * cam_local_point.y + right * cam_local_point.x)
	_end;
	return r;
}

_constant(mat3) mat3_ident = mat3(1, 0, 0, 0, 1, 0, 0, 0, 1);


mat2 rotate_2d(
	_in(float) angle_degrees
){
	float angle = radians(angle_degrees);
	float _sin = sin(angle);
	float _cos = cos(angle);
	return mat2(_cos, -_sin, _sin, _cos);
}

mat3 rotate_around_z(
	_in(float) angle_degrees
){
	float angle = radians(angle_degrees);
	float _sin = sin(angle);
	float _cos = cos(angle);
	return mat3(_cos, -_sin, 0, _sin, _cos, 0, 0, 0, 1);
}

mat3 rotate_around_y(
	_in(float) angle_degrees
){
	float angle = radians(angle_degrees);
	float _sin = sin(angle);
	float _cos = cos(angle);
	return mat3(_cos, 0, _sin, 0, 1, 0, -_sin, 0, _cos);
}

mat3 rotate_around_x(
	_in(float) angle_degrees
){
	float angle = radians(angle_degrees);
	float _sin = sin(angle);
	float _cos = cos(angle);
	return mat3(1, 0, 0, 0, _cos, -_sin, 0, _sin, _cos);
}

// http://http.developer.nvidia.com/GPUGems3/gpugems3_ch24.html
vec3 linear_to_srgb(
	_in(vec3) color
){
	const float p = 1. / 1.2;
	return vec3(pow(color.r, p), pow(color.g, p), pow(color.b, p));
}
vec3 srgb_to_linear(
	_in(vec3) color
){
	const float p = 2.2;
	return vec3(pow(color.r, p), pow(color.g, p), pow(color.b, p));
}

#ifdef __cplusplus
vec3 faceforward(
	_in(vec3) N,
	_in(vec3) I,
	_in(vec3) Nref
){
	return dot(Nref, I) < 0 ? N : -N;
}
#endif

float checkboard_pattern(
	_in(vec2) pos,
	_in(float) scale
){
	vec2 pattern = floor(pos * scale);
	return mod(pattern.x + pattern.y, 2.0);
}

float band (
	_in(float) start,
	_in(float) peak,
	_in(float) end,
	_in(float) t
){
	return
	smoothstep (start, peak, t) *
	(1. - smoothstep (peak, end, t));
}

// from https://www.shadertoy.com/view/4sSSW3
// original http://orbit.dtu.dk/fedora/objects/orbit:113874/datastreams/file_75b66578-222e-4c7d-abdf-f7e255100209/content
void fast_orthonormal_basis(
	_in(vec3) n,
	_out(vec3) f,
	_out(vec3) r
){
	float a = 1. / (1. + n.z);
	float b = -n.x*n.y*a;
	f = vec3(1. - n.x*n.x*a, b, -n.x);
	r = vec3(b, 1. - n.y*n.y*a, -n.y);
}

// ----------------------------------------------------------------------------
// Analytical surface-ray intersection routines
// ----------------------------------------------------------------------------

// geometrical solution
// info: http://www.scratchapixel.com/old/lessons/3d-basic-lessons/lesson-7-intersecting-simple-shapes/ray-sphere-intersection/
void intersect_sphere(
	_in(ray_t) ray,
	_in(sphere_t) sphere,
	_inout(hit_t) hit
){
	vec3 rc = sphere.origin - ray.origin;
	float radius2 = sphere.radius * sphere.radius;
	float tca = dot(rc, ray.direction);
	if (tca < 0.) return;

	float d2 = dot(rc, rc) - tca * tca;
	if (d2 > radius2) return;

	float thc = sqrt(radius2 - d2);
	float t0 = tca - thc;
	float t1 = tca + thc;

	if (t0 < 0.) t0 = t1;
	if (t0 > hit.t) return;

	vec3 impact = ray.origin + ray.direction * t0;

	hit.t = t0;
	hit.material_id = sphere.material;
	hit.origin = impact;
	hit.normal = (impact - sphere.origin) / sphere.radius;
}

// Plane is defined by normal N and distance to origin P0 (which is on the plane itself)
// a plane eq is: (P - P0) dot N = 0
// which means that any line on the plane is perpendicular to the plane normal
// a ray eq: P = O + t*D
// substitution and solving for t gives:
// t = ((P0 - O) dot N) / (N dot D)
void intersect_plane(
	_in(ray_t) ray,
	_in(plane_t) p,
	_inout(hit_t) hit
){
	float denom = dot(p.direction, ray.direction);
	if (denom < 1e-6) return;

	vec3 P0 = vec3(p.distance, p.distance, p.distance);
	float t = dot(P0 - ray.origin, p.direction) / denom;
	if (t < 0. || t > hit.t) return;
	
	hit.t = t;
	hit.material_id = p.material;
	hit.origin = ray.origin + ray.direction * t;
	hit.normal = faceforward(p.direction, ray.direction, p.direction);
}

// ----------------------------------------------------------------------------
// Volumetric utilities
// ----------------------------------------------------------------------------

float isotropic_phase_func(float mu)
{
	return
	           1.
	/ //-------------------
	        4. * PI;
}

float rayleigh_phase_func(float mu)
{
	return
	        3. * (1. + mu*mu)
	/ //------------------------
	           (16. * PI);
}

float henyey_greenstein_phase_func(float mu)
{
	// Henyey-Greenstein phase function factor [-1, 1]
	// represents the average cosine of the scattered directions
	// 0 is isotropic scattering
	// > 1 is forward scattering, < 1 is backwards
	const float g = 0.76;

	return
	                     (1. - g*g)
	/ //---------------------------------------------
	     ((4. + PI) * pow(1. + g*g - 2.*g*mu, 1.5));
}

float schlick_phase_func(float mu)
{
	// Schlick Phase Function factor
	// Pharr and  Humphreys [2004] equivalence to g from Henyey-Greenstein
	const float g = 0.76;
	const float k = 1.55*g - 0.55 * (g*g*g);

	return
	                  (1. - k*k)
	/ //-------------------------------------------
	     (4. * PI * (1. + k*mu) * (1. + k*mu));
}

struct volume_sampler_t {
	vec3 origin; // start of ray
	vec3 pos; // current pos of acccumulation ray
	float height;

	float coeff_absorb;
	float T; // transmitance

	vec3 C; // color
	float alpha;
};

volume_sampler_t begin_volume(
	_in(vec3) origin,
	_in(float) coeff_absorb
){
	volume_sampler_t v = _begin(volume_sampler_t)
		origin, origin, 0.,
		coeff_absorb, 1.,
		vec3(0., 0., 0.), 0.
	_end;
	return v;
}

float illuminate_volume(
	_inout(volume_sampler_t) vol,
	_in(vec3) V,
	_in(vec3) L
);

void integrate_volume(
	_inout(volume_sampler_t) vol,
	_in(vec3) V,
	_in(vec3) L,
	_in(float) density,
	_in(float) dt
){
	// change in transmittance (follows Beer-Lambert law)
	float T_i = exp(-vol.coeff_absorb * density * dt);
	// Update accumulated transmittance
	vol.T *= T_i;
	// integrate output radiance (here essentially color)
	vol.C += vol.T * illuminate_volume(vol, V, L) * density * dt;
	// accumulate opacity
	vol.alpha += (1. - T_i) * (1. - vol.alpha);
}

#define illumstrength (2.1+sin(u_time*2.3)*0.2)

#define cld_march_steps (75)
#define cld_coverage (0.23)
// #define cld_thick (122.0)
#define cld_thick (55.0)
float cld_absorb_coeff = (1.0*0.9);
#define cld_wind_dir vec3(0, 0, -u_time * .11)
#define cld_sun_dir normalize(vec3(0, 0.4/*abs(sin(u_time * .3))*/, -1))
_mutable(float) coverage_map;

// ----------------------------------------------------------------------------
// Noise function by iq from https://www.shadertoy.com/view/4sfGzS
// ----------------------------------------------------------------------------

float hash(
	_in(float) n
){
	return fract(sin(n)*753.5453123);
}

float noise_iq(
	_in(vec3) x
){
	vec3 p = floor(x);
	vec3 f = fract(x);
	f = f*f*(3.0 - 2.0*f);

#if 1
    float n = p.x + p.y*157.0 + 113.0*p.z;
    return mix(mix(mix( hash(n+  0.0), hash(n+  1.0),f.x),
                   mix( hash(n+157.0), hash(n+158.0),f.x),f.y),
               mix(mix( hash(n+113.0), hash(n+114.0),f.x),
                   mix( hash(n+270.0), hash(n+271.0),f.x),f.y),f.z);
#else
	vec2 uv = (p.xy + vec2(37.0, 17.0)*p.z) + f.xy;
	vec2 rg = textureLod( iChannel0, (uv+.5)/256., 0.).yx;
	return mix(rg.x, rg.y, f.z);
#endif
}

#define gnoise(x) noise_iq(x)

//
// Description : Array and textureless GLSL 2D/3D/4D simplex 
//               noise functions.
//      Author : Ian McEwan, Ashima Arts.
//  Maintainer : ijm
//     Lastmod : 20110822 (ijm)
//     License : Copyright (C) 2011 Ashima Arts. All rights reserved.
//               Distributed under the MIT License. See LICENSE file.
//               https://github.com/ashima/webgl-noise
// 

vec3 mod289(vec3 x) {
  return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec4 mod289(vec4 x) {
  return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec4 permute(vec4 x) {
     return mod289(((x*34.0)+1.0)*x);
}

vec4 taylorInvSqrt(vec4 r)
{
  return 1.79284291400159 - 0.85373472095314 * r;
}

float snoise(vec3 v)
  { 
  const vec2  C = vec2(1.0/6.0, 1.0/3.0) ;
  const vec4  D = vec4(0.0, 0.5, 1.0, 2.0);

// First corner
  vec3 i  = floor(v + dot(v, C.yyy) );
  vec3 x0 =   v - i + dot(i, C.xxx) ;

// Other corners
  vec3 g = step(x0.yzx, x0.xyz);
  vec3 l = 1.0 - g;
  vec3 i1 = min( g.xyz, l.zxy );
  vec3 i2 = max( g.xyz, l.zxy );

  //   x0 = x0 - 0.0 + 0.0 * C.xxx;
  //   x1 = x0 - i1  + 1.0 * C.xxx;
  //   x2 = x0 - i2  + 2.0 * C.xxx;
  //   x3 = x0 - 1.0 + 3.0 * C.xxx;
  vec3 x1 = x0 - i1 + C.xxx;
  vec3 x2 = x0 - i2 + C.yyy; // 2.0*C.x = 1/3 = C.y
  vec3 x3 = x0 - D.yyy;      // -1.0+3.0*C.x = -0.5 = -D.y

// Permutations
  i = mod289(i); 
  vec4 p = permute( permute( permute( 
             i.z + vec4(0.0, i1.z, i2.z, 1.0 ))
           + i.y + vec4(0.0, i1.y, i2.y, 1.0 )) 
           + i.x + vec4(0.0, i1.x, i2.x, 1.0 ));

// Gradients: 7x7 points over a square, mapped onto an octahedron.
// The ring size 17*17 = 289 is close to a multiple of 49 (49*6 = 294)
  float n_ = 0.142857142857; // 1.0/7.0
  vec3  ns = n_ * D.wyz - D.xzx;

  vec4 j = p - 49.0 * floor(p * ns.z * ns.z);  //  mod(p,7*7)

  vec4 x_ = floor(j * ns.z);
  vec4 y_ = floor(j - 7.0 * x_ );    // mod(j,N)

  vec4 x = x_ *ns.x + ns.yyyy;
  vec4 y = y_ *ns.x + ns.yyyy;
  vec4 h = 1.0 - abs(x) - abs(y);

  vec4 b0 = vec4( x.xy, y.xy );
  vec4 b1 = vec4( x.zw, y.zw );

  //vec4 s0 = vec4(lessThan(b0,0.0))*2.0 - 1.0;
  //vec4 s1 = vec4(lessThan(b1,0.0))*2.0 - 1.0;
  vec4 s0 = floor(b0)*2.0 + 1.0;
  vec4 s1 = floor(b1)*2.0 + 1.0;
  vec4 sh = -step(h, vec4(0, 0, 0, 0));

  vec4 a0 = b0.xzyw + s0.xzyw*sh.xxyy ;
  vec4 a1 = b1.xzyw + s1.xzyw*sh.zzww ;

  vec3 p0 = vec3(a0.xy,h.x);
  vec3 p1 = vec3(a0.zw,h.y);
  vec3 p2 = vec3(a1.xy,h.z);
  vec3 p3 = vec3(a1.zw,h.w);

//Normalise gradients
  vec4 norm = taylorInvSqrt(vec4(dot(p0,p0), dot(p1,p1), dot(p2, p2), dot(p3,p3)));
  p0 *= norm.x;
  p1 *= norm.y;
  p2 *= norm.z;
  p3 *= norm.w;

// Mix final noise value
  vec4 m = max(0.6 - vec4(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), 0.0);
  m = m * m;
  return 42.0 * dot( m*m, vec4( dot(p0,x0), dot(p1,x1), 
                                dot(p2,x2), dot(p3,x3) ) );
  }
#define noise(x) snoise(x)

// ----------------------------------------------------------------------------
// Fractional Brownian Motion
// depends on custom basis function
// ----------------------------------------------------------------------------

#define DECL_FBM_FUNC(_name, _octaves, _basis) float _name(_in(vec3) pos, _in(float) lacunarity, _in(float) init_gain, _in(float) gain) { vec3 p = pos; float H = init_gain; float t = 0.; for (int i = 0; i < _octaves; i++) { t += _basis * H; p *= lacunarity; H *= gain; } return t; }

DECL_FBM_FUNC(fbm, 4, noise(p))
DECL_FBM_FUNC(fbm_clouds, 5, abs(noise(p)))

vec3 render_sky_color(
	_in(vec3) eye_dir
){
	_constant(vec3) sun_color = vec3(4.8, 3.14, 3.15)*0.65;
	float sun_amount = max(dot(eye_dir, cld_sun_dir), 0.);

	vec3 sky = mix(vec3(.0, .1, .4), vec3(.3, .67, .8)*0.9, 1.0 - eye_dir.y);
	sky += sun_color * min(pow(sun_amount, 355.0) * 6.0, 1.0);
	sky += sun_color * min(pow(sun_amount, 8.0) * .2, 1.0);

	return sky;
}

float density_func(
	_in(vec3) pos,
	_in(float) h
){
	vec3 p = pos * .001 + cld_wind_dir;
	float dens = fbm_clouds(p * 2.032, 2.6434, .5, .5);
	
	dens *= smoothstep (cld_coverage, cld_coverage + .035, dens);

	//dens *= band(.2, .3, .5 + coverage_map * .5, h);

	return dens;
}

float color_func(
	_in(vec3) pos,
	_in(float) h
){
	vec3 p = pos * .001 + cld_wind_dir;
	float dens = fbm_clouds(p * 0.932, 2.6434, .5, .5);
	
	dens *= smoothstep (cld_coverage, cld_coverage + .035, dens);

	//dens *= band(.2, .3, .5 + coverage_map * .5, h);

	return dens;
}

float illuminate_volume(
	_inout(volume_sampler_t) cloud,
	_in(vec3) V,
	_in(vec3) L
){
	return exp(cloud.height) / illumstrength;
}

vec4 render_clouds(
	_in(ray_t) eye
){
	int steps = cld_march_steps;
	 float march_step = cld_thick / float(steps);
	 float colStep = 1.0 / float(steps);

	vec3 projection = eye.direction / eye.direction.y;
	vec3 iter = projection * march_step;

	float cutoff = dot(eye.direction, vec3(0, 0.7, 0));

	volume_sampler_t cloud = begin_volume(
		eye.origin + projection * 120.,
		cld_absorb_coeff);

	//coverage_map = gnoise(projection);
	//return vec4(coverage_map, coverage_map, coverage_map, 1);
	for (int i = 0; i < steps; i++) {
		cloud.height = (cloud.pos.y - cloud.origin.y) / cld_thick;
		float dens = density_func(cloud.pos, cloud.height);

		integrate_volume(
			cloud,
			eye.direction, cld_sun_dir,
			dens, march_step);

		cloud.pos += iter;
		if (cloud.alpha > .99) break;
	}

	vec3 p = (cloud.origin * 0.001 + cld_wind_dir)*1.0;
	// float dens1 = snoise(p)*1.7;
	// float dens2 = snoise(p)*1;
	float dens1 = fbm_clouds(p * 0.322, 2.2434, .55, .5);
	float dens2 = fbm_clouds(p * 0.2, 2.0, .5, .52);
	float dens3 = fbm_clouds(p * 0.2, 2.0, .52, .5);
	// float dens3 = snoise(p+2);
	float calpha = cloud.alpha * smoothstep(.0, .2, cutoff);
	// vec3 v3 = vec3(1.2+((sin(u_time*2.3+12.0)*0.5+0.5)*2.2+dens1));
	vec3 v3 = vec3(1.62);
	// v3.r *= dens1+0.5;
	v3.g *= dens2+0.2;
	v3.b *= dens3+0.1;
	// v3 = col;
	v3 = clamp(v3, vec3(0), vec3(1));
	// v3.g = calpha*dens3*(1.0/42.0);
	return vec4(pow(cloud.C*v3, vec3(1,0.9,0.8)), calpha*0.999);
}

void setup_camera(
	_inout(vec3) eye,
	_inout(vec3) look_at
){
	eye = vec3(0, 2.0+(sin(u_time*0.2)*0.1), 0);
	look_at = vec3(0.31+(sin((u_time+2020.0)*0.2)*0.3), 2.7, -1);
}

void setup_scene()
{
}

vec3 render(
	_in(ray_t) eye_ray,
	_in(vec3) point_cam
){
	vec3 sky = render_sky_color(eye_ray.direction);
    float dotR = max(0.0, dot(eye_ray.direction, vec3(0, 1, 0)));

	vec4 cld = render_clouds(eye_ray);
	//vec3 col = mix(sky, cld.rgb, cld.a);
	vec3 col1 = sky*(1.0-cld.a) + cld.rgb;
    
    vec3 col = mix(sky, cld.rgb, cld.a);
	col = mix(col, col1, 0.6);
	if (dotR < 0.05) return mix(sky, col, (dotR/0.05));

	return col;
}

#define FOV 0.8 // 45 degrees
// ----------------------------------------------------------------------------
// Main Rendering function
// depends on external defines: FOV
// ----------------------------------------------------------------------------

void mainImage(
	_out(vec4) fragColor,
#ifdef SHADERTOY
	vec2 fragCoord
#else
	_in(vec2) fragCoord
#endif
){
   // cld_coverage = (.39+(sin(u_time * 0.12)*0.065));
   // cld_thick = 66.0+(abs(sin((u_time+123123.0) * 0.13)*05.15));
    float clampF = 0.9;
    //cld_march_steps = 222 + int(floor(clamp(sin(u_time*0.8), -clampF, clampF)*(1.0/clampF)*212.0));
    //cld_march_steps = 70;
	// assuming screen width is larger than height 
	vec2 aspect_ratio = vec2(u_res.x / u_res.y, 1);

	vec3 color = vec3(0.1, 0, 0);

	vec3 eye, look_at;
	setup_camera(eye, look_at);

	setup_scene();

	vec2 point_ndc = fragCoord.xy / u_res.xy;
#ifdef HLSL
		point_ndc.y = 1. - point_ndc.y;
#endif
	vec3 point_cam = vec3(
		(2.0 * point_ndc - 1.0) * aspect_ratio * FOV,
		-1.0);

	ray_t ray = get_primary_ray(point_cam, eye, look_at);

	color += render(ray, point_cam);

	fragColor = vec4(linear_to_srgb(color), 1);
}
