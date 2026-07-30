@tool
extends EditorPlugin

var _export_plugin: EditorExportPlugin

func _enter_tree() -> void:
	_export_plugin = PicoManifestExportPlugin.new()
	add_export_plugin(_export_plugin)

func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null

class PicoManifestExportPlugin extends EditorExportPlugin:
	func _get_name() -> String:
		return "PicoManifestPatch"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	# PICO OS gates full 3D/compositor "resume" on this vendor-specific tag
	# (undocumented in PICO's Unity/SpatialUI SDK docs -- only in the OpenXR
	# Mobile SDK docs at sdk.picovr.com/docs/OpenXRMobileSDKv2/). Without it,
	# `dumpsys package` shows isAllComponentVr:false and PICO logs
	# "No 3D activity resumed & No permission" -- the app runs but nothing
	# ever renders, not a crash, not a Godot-side bug. Harmless on Quest/other
	# OpenXR runtimes, which simply ignore an unrecognized meta-data key.
	func _get_android_manifest_application_element_contents(platform: EditorExportPlatform, debug: bool) -> String:
		return '<meta-data android:name="pvr.app.type" android:value="vr" />'
