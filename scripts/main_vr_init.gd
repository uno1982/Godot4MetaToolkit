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
			# Detect device model if possible
			var device_name = openxr_ext.get_system_name() if openxr_ext.has_method("get_system_name") else ""
			var is_quest3 = device_name.find("Quest 3") >= 0
			
			if is_quest3:
				# Quest 3 settings
				openxr_ext.set_display_refresh_rate(90.0)  # Try for 90Hz
				openxr_ext.set_cpu_performance_level(3)
				openxr_ext.set_gpu_performance_level(5)  # Max for Quest 3
				print("Quest 3 detected: Set to 90Hz, CPU=3, GPU=5")
			else:
				# Quest 2 settings
				openxr_ext.set_display_refresh_rate(72.0)  # More reliable on Quest 2
				openxr_ext.set_cpu_performance_level(3)
				openxr_ext.set_gpu_performance_level(4)  # Max for Quest 2
				print("Quest 2 detected: Set to 72Hz, CPU=3, GPU=4")
		else:
			print("OpenXR extensions not available")
	else:
		print("HMD Not Connected! Check Meta link or Steamvr connection")
