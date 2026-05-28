class_name AeroVendorGodotGLTFBackendAdapter
extends RefCounted

const _RUNTIME_LOADER_SCRIPT_PATHS := [
	"res://addons/aerobeat-vendor-godot-gltf/loaders/aero_godot_gltf_runtime_loader.gd",
	"res://addons/aerobeat-vendor-godot-gltf/src/aero_godot_gltf_runtime_loader.gd",
	"res://../aerobeat-vendor-godot-gltf/src/aero_godot_gltf_runtime_loader.gd",
]

var _runtime_loader: Variant = null

func load_scene_bundle(request: Dictionary) -> Dictionary:
	var source := _resolve_vendor_source(request)
	var format := String(source.get("format", request.get("format", request.get("container", "")))).strip_edges().to_lower()
	var runtime_loader: Variant = _resolve_runtime_loader()
	if runtime_loader == null or not runtime_loader.has_method("load_source"):
		return {
			"ok": false,
			"error_code": "vendor_runtime_unavailable",
			"message": "Vendor GLTF runtime loader is unavailable.",
			"recoverable": true,
			"details": {
				"source": source,
				"format": format,
			},
		}

	var instantiate := bool(request.get("instantiate", true))
	var runtime_result: Dictionary = runtime_loader.load_scene(source, 0, _dictionary_or_empty(request.get("scene_options", {}))) if instantiate else runtime_loader.load_source(source)
	if not bool(runtime_result.get("success", false)):
		return {
			"ok": false,
			"error_code": String(runtime_result.get("code", "vendor_load_failed")),
			"message": String(runtime_result.get("message", "Vendor GLTF runtime loader failed.")),
			"recoverable": true,
			"details": _dictionary_or_empty(runtime_result.get("detail", {})),
		}

	var detail: Dictionary = _dictionary_or_empty(runtime_result.get("detail", {}))
	var asset_path := _asset_path_for_source(source)
	var resource_path: String = _resource_path_for(source)
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
		"source": source.duplicate(true),
		"absolute_path": _absolute_path_for(source, detail),
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

func load_scene_instance_bundle(request: Dictionary) -> Dictionary:
	var source := _resolve_vendor_source(request)
	var format := String(source.get("format", request.get("format", request.get("container", "")))).strip_edges().to_lower()
	var runtime_loader: Variant = _resolve_runtime_loader()
	if runtime_loader == null or not runtime_loader.has_method("load_scene_instance"):
		return {
			"ok": false,
			"error_code": "vendor_runtime_unavailable",
			"message": "Vendor GLTF runtime loader is unavailable.",
			"recoverable": true,
			"details": {
				"source": source,
				"format": format,
				"required_method": "load_scene_instance",
			},
		}

	var runtime_result: Dictionary = runtime_loader.load_scene_instance(
		source,
		0,
		_dictionary_or_empty(request.get("scene_options", {})),
		_normalize_vendor_instance_options(_dictionary_or_empty(request.get("instance", {})))
	)
	if not bool(runtime_result.get("success", false)):
		return {
			"ok": false,
			"error_code": String(runtime_result.get("code", "vendor_load_failed")),
			"message": String(runtime_result.get("message", "Vendor GLTF runtime loader failed.")),
			"recoverable": true,
			"details": _dictionary_or_empty(runtime_result.get("detail", {})),
		}

	var detail: Dictionary = _dictionary_or_empty(runtime_result.get("detail", {}))
	var instance_root: Variant = detail.get("scene", null)
	var packed_scene: PackedScene = null
	if instance_root != null:
		packed_scene = PackedScene.new()
		var pack_error := packed_scene.pack(instance_root)
		if pack_error != OK:
			packed_scene = null

	return {
		"ok": true,
		"asset_path": _asset_path_for_source(source),
		"source": source.duplicate(true),
		"absolute_path": _absolute_path_for(source, detail),
		"resource_path": _resource_path_for(source),
		"format": format,
		"container": String(request.get("container", format)),
		"scene_root": instance_root,
		"instance_root": instance_root,
		"loaded_scene_root": detail.get("loaded_scene", null),
		"packed_scene": packed_scene,
		"warnings": [],
		"details": {
			"vendor": detail,
			"instance": _dictionary_or_empty(request.get("instance", {})),
			"scene_options": _dictionary_or_empty(request.get("scene_options", {})),
		},
	}

func load_scene_bundles(request: Dictionary) -> Dictionary:
	var runtime_loader: Variant = _resolve_runtime_loader()
	if runtime_loader == null or not runtime_loader.has_method("load_scene_instances"):
		return {
			"ok": false,
			"error_code": "vendor_runtime_unavailable",
			"message": "Vendor GLTF runtime loader is unavailable.",
			"recoverable": true,
			"details": {
				"required_method": "load_scene_instances",
			},
		}

	var vendor_instances: Array = []
	for instance_variant in _array_or_empty(request.get("instances", [])):
		if not (instance_variant is Dictionary):
			continue
		var instance_request: Dictionary = Dictionary(instance_variant)
		vendor_instances.append({
			"name": String(_dictionary_or_empty(instance_request.get("instance", {})).get("name", "")),
			"source": _resolve_vendor_source(instance_request),
			"transform": _dictionary_or_empty(_dictionary_or_empty(instance_request.get("instance", {})).get("transform", {})),
			"metadata": _dictionary_or_empty(_dictionary_or_empty(instance_request.get("instance", {})).get("metadata", {})),
		})

	var runtime_result: Dictionary = runtime_loader.load_scene_instances(
		vendor_instances,
		0,
		_dictionary_or_empty(request.get("scene_options", {}))
	)
	if not bool(runtime_result.get("success", false)):
		return {
			"ok": false,
			"error_code": String(runtime_result.get("code", "vendor_load_failed")),
			"message": String(runtime_result.get("message", "Vendor GLTF runtime loader failed.")),
			"recoverable": true,
			"details": _dictionary_or_empty(runtime_result.get("detail", {})),
		}

	var detail: Dictionary = _dictionary_or_empty(runtime_result.get("detail", {}))
	var scene_root: Variant = detail.get("scene", null)
	var normalized_instances: Array = []
	var vendor_results: Array = _array_or_empty(detail.get("instances", []))
	var requested_instances: Array = _array_or_empty(request.get("instances", []))
	for index in range(vendor_results.size()):
		var vendor_instance_variant: Variant = vendor_results[index]
		if not (vendor_instance_variant is Dictionary):
			continue
		var vendor_instance: Dictionary = Dictionary(vendor_instance_variant)
		var requested_instance: Dictionary = {}
		if index < requested_instances.size() and requested_instances[index] is Dictionary:
			requested_instance = Dictionary(requested_instances[index])
		var requested_source := _resolve_vendor_source(requested_instance)
		normalized_instances.append({
			"asset_path": _asset_path_for_source(requested_source),
			"source": requested_source,
			"absolute_path": _absolute_path_for(requested_source, {"download": _dictionary_or_empty(vendor_instance.get("download", {}))}),
			"resource_path": _resource_path_for(requested_source),
			"format": String(requested_source.get("format", requested_instance.get("format", requested_instance.get("container", "")))),
			"container": String(requested_instance.get("container", requested_source.get("format", requested_instance.get("format", "")))),
			"scene_root": vendor_instance.get("instance_root", null),
			"instance_root": vendor_instance.get("instance_root", null),
			"loaded_scene_root": vendor_instance.get("loaded_scene", null),
			"warnings": [],
			"details": {
				"vendor": vendor_instance.duplicate(true),
				"instance": _dictionary_or_empty(requested_instance.get("instance", {})),
			},
		})

	return {
		"ok": true,
		"scene_root": scene_root,
		"instances": normalized_instances,
		"warnings": [],
		"details": {
			"vendor": detail,
			"scene_options": _dictionary_or_empty(request.get("scene_options", {})),
			"metadata": _dictionary_or_empty(request.get("metadata", {})),
		},
	}

func unload_result(result: Dictionary) -> Dictionary:
	var runtime_loader: Variant = _resolve_runtime_loader()
	if runtime_loader == null or not runtime_loader.has_method("unload_result"):
		return {
			"ok": true,
			"unloaded": false,
			"freed_roots": 0,
		}
	var vendor_result := _dictionary_or_empty(result.get("details", {})).get("vendor", _dictionary_or_empty(result.get("details", {})))
	var runtime_result: Dictionary = runtime_loader.unload_result({"detail": vendor_result})
	return {
		"ok": bool(runtime_result.get("success", true)),
		"unloaded": bool(_dictionary_or_empty(runtime_result.get("detail", {})).get("unloaded", false)),
		"freed_roots": int(_dictionary_or_empty(runtime_result.get("detail", {})).get("freed_roots", 0)),
		"details": _dictionary_or_empty(runtime_result.get("detail", {})),
	}

func unload_last_result() -> Dictionary:
	var runtime_loader: Variant = _resolve_runtime_loader()
	if runtime_loader == null or not runtime_loader.has_method("unload_last_result"):
		return {
			"ok": true,
			"unloaded": false,
			"freed_roots": 0,
		}
	var runtime_result: Dictionary = runtime_loader.unload_last_result()
	return {
		"ok": bool(runtime_result.get("success", true)),
		"unloaded": bool(_dictionary_or_empty(runtime_result.get("detail", {})).get("unloaded", false)),
		"freed_roots": int(_dictionary_or_empty(runtime_result.get("detail", {})).get("freed_roots", 0)),
		"details": _dictionary_or_empty(runtime_result.get("detail", {})),
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

func _resolve_vendor_source(request: Dictionary) -> Dictionary:
	var explicit_source := _dictionary_or_empty(request.get("source", {}))
	if not explicit_source.is_empty():
		return {
			"kind": String(explicit_source.get("kind", "file")).strip_edges().to_lower(),
			"path": String(explicit_source.get("path", "")).strip_edges(),
			"url": String(explicit_source.get("url", "")).strip_edges(),
			"format": String(explicit_source.get("format", request.get("format", request.get("container", "")))).strip_edges().to_lower(),
			"metadata": _dictionary_or_empty(explicit_source.get("metadata", {})),
		}

	var asset_path := String(request.get("asset_path", "")).strip_edges()
	var source_kind := "url" if _is_http_url(asset_path) else "file"
	return {
		"kind": source_kind,
		"path": asset_path if source_kind == "file" else "",
		"url": asset_path if source_kind == "url" else "",
		"format": String(request.get("format", request.get("container", ""))).strip_edges().to_lower(),
		"metadata": {},
	}

func _asset_path_for_source(source: Dictionary) -> String:
	var url := String(source.get("url", "")).strip_edges()
	if not url.is_empty():
		return url
	return String(source.get("path", "")).strip_edges()

func _absolute_path_for(source: Dictionary, detail: Dictionary) -> String:
	var source_kind := String(source.get("kind", "file"))
	if source_kind == "url":
		return String(_dictionary_or_empty(detail.get("download", {})).get("file_path", "")).strip_edges()
	var asset_path := String(source.get("path", "")).strip_edges()
	if asset_path.is_empty():
		return ""
	return ProjectSettings.globalize_path(asset_path) if asset_path.begins_with("res://") or asset_path.begins_with("user://") else asset_path.simplify_path()

func _resource_path_for(source: Dictionary) -> String:
	var asset_path := String(source.get("path", "")).strip_edges()
	if asset_path.begins_with("res://"):
		return asset_path
	return ""

func _normalize_vendor_instance_options(instance_options: Dictionary) -> Dictionary:
	return {
		"name": String(instance_options.get("name", "")).strip_edges(),
		"transform": _dictionary_or_empty(instance_options.get("transform", {})),
		"metadata": _dictionary_or_empty(instance_options.get("metadata", {})),
	}

func _is_http_url(value: String) -> bool:
	var normalized := value.strip_edges().to_lower()
	return normalized.begins_with("http://") or normalized.begins_with("https://")

func _dictionary_or_empty(value: Variant) -> Dictionary:
	if value is Dictionary:
		return Dictionary(value).duplicate(true)
	return {}

func _array_or_empty(value: Variant) -> Array:
	if value is Array:
		return Array(value).duplicate(true)
	return []
