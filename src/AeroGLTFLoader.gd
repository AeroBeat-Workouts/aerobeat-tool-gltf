## Consumer-facing GLTF/GLB facade for AeroBeat tool-side callers.
##
## This surface intentionally hides Godot runtime/import details behind the
## vendor repo so higher-level consumers can ask for a scene bundle without
## owning `GLTFDocument`, importer, URL transport, or resource-pipeline
## branching themselves.
class_name AeroGLTFLoader
extends RefCounted

const VERSION: String = "0.3.0"

const ERROR_INVALID_REQUEST := "invalid_request"
const ERROR_UNSUPPORTED_FORMAT := "unsupported_format"
const ERROR_BACKEND_UNAVAILABLE := "backend_unavailable"
const ERROR_BACKEND_FAILED := "backend_failed"

const SUPPORTED_CONTAINERS := ["gltf", "glb"]
const DEFAULT_BACKEND_CLASS_NAMES := [
	"AeroVendorGodotGLTFBackendAdapter",
	"AeroVendorGodotGLTF",
	"AeroVendorGodotGLTFManager",
]
const DEFAULT_BACKEND_SCRIPT_PATHS := [
	"res://src/AeroVendorGodotGLTFBackendAdapter.gd",
	"res://addons/aerobeat-tool-gltf-loader/src/AeroVendorGodotGLTFBackendAdapter.gd",
	"res://addons/aerobeat-vendor-godot-gltf/src/AeroVendorGodotGLTF.gd",
	"res://addons/aerobeat-vendor-godot-gltf/src/AeroVendorGodotGLTFManager.gd",
]
const BACKEND_METHOD_LOAD_SCENE_BUNDLE := "load_scene_bundle"
const BACKEND_METHOD_LOAD_SCENE_INSTANCE_BUNDLE := "load_scene_instance_bundle"
const BACKEND_METHOD_LOAD_SCENE_BUNDLES := "load_scene_bundles"
const BACKEND_METHOD_UNLOAD_RESULT := "unload_result"
const BACKEND_METHOD_UNLOAD_LAST_RESULT := "unload_last_result"

var _runtime_backend: Variant = null
var _last_result: Dictionary = {}

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
		"methods": {
			"scene": BACKEND_METHOD_LOAD_SCENE_BUNDLE,
			"scene_instance": BACKEND_METHOD_LOAD_SCENE_INSTANCE_BUNDLE,
			"scene_collection": BACKEND_METHOD_LOAD_SCENE_BUNDLES,
			"unload_result": BACKEND_METHOD_UNLOAD_RESULT,
			"unload_last_result": BACKEND_METHOD_UNLOAD_LAST_RESULT,
		},
		"request_keys": [
			"asset_path",
			"source",
			"container",
			"format",
			"instantiate",
			"metadata",
			"instance",
			"instances",
			"scene_options",
		],
		"result_keys": [
			"ok",
			"asset_path",
			"source",
			"scene_root",
			"instance_root",
			"loaded_scene_root",
			"instances",
			"packed_scene",
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

func get_default_transform() -> Dictionary:
	return {
		"position": Vector3.ZERO,
		"rotation_degrees": Vector3.ZERO,
		"scale": Vector3.ONE,
	}

func get_default_instance_options() -> Dictionary:
	return {
		"name": "",
		"transform": get_default_transform(),
		"metadata": {},
	}

func build_scene_request(asset_path: String, options: Dictionary = {}) -> Dictionary:
	var request := options.duplicate(true)
	request["asset_path"] = asset_path
	return normalize_scene_request(request)

func build_scene_request_from_source(source: Dictionary, options: Dictionary = {}) -> Dictionary:
	var request := options.duplicate(true)
	request["source"] = source.duplicate(true)
	return normalize_scene_request(request)

func build_scene_instance_request(asset_path: String, options: Dictionary = {}) -> Dictionary:
	var request := options.duplicate(true)
	request["asset_path"] = asset_path
	return normalize_scene_instance_request(request)

func build_scene_collection_request(instances: Array, options: Dictionary = {}) -> Dictionary:
	var request := options.duplicate(true)
	request["instances"] = instances.duplicate(true)
	return normalize_scene_collection_request(request)

func normalize_scene_request(request: Dictionary) -> Dictionary:
	var normalized_source_result := _normalize_source_request(
		_dictionary_or_empty(request.get("source", {})),
		String(request.get("asset_path", "")).strip_edges(),
		String(request.get("container", request.get("format", request.get("format_hint", "")))).strip_edges()
	)
	if not bool(normalized_source_result.get("ok", false)):
		return normalized_source_result

	var normalized_source: Dictionary = _dictionary_or_empty(normalized_source_result.get("source", {}))
	var normalized_request := {
		"asset_path": String(normalized_source_result.get("asset_path", "")),
		"source": normalized_source,
		"container": String(normalized_source.get("format", "")),
		"format": String(normalized_source.get("format", "")),
		"instantiate": bool(request.get("instantiate", true)),
		"metadata": _dictionary_or_empty(request.get("metadata", {})),
	}
	return {
		"ok": true,
		"request": normalized_request,
	}

func normalize_transform(transform_config: Dictionary) -> Dictionary:
	var normalized := get_default_transform()
	for key in transform_config.keys():
		normalized[key] = transform_config[key]

	normalized["position"] = _variant_to_vector3(normalized.get("position", Vector3.ZERO), Vector3.ZERO)
	normalized["rotation_degrees"] = _variant_to_vector3(normalized.get("rotation_degrees", Vector3.ZERO), Vector3.ZERO)
	normalized["scale"] = _variant_to_vector3(normalized.get("scale", Vector3.ONE), Vector3.ONE)
	return normalized

func normalize_instance_options(instance_options: Dictionary) -> Dictionary:
	var normalized := get_default_instance_options()
	for key in instance_options.keys():
		normalized[key] = instance_options[key]

	normalized["name"] = String(normalized.get("name", "")).strip_edges()
	normalized["metadata"] = _dictionary_or_empty(normalized.get("metadata", {}))
	normalized["transform"] = normalize_transform(_dictionary_or_empty(normalized.get("transform", {})))
	return normalized

func normalize_scene_instance_request(request: Dictionary) -> Dictionary:
	var scene_result := normalize_scene_request(request)
	if not bool(scene_result.get("ok", false)):
		return scene_result

	var normalized_request: Dictionary = Dictionary(scene_result.get("request", {})).duplicate(true)
	if not bool(normalized_request.get("instantiate", true)):
		return _failure(
			normalized_request,
			ERROR_INVALID_REQUEST,
			"GLTF scene instance requests require instantiate=true so a transformable parent can be created."
		)

	normalized_request["instance"] = normalize_instance_options(_dictionary_or_empty(request.get("instance", {})))
	normalized_request["scene_options"] = _dictionary_or_empty(request.get("scene_options", {}))
	return {
		"ok": true,
		"request": normalized_request,
	}

func normalize_scene_collection_request(request: Dictionary) -> Dictionary:
	var raw_instances := _array_or_empty(request.get("instances", []))
	if raw_instances.is_empty():
		return _failure({}, ERROR_INVALID_REQUEST, "GLTF scene collection requests require a non-empty instances array.")

	var normalized_instances: Array = []
	var validation_details: Array = []
	for index in range(raw_instances.size()):
		var instance_variant: Variant = raw_instances[index]
		if not (instance_variant is Dictionary):
			validation_details.append({
				"index": index,
				"message": "Each GLTF scene collection entry must be a Dictionary.",
			})
			continue

		var instance_request: Dictionary = Dictionary(instance_variant).duplicate(true)
		var normalized_result := normalize_scene_instance_request(instance_request)
		if not bool(normalized_result.get("ok", false)):
			validation_details.append({
				"index": index,
				"error_code": String(normalized_result.get("error_code", ERROR_INVALID_REQUEST)),
				"message": String(normalized_result.get("message", "Invalid GLTF scene collection entry.")),
				"details": _dictionary_or_empty(normalized_result.get("details", {})),
			})
			continue
		normalized_instances.append(Dictionary(normalized_result.get("request", {})).duplicate(true))

	if not validation_details.is_empty():
		return _failure(
			{"instances": raw_instances.duplicate(true)},
			ERROR_INVALID_REQUEST,
			"One or more GLTF scene collection entries were invalid.",
			true,
			{"validation_errors": validation_details.duplicate(true)}
		)

	return {
		"ok": true,
		"request": {
			"instances": normalized_instances,
			"scene_options": _dictionary_or_empty(request.get("scene_options", {})),
			"metadata": _dictionary_or_empty(request.get("metadata", {})),
		},
	}

func load_scene_from_path(asset_path: String, options: Dictionary = {}) -> Dictionary:
	var normalized_result := build_scene_request(asset_path, options)
	if not normalized_result.get("ok", false):
		return normalized_result
	return load_scene(Dictionary(normalized_result.get("request", {})))

func load_scene_from_source(source: Dictionary, options: Dictionary = {}) -> Dictionary:
	var normalized_result := build_scene_request_from_source(source, options)
	if not normalized_result.get("ok", false):
		return normalized_result
	return load_scene(Dictionary(normalized_result.get("request", {})))

func load_scene_instance_from_path(asset_path: String, options: Dictionary = {}) -> Dictionary:
	var normalized_result := build_scene_instance_request(asset_path, options)
	if not normalized_result.get("ok", false):
		return normalized_result
	return load_scene_instance(Dictionary(normalized_result.get("request", {})))

func load_scene_collection(instances: Array, options: Dictionary = {}) -> Dictionary:
	var normalized_result := build_scene_collection_request(instances, options)
	if not normalized_result.get("ok", false):
		return normalized_result
	return load_scene_collection_request(Dictionary(normalized_result.get("request", {})))

func load_scene(request: Dictionary) -> Dictionary:
	var normalized_result := normalize_scene_request(request)
	if not normalized_result.get("ok", false):
		return normalized_result

	var normalized_request: Dictionary = Dictionary(normalized_result.get("request", {})).duplicate(true)
	var runtime_result: Dictionary = _call_backend_dictionary(
		BACKEND_METHOD_LOAD_SCENE_BUNDLE,
		normalized_request,
		"GLTF runtime backend is unavailable. Install aerobeat-vendor-godot-gltf and expose %s()." % BACKEND_METHOD_LOAD_SCENE_BUNDLE
	)
	if not bool(runtime_result.get("ok", false)):
		return runtime_result
	_last_result = _normalize_scene_bundle_result(runtime_result, normalized_request)
	return _last_result

func load_scene_instance(request: Dictionary) -> Dictionary:
	var normalized_result := normalize_scene_instance_request(request)
	if not normalized_result.get("ok", false):
		return normalized_result

	var normalized_request: Dictionary = Dictionary(normalized_result.get("request", {})).duplicate(true)
	var runtime_result: Dictionary = _call_backend_dictionary(
		BACKEND_METHOD_LOAD_SCENE_INSTANCE_BUNDLE,
		normalized_request,
		"GLTF runtime backend is unavailable. Install aerobeat-vendor-godot-gltf and expose %s()." % BACKEND_METHOD_LOAD_SCENE_INSTANCE_BUNDLE
	)
	if not bool(runtime_result.get("ok", false)):
		return runtime_result
	_last_result = _normalize_scene_instance_bundle_result(runtime_result, normalized_request)
	return _last_result

func load_scene_collection_request(request: Dictionary) -> Dictionary:
	var normalized_result := normalize_scene_collection_request(request)
	if not normalized_result.get("ok", false):
		return normalized_result

	var normalized_request: Dictionary = Dictionary(normalized_result.get("request", {})).duplicate(true)
	var runtime_result: Dictionary = _call_backend_dictionary(
		BACKEND_METHOD_LOAD_SCENE_BUNDLES,
		normalized_request,
		"GLTF runtime backend is unavailable. Install aerobeat-vendor-godot-gltf and expose %s()." % BACKEND_METHOD_LOAD_SCENE_BUNDLES
	)
	if not bool(runtime_result.get("ok", false)):
		return runtime_result
	_last_result = _normalize_scene_collection_result(runtime_result, normalized_request)
	return _last_result

func unload_result(result: Dictionary) -> Dictionary:
	var runtime_backend: Variant = _resolve_runtime_backend()
	if runtime_backend != null and runtime_backend.has_method(BACKEND_METHOD_UNLOAD_RESULT):
		var backend_result: Variant = runtime_backend.call(BACKEND_METHOD_UNLOAD_RESULT, result.duplicate(true))
		if backend_result is Dictionary:
			_last_result = {}
			return Dictionary(backend_result)
	return _unload_locally(result)

func unload_last_result() -> Dictionary:
	var runtime_backend: Variant = _resolve_runtime_backend()
	if runtime_backend != null and runtime_backend.has_method(BACKEND_METHOD_UNLOAD_LAST_RESULT):
		var backend_result: Variant = runtime_backend.call(BACKEND_METHOD_UNLOAD_LAST_RESULT)
		if backend_result is Dictionary:
			_last_result = {}
			return Dictionary(backend_result)
	var local_result := _unload_locally(_last_result)
	_last_result = {}
	return local_result

func get_last_result() -> Dictionary:
	return _last_result.duplicate(true)

func _call_backend_dictionary(method_name: String, normalized_request: Dictionary, unavailable_message: String) -> Dictionary:
	var runtime_backend: Variant = _resolve_runtime_backend()
	if runtime_backend == null or not runtime_backend.has_method(method_name):
		return _failure(
			normalized_request,
			ERROR_BACKEND_UNAVAILABLE,
			unavailable_message,
			true,
			{
				"backend_contract": get_backend_contract(),
			}
		)

	var runtime_result_variant: Variant = runtime_backend.call(method_name, normalized_request.duplicate(true))
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
	return runtime_result

func _normalize_scene_bundle_result(runtime_result: Dictionary, normalized_request: Dictionary) -> Dictionary:
	var scene_root: Variant = runtime_result.get("scene_root", runtime_result.get("scene", null))
	return {
		"ok": true,
		"asset_path": String(runtime_result.get("asset_path", normalized_request.get("asset_path", ""))),
		"source": _dictionary_or_empty(runtime_result.get("source", normalized_request.get("source", {}))),
		"absolute_path": String(runtime_result.get("absolute_path", "")),
		"resource_path": String(runtime_result.get("resource_path", "")),
		"format": String(runtime_result.get("format", normalized_request.get("format", ""))),
		"container": String(runtime_result.get("container", normalized_request.get("container", ""))),
		"scene_root": scene_root,
		"packed_scene": runtime_result.get("packed_scene", null),
		"warnings": _array_or_empty(runtime_result.get("warnings", [])),
		"details": _dictionary_or_empty(runtime_result.get("details", {})),
	}

func _normalize_scene_instance_bundle_result(runtime_result: Dictionary, normalized_request: Dictionary) -> Dictionary:
	var scene_root: Variant = runtime_result.get("scene_root", runtime_result.get("scene", null))
	var instance_root: Variant = runtime_result.get("instance_root", scene_root)
	return {
		"ok": true,
		"asset_path": String(runtime_result.get("asset_path", normalized_request.get("asset_path", ""))),
		"source": _dictionary_or_empty(runtime_result.get("source", normalized_request.get("source", {}))),
		"absolute_path": String(runtime_result.get("absolute_path", "")),
		"resource_path": String(runtime_result.get("resource_path", "")),
		"format": String(runtime_result.get("format", normalized_request.get("format", ""))),
		"container": String(runtime_result.get("container", normalized_request.get("container", ""))),
		"scene_root": scene_root,
		"instance_root": instance_root,
		"loaded_scene_root": runtime_result.get("loaded_scene_root", runtime_result.get("loaded_scene", null)),
		"packed_scene": runtime_result.get("packed_scene", null),
		"warnings": _array_or_empty(runtime_result.get("warnings", [])),
		"details": _dictionary_or_empty(runtime_result.get("details", {})),
	}

func _normalize_scene_collection_result(runtime_result: Dictionary, normalized_request: Dictionary) -> Dictionary:
	var normalized_instances: Array = []
	var runtime_instances := _array_or_empty(runtime_result.get("instances", []))
	var request_instances := _array_or_empty(normalized_request.get("instances", []))
	for index in range(runtime_instances.size()):
		var runtime_instance_variant: Variant = runtime_instances[index]
		if not (runtime_instance_variant is Dictionary):
			continue
		var runtime_instance: Dictionary = Dictionary(runtime_instance_variant)
		var requested_instance: Dictionary = {}
		if index < request_instances.size() and request_instances[index] is Dictionary:
			requested_instance = Dictionary(request_instances[index])
		normalized_instances.append({
			"asset_path": String(runtime_instance.get("asset_path", requested_instance.get("asset_path", ""))),
			"source": _dictionary_or_empty(runtime_instance.get("source", requested_instance.get("source", {}))),
			"absolute_path": String(runtime_instance.get("absolute_path", "")),
			"resource_path": String(runtime_instance.get("resource_path", "")),
			"format": String(runtime_instance.get("format", requested_instance.get("format", ""))),
			"container": String(runtime_instance.get("container", requested_instance.get("container", ""))),
			"scene_root": runtime_instance.get("scene_root", runtime_instance.get("instance_root", null)),
			"instance_root": runtime_instance.get("instance_root", runtime_instance.get("scene_root", null)),
			"loaded_scene_root": runtime_instance.get("loaded_scene_root", runtime_instance.get("loaded_scene", null)),
			"warnings": _array_or_empty(runtime_instance.get("warnings", [])),
			"details": _dictionary_or_empty(runtime_instance.get("details", {})),
		})

	return {
		"ok": true,
		"scene_root": runtime_result.get("scene_root", runtime_result.get("scene", null)),
		"instances": normalized_instances,
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

func _normalize_source_request(source: Dictionary, asset_path: String, container_hint: String) -> Dictionary:
	var normalized_source := source.duplicate(true)
	var hinted_container := _normalize_container(container_hint)
	var path := String(normalized_source.get("path", asset_path)).strip_edges()
	var url := String(normalized_source.get("url", asset_path if _is_http_url(asset_path) else "")).strip_edges()
	var source_kind := String(normalized_source.get("kind", "")).strip_edges().to_lower()
	if source_kind.is_empty():
		source_kind = "url" if (not url.is_empty() or _is_http_url(path)) else "file"

	if source_kind == "url":
		if url.is_empty():
			url = path
		path = url
	else:
		url = ""

	var container := hinted_container
	if container.is_empty():
		container = _container_from_asset_path(url if source_kind == "url" else path)
	if not supports_container(container):
		return _failure(
			{"asset_path": asset_path, "source": source.duplicate(true)},
			ERROR_UNSUPPORTED_FORMAT,
			"Unsupported GLTF container for source '%s'. Supported containers: %s" % [
				(url if source_kind == "url" else path),
				", ".join(PackedStringArray(SUPPORTED_CONTAINERS)),
			]
		)

	var normalized_request_source := {
		"kind": source_kind,
		"path": path if source_kind != "url" else "",
		"url": url if source_kind == "url" else "",
		"format": container,
		"metadata": _dictionary_or_empty(normalized_source.get("metadata", {})),
	}
	var normalized_asset_path := url if source_kind == "url" else path
	if normalized_asset_path.is_empty():
		return _failure({}, ERROR_INVALID_REQUEST, "GLTF/GLB requests require a non-empty asset path or source.")

	return {
		"ok": true,
		"asset_path": normalized_asset_path,
		"source": normalized_request_source,
	}

func _container_from_asset_path(asset_path: String) -> String:
	var path_without_fragment := asset_path
	var fragment_index := path_without_fragment.find("#")
	if fragment_index != -1:
		path_without_fragment = path_without_fragment.substr(0, fragment_index)
	var path_without_query := path_without_fragment
	var query_index := path_without_query.find("?")
	if query_index != -1:
		path_without_query = path_without_query.substr(0, query_index)
	var extension := path_without_query.get_extension().strip_edges().to_lower()
	if extension == "glb":
		return "glb"
	if extension == "gltf":
		return "gltf"
	return ""

func _normalize_container(container: String) -> String:
	return container.strip_edges().trim_prefix(".").to_lower()

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

func _variant_to_vector3(value: Variant, default_value: Vector3) -> Vector3:
	if value is Vector3:
		return value
	if value is Array:
		var array_value: Array = value
		if array_value.size() >= 3:
			return Vector3(float(array_value[0]), float(array_value[1]), float(array_value[2]))
	if value is Dictionary:
		var dictionary_value: Dictionary = value
		return Vector3(
			float(dictionary_value.get("x", default_value.x)),
			float(dictionary_value.get("y", default_value.y)),
			float(dictionary_value.get("z", default_value.z))
		)
	return default_value

func _unload_locally(result: Dictionary) -> Dictionary:
	var scene_root := result.get("scene_root", result.get("instance_root", null)) as Node
	var freed_roots := 0
	if scene_root != null and is_instance_valid(scene_root):
		if scene_root.get_parent() != null:
			scene_root.get_parent().remove_child(scene_root)
		scene_root.queue_free()
		freed_roots += 1
	return {
		"ok": true,
		"unloaded": freed_roots > 0,
		"freed_roots": freed_roots,
	}

func _failure(request: Dictionary, error_code: String, message: String, recoverable: bool = true, details: Dictionary = {}) -> Dictionary:
	return {
		"ok": false,
		"request": request.duplicate(true),
		"error_code": error_code,
		"message": message,
		"recoverable": recoverable,
		"details": details.duplicate(true),
	}
