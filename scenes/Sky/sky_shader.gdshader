shader_type sky;
render_mode use_quarter_res_pass;

// Sky parameters
uniform vec3 day_top_color : source_color = vec3(0.3, 0.5, 0.95);
uniform vec3 day_bottom_color : source_color = vec3(0.6, 0.8, 1.0);
uniform vec3 sunset_top_color : source_color = vec3(0.26, 0.24, 0.38);
uniform vec3 sunset_bottom_color : source_color = vec3(0.95, 0.33, 0.15);
uniform vec3 night_top_color : source_color = vec3(0.02, 0.02, 0.05);
uniform vec3 night_bottom_color : source_color = vec3(0.05, 0.05, 0.1);


// Cloud parameters
uniform float cloud_edge_softness : hint_range(0.0, 1.0) = 0.3;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.5;
uniform float cloud_speed : hint_range(0.0, 1.0) = 0.01;
uniform vec2 cloud_movement_direction = vec2(1.0, 0.0);
uniform sampler2D cloud_noise_texture;

// Horizon parameters
uniform float horizon_blend : hint_range(0.0, 1.0) = 0.1;

// Sun parameters
uniform float sun_size : hint_range(0.001, 0.5) = 0.01;
uniform float sun_halo : hint_range(0.0, 1.0) = 0.2;

// Moon parameters
uniform float moon_size : hint_range(0.001, 0.5) = 0.02;
uniform float moon_halo : hint_range(0.0, 1.0) = 0.1;

// Time of day control
uniform float time_of_day : hint_range(0.0, 1.0) = 0.5; // 0.0 = midnight, 0.25 = sunrise, 0.5 = noon, 0.75 = sunset

// Advanced spherical UV mapping with less distortion
vec2 improved_spherical_uv(vec3 dir) {
    // Use atan2 for a more precise mapping
    float phi = atan(dir.z, dir.x);
    float theta = acos(clamp(dir.y, -1.0, 1.0));
    
    // Apply a non-linear transformation to reduce pole pinching
    float pole_correction = 1.0 - pow(abs(dir.y), 0.5);
    
    // Remap to [0,1] range with wrapping and pole correction
    vec2 uv = vec2(
        (phi / (2.0 * 3.14159265) + 0.5),
        theta / 3.14159265 * pole_correction
    );
    
    return uv;
}

// Seamless noise function using multiple octaves
float fbm_noise(vec2 uv, float time) {
    // Multiple layers of noise with different scales and offsets
    float noise1 = texture(cloud_noise_texture, uv * 1.0 + vec2(time * 0.01, 0.0)).r;
    float noise2 = texture(cloud_noise_texture, uv * 2.0 + vec2(-time * 0.015, time * 0.01)).r;
    float noise3 = texture(cloud_noise_texture, uv * 4.0 + vec2(time * 0.02, -time * 0.02)).r;
    
    // Combine noise layers with decreasing amplitude
    return (noise1 * 0.5 + noise2 * 0.3 + noise3 * 0.2);
}

// Advanced cloud generation that avoids poles
float advanced_clouds(vec3 ray_dir, float time) {
    // Get improved UV mapping
    vec2 base_uv = improved_spherical_uv(ray_dir);
    
    // Apply cloud movement with wraparound
    float time_scale = time * cloud_speed * 0.05;
    vec2 moved_uv = fract(base_uv + 
        vec2(
            cloud_movement_direction.x * time_scale, 
            cloud_movement_direction.y * time_scale
        )
    );
    
    // Pole avoidance - reduce cloud density near the poles
    float pole_mask = 1.0 - smoothstep(0.8, 1.0, abs(ray_dir.y));
    
    // Generate noise with multiple octaves
    float base_cloud = fbm_noise(moved_uv, time);
    
    // Altitude-based cloud density adjustment
    float altitude_factor = 1.0 - smoothstep(-0.2, 0.2, ray_dir.y);
    base_cloud = mix(base_cloud, base_cloud * 1.2, altitude_factor);
    
    // Apply pole mask to dramatically reduce cloud density
    base_cloud *= pole_mask;
    
    // Apply cloud coverage and edge softness
    float threshold = 1.0 - cloud_coverage;
    float cloud_factor = smoothstep(
        threshold - cloud_edge_softness, 
        threshold + cloud_edge_softness, 
        base_cloud
    );
    
    return cloud_factor;
}

void sky() {
    // Direction of the current fragment
    vec3 dir = EYEDIR;
    
    // Base sky color calculation based on height
    float height_factor = clamp(dir.y, 0.0, 1.0);
    
    // Sky color transition based on time of day
    vec3 top_color, bottom_color;
    vec3 halo_color;
    
    // Calculate day/night cycle
    if (time_of_day < 0.25) { // Night to sunrise
        float t = time_of_day / 0.25;
        
        // Make colors deeper near midnight (closer to 0.0)
        float midnight_intensity = 1.0 - abs(time_of_day * 4.0 - 1.0);
        
        // More distinct deep blue night colors
        top_color = mix(
            vec3(0.01, 0.01, 0.03),    // Extremely dark blue-black
            vec3(0.1, 0.1, 0.2),        // Slightly lighter blue-black
            t
        );
        // Intensify darkness near midnight
        top_color *= mix(1.0, 1.5, midnight_intensity);
        
        bottom_color = mix(
            vec3(0.02, 0.02, 0.06),      // Very dark blue-black
            vec3(0.15, 0.15, 0.25),     // Slightly lighter dark blue
            t
        );
        // Intensify darkness near midnight
        bottom_color *= mix(1.0, 1.5, midnight_intensity);
        
        halo_color = mix(
            vec3(0.2, 0.2, 0.5),        // Deep, deep blue
            vec3(0.5, 0.5, 1.0),        // Lighter blue
            t
        );
        // Intensify darkness of halo near midnight
        halo_color *= mix(1.0, 1.3, midnight_intensity);
    } else if (time_of_day < 0.5) { // Sunrise to noon
        float t = (time_of_day - 0.25) / 0.25;
        // Smooth transition between sunset and day colors
        top_color = mix(
            vec3(0.1, 0.1, 0.2),        // Night blue
            day_top_color,               // Day top color
            smoothstep(0.0, 1.0, t)     // Smooth interpolation
        );
        bottom_color = mix(
            vec3(0.15, 0.15, 0.25),     // Night blue bottom
            day_bottom_color,            // Day bottom color
            smoothstep(0.0, 1.0, t)     // Smooth interpolation
        );
        halo_color = mix(
            vec3(0.5, 0.5, 1.0),        // Night blue halo
            vec3(1.0, 1.0, 1.0),        // Bright day halo
            smoothstep(0.0, 1.0, t)     // Smooth interpolation
        );
    } else if (time_of_day < 0.75) { // Noon to sunset
        float t = (time_of_day - 0.5) / 0.25;
        // Smooth transition between day and sunset colors
        top_color = mix(
            day_top_color,               // Day top color
            sunset_top_color,            // Sunset top color
            smoothstep(0.0, 1.0, t)     // Smooth interpolation
        );
        bottom_color = mix(
            day_bottom_color,            // Day bottom color
            sunset_bottom_color,         // Sunset bottom color
            smoothstep(0.0, 1.0, t)     // Smooth interpolation
        );
        halo_color = mix(
            vec3(1.0, 1.0, 1.0),        // Bright day halo
            vec3(1.0, 0.6, 0.3),        // Sunset halo
            smoothstep(0.0, 1.0, t)     // Smooth interpolation
        );
    } else { // Sunset to night
        float t = (time_of_day - 0.75) / 0.25;
        // Quickly transition to deep blue night colors
        top_color = mix(
            sunset_top_color, 
            vec3(0.01, 0.01, 0.03),    // Extremely dark blue-black
            smoothstep(0.0, 1.0, t)    // Smooth interpolation
        );
        bottom_color = mix(
            sunset_bottom_color, 
            vec3(0.02, 0.02, 0.06),      // Very dark blue-black
            smoothstep(0.0, 1.0, t)    // Smooth interpolation
        );
        halo_color = mix(
            vec3(1.0, 0.6, 0.3),        // Sunset orange
            vec3(0.2, 0.2, 0.5),        // Deep, deep blue
            smoothstep(0.0, 1.0, t)    // Smooth interpolation
        );
    }
    
    // Basic sky gradient with enhanced horizon atmosphere
    float horizon_factor = 1.0 - pow(height_factor, 0.4); // Stronger effect near horizon
    vec3 horizon_glow = mix(bottom_color, bottom_color * 1.2, horizon_factor * horizon_factor);
    vec3 sky_color = mix(horizon_glow, top_color, pow(height_factor, 0.5));
    
    // Determine if it's night time
    bool is_night = time_of_day < 0.25 || time_of_day > 0.75;
    
    // Light source calculation (sun/moon)
    vec3 light_dir = normalize(LIGHT0_DIRECTION);
    float light_dot = max(0.0, dot(dir, light_dir));
    
    // Sun calculation
    float sun_factor = smoothstep(1.0 - sun_size, (1.0 - sun_size) + 0.001, light_dot);
    float sun_halo_factor = pow(light_dot, 32.0) * sun_halo;
    
    // Moon calculation
    float moon_factor = smoothstep(1.0 - moon_size, (1.0 - moon_size) + 0.001, light_dot);
    float moon_halo_factor = pow(light_dot, 32.0) * moon_halo;
    
    // Color for sun and moon
    vec3 sun_color = is_night ? vec3(0.0) : vec3(1.0, 1.0, 1.0);
    vec3 moon_color = is_night ? vec3(0.8, 0.8, 0.9) : vec3(0.0);
    vec3 sun_halo_color = halo_color;
    vec3 moon_halo_color = is_night ? vec3(0.6, 0.6, 0.7) : vec3(0.0);
    
    // Determine which light source to use
    float primary_factor = is_night ? moon_factor : sun_factor;
    float primary_halo = is_night ? moon_halo_factor : sun_halo_factor;
    vec3 primary_color = is_night ? moon_color : sun_color;
    vec3 primary_halo_color = is_night ? moon_halo_color : sun_halo_color;
    
    // Add primary light source to sky color
    sky_color += primary_factor * primary_color;
    sky_color += primary_halo * primary_halo_color;
    
    // Add clouds
    float time = TIME * 0.05;
    float cloud_density = advanced_clouds(dir, time);
    
    // Cloud coloring based on time of day
    vec3 cloud_color_day = vec3(1.0);
    vec3 cloud_color_sunset = vec3(0.9, 0.7, 0.5);
    vec3 cloud_color_night = vec3(0.2, 0.2, 0.3);
    
    vec3 cloud_color;
    if (time_of_day < 0.25) {
        cloud_color = mix(cloud_color_night, cloud_color_sunset, time_of_day / 0.25);
    } else if (time_of_day < 0.5) {
        cloud_color = mix(cloud_color_sunset, cloud_color_day, (time_of_day - 0.25) / 0.25);
    } else if (time_of_day < 0.75) {
        cloud_color = mix(cloud_color_day, cloud_color_sunset, (time_of_day - 0.5) / 0.25);
    } else {
        cloud_color = mix(cloud_color_sunset, cloud_color_night, (time_of_day - 0.75) / 0.25);
    }
    
    // Cloud lighting calculations
    float direct_light = max(0.0, dot(light_dir, vec3(0.0, 1.0, 0.0)));
    float side_light = max(0.0, dot(normalize(vec3(dir.x, 0.2, dir.z)), light_dir));
    
    // Combine lighting effects
    vec3 lit_cloud_color = mix(
        cloud_color * 0.5, // Shadow color
        cloud_color * 1.3, // Fully lit color
        mix(side_light, direct_light, 0.5) // Blend lighting
    );
    
    // Add subtle silver lining on cloud edges
    float edge_factor = smoothstep(0.0, 0.2, cloud_density) - smoothstep(0.4, 0.9, cloud_density);
    lit_cloud_color += cloud_color * edge_factor * side_light * 0.3;
    
    // Mix clouds with sky
    sky_color = mix(sky_color, lit_cloud_color, cloud_density);
    
    // Horizon line (for ground blending)
    float horizon = smoothstep(-horizon_blend, horizon_blend, dir.y);
    sky_color = mix(bottom_color * 0.8, sky_color, horizon);
    
    // Output final color
    COLOR = sky_color;
}