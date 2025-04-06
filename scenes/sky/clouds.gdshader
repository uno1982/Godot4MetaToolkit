shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_front, unshaded;

uniform sampler2D noise_texture;
uniform float cloud_density : hint_range(0.0, 1.0) = 0.8;
uniform float edge_softness : hint_range(0.0, 0.5) = 0.1;
uniform vec3 cloud_color : source_color = vec3(1.0);
uniform float time_scale : hint_range(0.0, 0.1) = 0.01;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.3;
uniform float noise_scale : hint_range(0.01, 1.0) = 0.1;

void fragment() {
    // Basic sphere shape with soft edges
    vec3 normal = normalize(NORMAL);
    float fresnel = pow(1.0 - dot(normal, VIEW), 2.0);
    
    // Get world position
    vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
    
    // Spherical to Cartesian conversion to avoid pole pinching
    // Using world position directly for proper world space movement
    vec3 sample_pos = world_pos * noise_scale;
    
    // Time offsets for animation
    vec3 time_offset = vec3(TIME * time_scale, TIME * time_scale * 0.7, TIME * time_scale * 0.3);
    
    // Sample noise at different scales for detail
    float noise1 = texture(noise_texture, sample_pos.xy + time_offset.xy).r;
    float noise2 = texture(noise_texture, sample_pos.yz * 2.0 - time_offset.yz * 1.5).r;
    float noise3 = texture(noise_texture, sample_pos.xz * 4.0 + time_offset.xz * 0.5).r;
    
    // Combine noise samples for detail
    float combined_noise = noise1 * 0.6 + noise2 * 0.3 + noise3 * 0.1;
    
    // Create fluffy cloud effect
    float cloud_shape = smoothstep(0.0, edge_softness, combined_noise) * 
                      smoothstep(1.0, 1.0 - edge_softness, combined_noise);
                      
    // Apply fresnel for edge glow
    float edge_glow = smoothstep(0.5, 1.0, fresnel);
    
    // Final alpha calculations
    float alpha = cloud_shape * cloud_density;
    alpha = mix(alpha, alpha * (1.0 - edge_glow * 0.5), detail_strength);
    
    // Output
    ALBEDO = cloud_color;
    ALPHA = clamp(alpha, 0.0, 1.0);
    
    // Add some depth to the clouds with subtle shading
    float depth = mix(0.8, 1.0, combined_noise);
    ALBEDO *= depth;
}