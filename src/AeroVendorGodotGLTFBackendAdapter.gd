class_name AeroVendorGodotGLTFBackendAdapter
extends RefCounted

const _RUNTIME_LOADER_SCRIPT_PATHS := [
	"res://addons/aerobeat-vendor-godot-gltf/loaders/aero_godot_gltf_runtime_loader.gd",
]

var _runtime_loader: Variant = null

func load_scene_bundle(request: Dictionary) -> Dictionary:
	var asset_path := String(request.get("asset_path", "")).strip_edges()
	var format := String(request.get("format", request.get("container", ""))).strip_edges().to_lower()
	var runtime_loader: Variant = _resolve_runtime_loader()
	if runtime_loader == null or not runtime_loader.has_method("load_source"):
		return {
			"ok": false,
			"error_code": "vendor_runtime_unavailable",
			"message": "Vendor GLTF runtime loader is unavailable.",
			"recoverable": true,
			"details": {
				"asset_path": asset_path,
				"format": format,
			},
		}

	var source := {
		"path": asset_path,
		"format": format,
	}
	var instantiate := bool(request.get("instantiate", true))
	var runtime_result: Dictionary = runtime_loader.load_scene(source) if instantiate else runtime_loader.load_source(source)
	if not bool(runtime_result.get("success", false)):
		return {
			"ok": false,
			"error_code": String(runtime_result.get("code", "vendor_load_failed")),
			"message": String(runtime_result.get("message", "Vendor GLTF runtime loader failed.")),
			"recoverable": true,
			"details": _dictionary_or_empty(runtime_result.get("detail", {})),
		}

	var detail := _dictionary_or_empty(runtime_result.get("detail", {}))
	var normalized_path := _normalize_asset_path(asset_path)
	var resource_path := _resource_path_for(asset_path)
	var scene_root: Variant = detail.get("scene", null)
	var packed_scene: PackedScene = null
	if instantiate and scene_root != null:
		packed_scene = PackedScene.new()
		var pack_error := packed_scene.pack(scene_root)
		if pack_error != OK:
			packed_scene = null

	return {
		"ok": true,
		"asset_path": asset_path,
		"absolute_path": normalized_path,
		"resource_path": resource_path,
		"format": format,
		"container": String(request.get("container", format)),
		"scene_root": scene_root,
		"packed_scene": packed_scene,
		"warnings": [],
		"details": {
			"vendor": detail,
			"instantiate": instantiate,
		},
	}

func _resolve_runtime_loader() -> Variant:
	if _runtime_loader != null and _runtime_loader.has_method("load_source"):
		return _runtime_loader

	for script_path in _RUNTIME_LOADER_SCRIPT_PATHS:
		if not ResourceLoader.exists(script_path, "Script"):
			continue
		var script_resource: Variant = load(script_path)
		if script_resource == null or not script_resource.has_method("new"):
			continue
		_runtime_loader = script_resource.new()
		if _runtime_loader != null and _runtime_loader.has_method("load_source"):
			return _runtime_loader

	return null

func _normalize_asset_path(asset_path: String) -> String:
	if asset_path.is_empty():
		return ""
	return ProjectSettings.globalize_path(asset_path) if asset_path.begins_with("res://") or asset_path.begins_with("user://") else asset_path.simplify_path()

func _resource_path_for(asset_path: String) -> String:
	if asset_path.begins_with("res://"):
		return asset_path
	return ""

func _dictionary_or_empty(value: Variant) -> Dictionary:
	if value is Dictionary:
		return Dictionary(value).duplicate(true)
	return {}
