extends Node3D
var xr_interface: XRInterface

#this is the main init script for a VR Scene
func _ready():
	xr_interface = XRServer.find_interface("OpenXR")
	
	if xr_interface and xr_interface.is_initialized():
		print("OpenXR init successfully")
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		
		get_viewport().use_xr = true
		# Get the OpenXR extensions object first
		var openxr_ext = xr_interface.get_openxr_extensions()
		if openxr_ext:
			openxr_ext.set_display_refresh_rate(90.0)
			# Set GPU level (0-4 for Quest 2, 0-5 for Quest 3)
			openxr_ext.set_cpu_performance_level(4)  # Medium-high CPU
			openxr_ext.set_gpu_performance_level(4)  # High GPU (max for Quest 2)
			print("Set Quest performance levels: CPU=4, GPU=4")
		else:
			print("OpenXR extensions not available")
	else:
		print("HMD Not Connected! Check Meta link or Steamvr connection")
