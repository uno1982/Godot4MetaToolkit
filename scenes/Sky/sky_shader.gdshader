shader_type sky;
render_mode use_half_res_pass;

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

// 3D Noise-based cloud generation
// This approach eliminates UV seams by working directly in 3D space
float voronoi_noise(vec3 p) {
    vec3 ip = floor(p);
    vec3 fp = fract(p);
    
    float minDist = 1.0;
    
    for (int i = -1; i <= 1; i++) {
        for (int j = -1; j <= 1; j++) {
            for (int k = -1; k <= 1; k++) {
                vec3 offset = vec3(float(i), float(j), float(k));
                // Generate a random position from the cell coordinate
                vec3 pos = offset + vec3(
                    fract(sin(dot(ip + offset, vec3(12.9898, 78.233, 45.164))) * 43758.5453),
                    fract(sin(dot(ip + offset, vec3(39.346, 11.135, 83.155))) * 43758.5453),
                    fract(sin(dot(ip + offset, vec3(73.156, 52.235, 09.151))) * 43758.5453)
                );
                
                float dist = length(pos - fp);
                minDist = min(minDist, dist);
            }
        }
    }
    
    return minDist;
}

// Simple hash function for noise
float hash_noise(vec3 p) {
    p = fract(p * vec3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.x + p.y) * p.z);
}

// Generate simple 3D value noise
float value_noise_3d(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    
    // Smoothstep interpolation
    vec3 u = f * f * (3.0 - 2.0 * f);
    
    // Sample 8 corners of the cube
    float a = hash_noise(i);
    float b = hash_noise(i + vec3(1.0, 0.0, 0.0));
    float c = hash_noise(i + vec3(0.0, 1.0, 0.0));
    float d = hash_noise(i + vec3(1.0, 1.0, 0.0));
    float e = hash_noise(i + vec3(0.0, 0.0, 1.0));
    float f1 = hash_noise(i + vec3(1.0, 0.0, 1.0));
    float g = hash_noise(i + vec3(0.0, 1.0, 1.0));
    float h = hash_noise(i + vec3(1.0, 1.0, 1.0));
    
    // Trilinear interpolation
    float k0 = a;
    float k1 = b - a;
    float k2 = c - a;
    float k3 = e - a;
    float k4 = a - b - c + d;
    float k5 = a - c - e + g;
    float k6 = a - b - e + f1;
    float k7 = -a + b + c - d + e - f1 - g + h;
    
    return k0 + k1 * u.x + k2 * u.y + k3 * u.z + 
           k4 * u.x * u.y + k5 * u.y * u.z + k6 * u.x * u.z + 
           k7 * u.x * u.y * u.z;
}

// Ultra-simple cloud noise with continuous, non-symmetric coverage
float basic_cloud_noise(vec3 dir, float time) {
    // Use a fixed reference plane rather than ray direction
    // This creates a consistent layer of clouds across the entire sky
    vec3 base_plane = normalize(vec3(0.0, 1.0, 0.0)); // Up vector
    
    // Project the view direction onto a plane for consistent sampling
    float height = dir.y;
    vec3 flat_dir = normalize(dir - base_plane * height);
    
    // Calculate a position on a virtual cloud layer
    // This avoids spherical mapping issues while maintaining continuity
    vec3 cloud_pos = flat_dir * (1.0 - abs(height) * 0.5) + vec3(0.0, height * 0.2, 0.0);
    
    // Scale for appropriate cloud size
    cloud_pos *= 0.25;
    
    // Create a time-dependent offset for movement
    vec2 movement = cloud_movement_direction * time * cloud_speed * 0.1;
    
    // Apply movement to x-z plane (keeping height consistent)
    cloud_pos.x += movement.x;
    cloud_pos.z += movement.y;
    
    // Basic noise sampling at different frequencies
    float n1 = value_noise_3d(cloud_pos);
    float n2 = value_noise_3d(cloud_pos * 2.0 + vec3(100.0, 50.0, 200.0));
    float n3 = value_noise_3d(cloud_pos * 4.0 + vec3(200.0, 100.0, 300.0));
    
    // Mix the noise samples with varied weights
    float noise = n1 * 0.5 + n2 * 0.35 + n3 * 0.15;
    
    // Apply vertical falloff to create layered feeling
    float vertical_falloff = 1.0 - pow(abs(height), 1.5);
    
    return noise * vertical_falloff;
}

// Get cloud density with more natural distribution
float get_cloud_density(vec3 ray_dir, float time) {
    // Get base noise
    float noise = basic_cloud_noise(ray_dir, time);
    
    // Shape the clouds with variable thickness
    float base_thickness = cloud_coverage * 0.7 + 0.3; // Ensure some minimum coverage
    float cloud_shape = smoothstep(0.4 - base_thickness * 0.4, 0.6, noise);
    
    // Add edge softness
    float edge_softness_factor = cloud_edge_softness * 0.5;
    float soft_edges = smoothstep(0.0, edge_softness_factor, cloud_shape) * 
                       (1.0 - smoothstep(1.0 - edge_softness_factor, 1.0, cloud_shape));
    
    float cloud_factor = cloud_shape * (0.8 + soft_edges * 0.2);
    
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
    
    // Add clouds using 3D noise approach
    float time = TIME * 0.05;
    float cloud_density = get_cloud_density(dir, time);
    
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