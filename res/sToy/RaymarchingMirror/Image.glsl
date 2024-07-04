float smin(in float a, in float b, float k) {
    float h = max(k - abs(a-b), 0.0);
    
    return min(a,b) - h*h/(k*4.0);
}

float sdSphere(in vec3 pos, float rad) {
    return length(pos) - rad;
}

float sdMirror(vec3 pos) {
    float mirror = max(pos.x + 1.0, pos.y - 0.8);
    mirror = max(mirror, abs(pos.z + 0.7) - 0.8);
    mirror = max(mirror, -pos.x - 1.25);
    
    return mirror;
}

float sdFrame(vec3 pos) {
    float frame = max(pos.x + 1.001, pos.y - 0.9);
    frame = max(frame, abs(pos.z + 0.7) - 0.9);
    frame = max(frame, -pos.x - 1.2499);
    
    return frame;
}

float map(in vec3 pos, bool reflected, inout float material)
{
    float ground = pos.y + 0.25;
    float sphere = sdSphere(pos + vec3(-0.5, -0.2, 0.8), 0.25);
    float sphere2 = sdSphere(pos + vec3(-0.95, -0.2, 0.8 + sin(iTime)), 0.25);
    float mirror = sdMirror(pos);
    float frame = max(sdFrame(pos), -mirror);
      
    float res;
    
    res = ground;
    material = 0.0;
    
    float sphere_blend = smin(sphere, sphere2, 0.25);

    if (sphere_blend < res) {
        res = sphere_blend;
        material = 1.0;
        if (sphere2 < sphere)
            material = 2.0;
    }

    if (!reflected && frame < res) {
        res = frame;
        material = 3.0;
    }

    if (!reflected && mirror < res) {
        res = mirror;
        material = 4.0;
    }
        
    
    return res;
}

vec3 calcNormal(in vec3 pos)
{
    vec2 e = vec2(0.0001, 0.0);
    float mat = 0.0;
    
    return normalize(  vec3(map(pos+e.xyy, false, mat) - map(pos-e.xyy, false, mat),
                            map(pos+e.yxy, false, mat) - map(pos-e.yxy, false, mat),
                            map(pos+e.yyx, false, mat) - map(pos-e.yyx, false, mat)));
}

float castRay (inout vec3 ro, vec3 rd, inout bool reflected, inout float material) {
    float t = 0.0;
    int i=0;    
    for (; i<100; i++) {
        float map_res = map(ro, reflected, material);
        float h = map_res;
        ro += h*rd;
        
        if (h < 0.001) {
            if (material > 3.5) {
                if (!reflected) {
                    vec3 norm = calcNormal(ro - 0.001 * rd);
                    rd = rd - 2.0 * dot(rd,norm) * norm;

                    reflected = true;
                }
                t += h;
                continue;
            }
            
            break;
        }
        
        t += h;
        
        if (t > 20.0) {
            break;
        }
    }
    
    if (t > 20.0) t = -1.0;
    
    return t;
}

float castShadow (vec3 ro, vec3 rd) {
    float t = 0.0;
    vec3 pos = ro;
    bool reflected = false;
    float material = 0.0;
    for (int i=0; i<100; i++) {
        float map_res = map(pos, reflected, material);
        float h = map_res;
        pos += h*rd;

        
        if (h < 0.0001) {
            break;
        }
        
        t += h;
        
        if (t > 20.0) {
            break;
        }
    }
    
    if (t > 20.0) t = -1.0;
    
    return t;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec2 p = (2.0 * fragCoord - iResolution.xy) / iResolution.y;
    
    float an_x = 10.0*iMouse.x/iResolution.x + 1.0;//iTime;
    float an_y = 1.0*iMouse.y/iResolution.y;
    
    vec3 ta = vec3(0.0, 0.25, 0.0);
    vec3 ro = ta + vec3(1.5*sin(an_x), 1.5*sin(an_y), 1.5*cos(an_x));
    ro *= 1.5;
    
    vec3 ww = normalize(ta - ro);
    vec3 uu = normalize(cross(ww, vec3(0,1,0)));
    vec3 vv = normalize(cross(uu, ww));
    
    vec3 rd = normalize(vec3(p.x*uu + p.y*vv + 1.8*ww));
    
    vec3 col = vec3(0.4, 0.75, 1.0) - 0.7 * rd.y;
    col = mix(col, vec3(0.7,0.75,0.8), exp(-10.0*rd.y));
        
    bool reflected = false;
    
    float material = 0.0;
    float tp = castRay(ro, rd, reflected, material);
    float t = tp;
    vec3 pos = ro;
    
    if (t > 0.0) {
        vec3 nor = calcNormal(pos);
        
        float row = floor(mod(pos.x * 2.0, 2.0));
        float column = floor(mod(pos.z * 2.0, 2.0));
        
        vec3 mate = vec3(0.2);
        if (material < 0.5 && (row < 0.5 || column < 0.5) && !(row < 0.5 && column < 0.5)) mate = vec3(0.1);
        if (material < 1.5 && material > 0.5) mate = vec3(0.3, 0.2, 0.1);
        if (material < 2.5 && material > 1.5) mate = vec3(0.1, 0.2, 0.3);
        if (material < 3.5 && material > 2.5) mate = vec3(0.01);
        
        vec3 sun_dir = normalize(vec3(sin(iTime / 5.0), 0.4, cos(iTime / 5.0)));
        float sun_dif = clamp(dot(nor, sun_dir), 0.0, 1.0);
        float sun_sha = step(castShadow(pos+nor*0.001, sun_dir), -0.5);
        float sky_dif = clamp(0.5 + 0.5*dot(nor, vec3(0.0, 1.0, 0.0)), 0.0, 1.0);
        float bou_dif = clamp(0.5 + 0.5*dot(nor, vec3(0.0, -1.0, 0.0)), 0.0, 1.0);
        
        col = mate*vec3(7.0, 5.0, 3.0)*sun_dif*sun_sha;
        col += mate*vec3(0.5, 0.8, 0.9)*sky_dif;
        col += mate*vec3(0.7, 0.3, 0.2)*bou_dif;
    }
        
    col = pow(col, vec3(0.4545));
    if (reflected) {
        col *= 0.75;
    }
    
    
    fragColor = vec4(col, 1.0);
}