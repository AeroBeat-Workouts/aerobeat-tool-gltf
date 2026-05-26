## Consumer-facing GLTF/GLB facade for AeroBeat tool-side callers.
##
## This surface intentionally hides Godot runtime/import details behind the
## vendor repo so higher-level consumers can ask for a scene bundle without
## owning `GLTFDocument`, importer, or resource-pipeline branching themselves.
class_name AeroGLTFTool
extends RefCounted

const VERSION: String = "0.1.0"

const ERROR_INVALID_REQUEST := "invalid_request"
const ERROR_UNSUPPORTED_FORMAT := "unsupported_format"
const ERROR_BACKEND_UNAVAILABLE := "backend_unavailable"
const ERROR_BACKEND_FAILED := "backend_failed"

const SUPPORTED_CONTAINERS := ["gltf", "glb"]
const DEFAULT_BACKEND_CLASS_NAMES := [
	"AeroVendorGodotGLTF",
	"AeroVendorGodotGLTFManager",
]
const DEFAULT_BACKEND_SCRIPT_PATHS := [
	"res://addons/aerobeat-vendor-godot-gltf/src/AeroVendorGodotGLTF.gd",
	"res://addons/aerobeat-vendor-godot-gltf/src/AeroVendorGodotGLTFManager.gd",
]
const BACKEND_METHOD_LOAD_SCENE_BUNDLE := "load_scene_bundle"

var _runtime_backend: Variant = null

func set_runtime_backend(runtime_backend: Variant) -> void:
	_runtime_backend = runtime_backend

func clear_runtime_backend() -> void:
	_runtime_backend = null

func supports_container(container: String) -> bool:
	return SUPPORTED_CONTAINERS.has(_normalize_container(container))

func supported_containers() -> Array:
	return SUPPORTED_CONTAINERS.duplicate()

func get_backend_contract() -> Dictionary:
	return {
		"class_names": DEFAULT_BACKEND_CLASS_NAMES.duplicate(),
		"script_paths": DEFAULT_BACKEND_SCRIPT_PATHS.duplicate(),
		"method": BACKEND_METHOD_LOAD_SCENE_BUNDLE,
		"request_keys": [
			"asset_path",
			"container",
			"format",
			"instantiate",
			"metadata",
		],
		"result_keys": [
			"ok",
			"scene_root",
			"packed_scene",
			"asset_path",
			"absolute_path",
			"resource_path",
			"format",
			"container",
			"warnings",
			"details",
			"error_code",
			"message",
			"recoverable",
		],
	}

func build_scene_request(asset_path: String, options: Dictionary = {}) -> Dictionary:
	var request := options.duplicate(true)
	request["asset_path"] = asset_path
	return normalize_scene_request(request)

func normalize_scene_request(request: Dictionary) -> Dictionary:
	var asset_path := String(request.get("asset_path", "")).strip_edges()
	if asset_path.is_empty():
		return _failure({}, ERROR_INVALID_REQUEST, "GLTF/GLB requests require a non-empty asset_path.")

	var container := _normalize_container(String(
		request.get("container", request.get("format", request.get("format_hint", "")))
	))
	if container.is_empty():
		container = _container_from_asset_path(asset_path)
	if not supports_container(container):
		return _failure(
			{"asset_path": asset_path},
			ERROR_UNSUPPORTED_FORMAT,
			"Unsupported GLTF container for path '%s'. Supported containers: %s" % [
				asset_path,
				", ".join(PackedStringArray(SUPPORTED_CONTAINERS)),
			]
		)

	var normalized_request := {
		"asset_path": asset_path,
		"container": container,
		"format": container,
		"instantiate": bool(request.get("instantiate", true)),
		"metadata": _dictionary_or_empty(request.get("metadata", {})),
	}
	return {
		"ok": true,
		"request": normalized_request,
	}

func load_scene_from_path(asset_path: String, options: Dictionary = {}) -> Dictionary:
	var normalized_result := build_scene_request(asset_path, options)
	if not normalized_result.get("ok", false):
		return normalized_result
	return load_scene(Dictionary(normalized_result.get("request", {})))

func load_scene(request: Dictionary) -> Dictionary:
	var normalized_result := normalize_scene_request(request)
	if not normalized_result.get("ok", false):
		return normalized_result

	var normalized_request: Dictionary = Dictionary(normalized_result.get("request", {})).duplicate(true)
	var runtime_backend: Variant = _resolve_runtime_backend()
	if runtime_backend == null or not runtime_backend.has_method(BACKEND_METHOD_LOAD_SCENE_BUNDLE):
		return _failure(
			normalized_request,
			ERROR_BACKEND_UNAVAILABLE,
			"GLTF runtime backend is unavailable. Install aerobeat-vendor-godot-gltf and expose %s()." % BACKEND_METHOD_LOAD_SCENE_BUNDLE,
			true,
			{
				"backend_contract": get_backend_contract(),
			}
		)

	var runtime_result_variant: Variant = runtime_backend.call(BACKEND_METHOD_LOAD_SCENE_BUNDLE, normalized_request.duplicate(true))
	if not (runtime_result_variant is Dictionary):
		return _failure(
			normalized_request,
			ERROR_BACKEND_FAILED,
			"GLTF runtime backend returned a non-Dictionary result.",
			false
		)

	var runtime_result: Dictionary = Dictionary(runtime_result_variant)
	if not bool(runtime_result.get("ok", false)):
		return _failure(
			normalized_request,
			String(runtime_result.get("error_code", ERROR_BACKEND_FAILED)),
			String(runtime_result.get("message", "GLTF runtime backend failed to load the scene bundle.")),
			bool(runtime_result.get("recoverable", true)),
			_dictionary_or_empty(runtime_result.get("details", {}))
		)

	var scene_root: Variant = runtime_result.get("scene_root", runtime_result.get("scene", null))
	return {
		"ok": true,
		"asset_path": String(runtime_result.get("asset_path", normalized_request.get("asset_path", ""))),
		"absolute_path": String(runtime_result.get("absolute_path", "")),
		"resource_path": String(runtime_result.get("resource_path", "")),
		"format": String(runtime_result.get("format", normalized_request.get("format", ""))),
		"container": String(runtime_result.get("container", normalized_request.get("container", ""))),
		"scene_root": scene_root,
		"packed_scene": runtime_result.get("packed_scene", null),
		"warnings": _array_or_empty(runtime_result.get("warnings", [])),
		"details": _dictionary_or_empty(runtime_result.get("details", {})),
	}

func _resolve_runtime_backend() -> Variant:
	if _runtime_backend != null and _runtime_backend.has_method(BACKEND_METHOD_LOAD_SCENE_BUNDLE):
		return _runtime_backend

	for global_class_name in DEFAULT_BACKEND_CLASS_NAMES:
		var backend_from_global: Variant = _instantiate_global_class(String(global_class_name))
		if backend_from_global != null and backend_from_global.has_method(BACKEND_METHOD_LOAD_SCENE_BUNDLE):
			_runtime_backend = backend_from_global
			return _runtime_backend

	for script_path in DEFAULT_BACKEND_SCRIPT_PATHS:
		var backend_from_path: Variant = _instantiate_script(String(script_path))
		if backend_from_path != null and backend_from_path.has_method(BACKEND_METHOD_LOAD_SCENE_BUNDLE):
			_runtime_backend = backend_from_path
			return _runtime_backend

	return null

func _instantiate_global_class(global_class_name: String) -> Variant:
	var global_classes: Array = ProjectSettings.get_global_class_list()
	for entry_variant in global_classes:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant
		if String(entry.get("class", "")) != global_class_name:
			continue
		return _instantiate_script(String(entry.get("path", "")))
	return null

func _instantiate_script(script_path: String) -> Variant:
	if script_path.is_empty() or not ResourceLoader.exists(script_path):
		return null
	var script_resource: Variant = load(script_path)
	if script_resource == null or not script_resource.has_method("new"):
		return null
	return script_resource.new()

func _container_from_asset_path(asset_path: String) -> String:
	var extension := asset_path.get_extension().strip_edges().to_lower()
	if extension == "glb":
		return "glb"
	if extension == "gltf":
		return "gltf"
	return ""

func _normalize_container(container: String) -> String:
	return container.strip_edges().trim_prefix(".").to_lower()

func _dictionary_or_empty(value: Variant) -> Dictionary:
	if value is Dictionary:
		return Dictionary(value).duplicate(true)
	return {}

func _array_or_empty(value: Variant) -> Array:
	if value is Array:
		return Array(value).duplicate(true)
	return []

func _failure(request: Dictionary, error_code: String, message: String, recoverable: bool = true, details: Dictionary = {}) -> Dictionary:
	return {
		"ok": false,
		"request": request.duplicate(true),
		"error_code": error_code,
		"message": message,
		"recoverable": recoverable,
		"details": details.duplicate(true),
	}
