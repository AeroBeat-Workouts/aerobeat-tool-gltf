extends GutTest

const PACKAGED_FIXTURE_PATH := "res://assets/models/alien-planet.glb"
const EXTERNAL_FIXTURE_DIR := "user://gltf-fixtures"
const EXTERNAL_FIXTURE_PATH := "user://gltf-fixtures/alien-planet.glb"

class FakeRuntimeBackend:
	extends RefCounted

	var last_scene_request: Dictionary = {}
	var last_instance_request: Dictionary = {}
	var last_collection_request: Dictionary = {}
	var last_unload_result_request: Dictionary = {}
	var unload_last_result_called := false
	var _next_scene_result: Dictionary = {}
	var _next_instance_result: Dictionary = {}
	var _next_collection_result: Dictionary = {}
	var _next_unload_result: Dictionary = {"ok": true, "unloaded": true, "freed_roots": 1}
	var _next_unload_last_result: Dictionary = {"ok": true, "unloaded": true, "freed_roots": 1}

	func _init(scene_result: Dictionary = {}, instance_result: Dictionary = {}, collection_result: Dictionary = {}) -> void:
		_next_scene_result = scene_result
		_next_instance_result = instance_result if not instance_result.is_empty() else scene_result
		_next_collection_result = collection_result if not collection_result.is_empty() else scene_result

	func load_scene_bundle(request: Dictionary) -> Dictionary:
		last_scene_request = request.duplicate(true)
		return _next_scene_result

	func load_scene_instance_bundle(request: Dictionary) -> Dictionary:
		last_instance_request = request.duplicate(true)
		return _next_instance_result

	func load_scene_bundles(request: Dictionary) -> Dictionary:
		last_collection_request = request.duplicate(true)
		return _next_collection_result

	func unload_result(result: Dictionary) -> Dictionary:
		last_unload_result_request = result.duplicate(true)
		return _next_unload_result

	func unload_last_result() -> Dictionary:
		unload_last_result_called = true
		return _next_unload_last_result

func before_all() -> void:
	assert_true(FileAccess.file_exists(PACKAGED_FIXTURE_PATH), "Packaged GLB fixture should exist in the tool testbed")

func after_each() -> void:
	_cleanup_external_fixture_dir()

func test_repo_identity_is_gltf_specific() -> void:
	var tool := AeroGLTFLoader.new()
	assert_eq(AeroGLTFLoader.VERSION, "0.3.0", "Facade version should reflect renamed facade + source selection support")
	assert_true(tool.supports_container("glb"), "Facade should explicitly support GLB")
	assert_true(tool.supports_container(".gltf"), "Facade should normalize dotted GLTF format hints")
	assert_false(tool.supports_container("png"), "Facade should reject unrelated container formats")

func test_build_scene_request_normalizes_supported_input() -> void:
	var tool := AeroGLTFLoader.new()
	var result: Dictionary = tool.build_scene_request(" user://packs/environment.GLb ", {
		"metadata": {
			"source": "test",
		},
	})
	assert_true(result.get("ok", false), "GLB path should normalize into a valid request")
	var request := Dictionary(result.get("request", {}))
	assert_eq(String(request.get("asset_path", "")), "user://packs/environment.GLb", "asset_path should be trimmed but otherwise preserved")
	assert_eq(String(request.get("container", "")), "glb", "container should normalize from the extension")
	assert_eq(String(request.get("format", "")), "glb", "format should mirror the container in this slice")
	assert_true(bool(request.get("instantiate", false)), "instantiate should default to true")
	assert_eq(String(Dictionary(request.get("metadata", {})).get("source", "")), "test", "metadata should round-trip")

func test_build_scene_request_accepts_url_sources() -> void:
	var tool := AeroGLTFLoader.new()
	var result: Dictionary = tool.build_scene_request_from_source({
		"url": "https://example.com/models/environment.glb?cache=1",
	})
	assert_true(result.get("ok", false), "GLB URLs should normalize into a valid request")
	var request := Dictionary(result.get("request", {}))
	assert_eq(String(request.get("asset_path", "")), "https://example.com/models/environment.glb?cache=1")
	assert_eq(String(Dictionary(request.get("source", {})).get("kind", "")), "url")
	assert_eq(String(Dictionary(request.get("source", {})).get("format", "")), "glb")

func test_build_scene_instance_request_normalizes_transform_vectors() -> void:
	var tool := AeroGLTFLoader.new()
	var result: Dictionary = tool.build_scene_instance_request(PACKAGED_FIXTURE_PATH, {
		"instance": {
			"name": "PlanetLeft",
			"transform": {
				"position": [1, 2, 3],
				"rotation_degrees": {"x": 10, "y": 20, "z": 30},
				"scale": [0.5, 0.75, 1.25],
			},
		},
	})
	assert_true(result.get("ok", false), "GLTF scene-instance request should normalize a valid packaged fixture")
	var instance_request := Dictionary(Dictionary(result.get("request", {})).get("instance", {}))
	assert_eq(String(instance_request.get("name", "")), "PlanetLeft")
	var instance_transform := Dictionary(instance_request.get("transform", {}))
	assert_eq(instance_transform.get("position", Vector3.ZERO), Vector3(1, 2, 3))
	assert_eq(instance_transform.get("rotation_degrees", Vector3.ZERO), Vector3(10, 20, 30))
	assert_eq(instance_transform.get("scale", Vector3.ONE), Vector3(0.5, 0.75, 1.25))

func test_build_scene_request_rejects_unsupported_formats() -> void:
	var tool := AeroGLTFLoader.new()
	var result: Dictionary = tool.build_scene_request("user://packs/environment.usdz")
	assert_false(result.get("ok", true), "Unsupported formats should fail early")
	assert_eq(String(result.get("error_code", "")), AeroGLTFLoader.ERROR_UNSUPPORTED_FORMAT, "Unsupported formats should report the facade error code")

func test_build_scene_collection_request_rejects_invalid_entries() -> void:
	var tool := AeroGLTFLoader.new()
	var result: Dictionary = tool.build_scene_collection_request([
		{"asset_path": PACKAGED_FIXTURE_PATH},
		{"asset_path": ""},
	])
	assert_false(result.get("ok", true), "Scene collection validation should reject invalid entries")
	assert_eq(String(result.get("error_code", "")), AeroGLTFLoader.ERROR_INVALID_REQUEST)
	assert_eq(Array(Dictionary(result.get("details", {})).get("validation_errors", [])).size(), 1, "Validation details should identify the failing entry")

func test_load_scene_delegates_to_runtime_backend_and_returns_scene_bundle() -> void:
	var tool := AeroGLTFLoader.new()
	var scene_root := Node3D.new()
	var runtime_backend = FakeRuntimeBackend.new({
		"ok": true,
		"asset_path": "user://packs/environment.glb",
		"absolute_path": "/tmp/environment.glb",
		"resource_path": "res://imports/environment.glb",
		"format": "glb",
		"container": "glb",
		"scene_root": scene_root,
		"warnings": ["used imported fallback"],
		"details": {
			"loader": "fake",
		},
	})
	tool.set_runtime_backend(runtime_backend)

	var result: Dictionary = tool.load_scene_from_path("user://packs/environment.glb", {
		"metadata": {
			"consumer": "environment-loader",
		},
	})

	assert_true(result.get("ok", false), "Backend success should surface as facade success")
	assert_eq(String(Dictionary(runtime_backend.last_scene_request).get("asset_path", "")), "user://packs/environment.glb", "Facade should forward the normalized asset path")
	assert_eq(String(Dictionary(runtime_backend.last_scene_request).get("container", "")), "glb", "Facade should forward the normalized container")
	assert_eq(String(Dictionary(Dictionary(runtime_backend.last_scene_request).get("metadata", {})).get("consumer", "")), "environment-loader", "Facade should forward metadata")
	assert_same(result.get("scene_root", null), scene_root, "Facade should return the instantiated scene root without re-wrapping it")
	assert_eq(String(Dictionary(result.get("details", {})).get("loader", "")), "fake", "Facade should preserve backend details")
	assert_eq(Array(result.get("warnings", []))[0], "used imported fallback", "Facade should preserve backend warnings")
	scene_root.free()

func test_load_scene_instance_delegates_transform_bundle_to_runtime_backend() -> void:
	var tool := AeroGLTFLoader.new()
	var instance_root := Node3D.new()
	instance_root.name = "PlanetAnchor"
	var loaded_scene := Node3D.new()
	loaded_scene.name = "ImportedPlanet"
	instance_root.add_child(loaded_scene)
	var runtime_backend = FakeRuntimeBackend.new(
		{},
		{
			"ok": true,
			"asset_path": PACKAGED_FIXTURE_PATH,
			"absolute_path": ProjectSettings.globalize_path(PACKAGED_FIXTURE_PATH),
			"resource_path": PACKAGED_FIXTURE_PATH,
			"format": "glb",
			"container": "glb",
			"scene_root": instance_root,
			"instance_root": instance_root,
			"loaded_scene_root": loaded_scene,
			"details": {"backend": "fake-instance"},
		},
	)
	tool.set_runtime_backend(runtime_backend)

	var result: Dictionary = tool.load_scene_instance_from_path(PACKAGED_FIXTURE_PATH, {
		"instance": {
			"name": "PlanetAnchor",
			"transform": {
				"position": [1, 2, 3],
				"rotation_degrees": [0, 45, 0],
				"scale": [0.5, 0.5, 0.5],
			},
		},
		"scene_options": {
			"bake_fps": 24.0,
		},
	})

	assert_true(result.get("ok", false), "Instance backend success should surface as facade success")
	var last_instance_request := Dictionary(runtime_backend.last_instance_request)
	var last_instance_options := Dictionary(last_instance_request.get("instance", {}))
	assert_eq(String(last_instance_options.get("name", "")), "PlanetAnchor")
	assert_eq(Dictionary(last_instance_options.get("transform", {})).get("position", Vector3.ZERO), Vector3(1, 2, 3))
	assert_eq(float(Dictionary(last_instance_request.get("scene_options", {})).get("bake_fps", 0.0)), 24.0)
	assert_same(result.get("scene_root", null), instance_root)
	assert_same(result.get("instance_root", null), instance_root)
	assert_same(result.get("loaded_scene_root", null), loaded_scene)
	assert_eq(String(Dictionary(result.get("details", {})).get("backend", "")), "fake-instance")
	instance_root.free()

func test_load_scene_collection_delegates_multiple_instances_and_preserves_independence() -> void:
	var tool := AeroGLTFLoader.new()
	var aggregate_root := Node3D.new()
	aggregate_root.name = "CollectionRoot"
	var left_root := Node3D.new()
	left_root.name = "LeftAnchor"
	var right_root := Node3D.new()
	right_root.name = "RightAnchor"
	aggregate_root.add_child(left_root)
	aggregate_root.add_child(right_root)
	var runtime_backend = FakeRuntimeBackend.new(
		{},
		{},
		{
			"ok": true,
			"scene_root": aggregate_root,
			"instances": [
				{
					"asset_path": PACKAGED_FIXTURE_PATH,
					"absolute_path": ProjectSettings.globalize_path(PACKAGED_FIXTURE_PATH),
					"resource_path": PACKAGED_FIXTURE_PATH,
					"format": "glb",
					"container": "glb",
					"scene_root": left_root,
					"instance_root": left_root,
					"details": {"side": "left"},
				},
				{
					"asset_path": PACKAGED_FIXTURE_PATH,
					"absolute_path": ProjectSettings.globalize_path(PACKAGED_FIXTURE_PATH),
					"resource_path": PACKAGED_FIXTURE_PATH,
					"format": "glb",
					"container": "glb",
					"scene_root": right_root,
					"instance_root": right_root,
					"details": {"side": "right"},
				},
			],
			"details": {"root_name": "CollectionRoot"},
		},
	)
	tool.set_runtime_backend(runtime_backend)

	var result: Dictionary = tool.load_scene_collection([
		{
			"asset_path": PACKAGED_FIXTURE_PATH,
			"instance": {"name": "LeftAnchor", "transform": {"position": [-2, 0, 0]}},
		},
		{
			"asset_path": PACKAGED_FIXTURE_PATH,
			"instance": {"name": "RightAnchor", "transform": {"position": [2, 0, 0], "scale": [1.5, 1.5, 1.5]}},
		},
	], {"scene_options": {"root_name": "CollectionRoot"}})

	assert_true(result.get("ok", false), "Collection backend success should surface as facade success")
	var last_collection_request := Dictionary(runtime_backend.last_collection_request)
	var last_collection_instances := Array(last_collection_request.get("instances", []))
	assert_eq(last_collection_instances.size(), 2, "Facade should pass both normalized scene requests")
	assert_eq(String(Dictionary(Dictionary(last_collection_instances[0]).get("instance", {})).get("name", "")), "LeftAnchor")
	assert_eq(Dictionary(Dictionary(Dictionary(last_collection_instances[1]).get("instance", {})).get("transform", {})).get("scale", Vector3.ONE), Vector3(1.5, 1.5, 1.5))
	assert_same(result.get("scene_root", null), aggregate_root)
	var collection_instances := Array(result.get("instances", []))
	assert_eq(collection_instances.size(), 2)
	assert_same(Dictionary(collection_instances[0]).get("instance_root", null), left_root)
	assert_same(Dictionary(collection_instances[1]).get("instance_root", null), right_root)
	assert_ne(Dictionary(collection_instances[0]).get("instance_root", null), Dictionary(collection_instances[1]).get("instance_root", null), "Each collection entry should preserve its own instance root")
	assert_eq(String(Dictionary(result.get("details", {})).get("root_name", "")), "CollectionRoot")
	aggregate_root.free()

func test_unload_result_delegates_to_runtime_backend() -> void:
	var tool := AeroGLTFLoader.new()
	var scene_root := Node3D.new()
	var runtime_backend = FakeRuntimeBackend.new()
	tool.set_runtime_backend(runtime_backend)

	var result := tool.unload_result({
		"scene_root": scene_root,
		"details": {"vendor": {"scene": scene_root}},
	})
	assert_true(result.get("ok", false), "Facade should surface backend unload success")
	assert_true(bool(result.get("unloaded", false)), "Facade should preserve unload state")
	assert_eq(int(result.get("freed_roots", 0)), 1)
	assert_same(Dictionary(runtime_backend.last_unload_result_request).get("scene_root", null), scene_root)
	scene_root.free()

func test_unload_last_result_delegates_to_runtime_backend() -> void:
	var tool := AeroGLTFLoader.new()
	var runtime_backend = FakeRuntimeBackend.new()
	tool.set_runtime_backend(runtime_backend)

	var result := tool.unload_last_result()
	assert_true(result.get("ok", false), "Facade should surface backend unload-last success")
	assert_true(runtime_backend.unload_last_result_called, "Facade should ask the backend to unload its last result")

func test_load_scene_reports_backend_failure_cleanly() -> void:
	var tool := AeroGLTFLoader.new()
	tool.set_runtime_backend(FakeRuntimeBackend.new({
		"ok": false,
		"error_code": "vendor_requires_imported_resource",
		"message": "GLB is local but not importable by the current resource pipeline.",
		"recoverable": true,
		"details": {
			"resource_path": "",
		},
	}))

	var result: Dictionary = tool.load_scene_from_path("/tmp/environment.glb")
	assert_false(result.get("ok", true), "Backend failure should surface without consumers touching runtime specifics")
	assert_eq(String(result.get("error_code", "")), "vendor_requires_imported_resource", "Facade should preserve backend-specific error codes for higher-level mapping")
	assert_true(bool(result.get("recoverable", false)), "Facade should preserve recoverability")
	assert_eq(String(Dictionary(result.get("details", {})).get("resource_path", "")), "", "Facade should preserve backend details for higher-level error mapping")

func test_load_scene_from_packaged_glb_fixture_uses_default_vendor_adapter() -> void:
	var tool := AeroGLTFLoader.new()
	tool.clear_runtime_backend()

	var result: Dictionary = tool.load_scene_from_path(PACKAGED_FIXTURE_PATH)

	assert_true(result.get("ok", false), "Facade should load the packaged GLB fixture through the default vendor adapter")
	if not bool(result.get("ok", false)):
		return
	assert_eq(result.get("asset_path", ""), PACKAGED_FIXTURE_PATH, "Facade should preserve the packaged request path")
	assert_eq(result.get("resource_path", ""), PACKAGED_FIXTURE_PATH, "Packaged GLB should round-trip as a resource path")
	assert_eq(result.get("format", ""), "glb", "Packaged fixture should resolve as GLB")
	assert_true(result.get("scene_root", null) is Node, "Packaged GLB load should produce a scene root")
	assert_true(Dictionary(result.get("details", {})).has("vendor"), "Facade should expose vendor details for debugging")
	var scene_root: Variant = result.get("scene_root", null)
	if scene_root != null:
		scene_root.free()

func test_load_scene_instance_from_packaged_glb_fixture_uses_default_vendor_adapter() -> void:
	var tool := AeroGLTFLoader.new()
	tool.clear_runtime_backend()

	var result: Dictionary = tool.load_scene_instance_from_path(PACKAGED_FIXTURE_PATH, {
		"instance": {
			"name": "PlanetAnchor",
			"transform": {
				"position": [1.0, 0.5, 0.0],
				"rotation_degrees": [0.0, 30.0, 0.0],
				"scale": [0.75, 0.75, 0.75],
			},
		},
	})

	assert_true(result.get("ok", false), "Facade should wrap the packaged GLB fixture in a transformable instance root")
	if not bool(result.get("ok", false)):
		return
	var instance_root := result.get("instance_root", null) as Node3D
	assert_true(instance_root != null, "Instance load should surface a Node3D instance root")
	assert_eq(instance_root.name, "PlanetAnchor")
	assert_eq(instance_root.position, Vector3(1.0, 0.5, 0.0))
	assert_eq(instance_root.rotation_degrees, Vector3(0.0, 30.0, 0.0))
	assert_eq(instance_root.scale, Vector3(0.75, 0.75, 0.75))
	assert_eq(instance_root.get_child_count(), 1, "Wrapped instance root should own the loaded GLTF scene")
	instance_root.free()

func test_load_scene_collection_from_packaged_glb_fixture_uses_default_vendor_adapter() -> void:
	var tool := AeroGLTFLoader.new()
	tool.clear_runtime_backend()

	var result: Dictionary = tool.load_scene_collection([
		{
			"asset_path": PACKAGED_FIXTURE_PATH,
			"instance": {
				"name": "PlanetLeft",
				"transform": {
					"position": [-2.0, 0.0, 0.0],
					"rotation_degrees": [0.0, -20.0, 0.0],
				},
			},
		},
		{
			"asset_path": PACKAGED_FIXTURE_PATH,
			"instance": {
				"name": "PlanetRight",
				"transform": {
					"position": [2.0, 0.75, 0.0],
					"scale": [1.25, 1.25, 1.25],
				},
			},
		},
	], {"scene_options": {"root_name": "ToolGLTFCollectionRoot"}})

	assert_true(result.get("ok", false), "Facade should load multiple GLTF instances through the default vendor adapter")
	if not bool(result.get("ok", false)):
		return
	var aggregate_root := result.get("scene_root", null) as Node3D
	assert_true(aggregate_root != null, "Collection load should surface an aggregate Node3D root")
	assert_eq(aggregate_root.name, "ToolGLTFCollectionRoot")
	assert_eq(Array(result.get("instances", [])).size(), 2, "Collection result should preserve both instance bundles")
	var left_root := Dictionary(Array(result.get("instances", []))[0]).get("instance_root", null) as Node3D
	var right_root := Dictionary(Array(result.get("instances", []))[1]).get("instance_root", null) as Node3D
	assert_true(left_root != null and right_root != null, "Collection result should include instance roots for both children")
	assert_eq(left_root.name, "PlanetLeft")
	assert_eq(right_root.name, "PlanetRight")
	assert_eq(left_root.position, Vector3(-2.0, 0.0, 0.0))
	assert_eq(right_root.scale, Vector3(1.25, 1.25, 1.25))
	aggregate_root.free()

func test_load_scene_from_external_copied_glb_fixture_uses_default_vendor_adapter() -> void:
	var tool := AeroGLTFLoader.new()
	tool.clear_runtime_backend()
	var external_asset_path := _copy_packaged_fixture_to_external_path()

	var result: Dictionary = tool.load_scene_from_path(external_asset_path, {
		"metadata": {
			"source": "external-copy",
		},
	})

	assert_true(result.get("ok", false), "Facade should load an external copied GLB fixture through the default vendor adapter")
	if not bool(result.get("ok", false)):
		return
	assert_eq(result.get("asset_path", ""), external_asset_path, "Facade should preserve the external request path")
	assert_eq(result.get("absolute_path", ""), external_asset_path, "External GLB should round-trip as an absolute path")
	assert_eq(result.get("resource_path", ""), "", "External GLB should not claim a res:// resource path")
	assert_eq(result.get("format", ""), "glb", "External fixture should resolve as GLB")
	assert_true(result.get("scene_root", null) is Node, "External GLB load should produce a scene root")
	assert_true(Dictionary(result.get("details", {})).has("vendor"), "Facade should expose vendor details for debugging")
	var scene_root: Variant = result.get("scene_root", null)
	if scene_root != null:
		scene_root.free()

func _copy_packaged_fixture_to_external_path() -> String:
	_cleanup_external_fixture_dir()
	var source_absolute := ProjectSettings.globalize_path(PACKAGED_FIXTURE_PATH)
	var external_dir_absolute := ProjectSettings.globalize_path(EXTERNAL_FIXTURE_DIR)
	var make_dir_error := DirAccess.make_dir_recursive_absolute(external_dir_absolute)
	assert_eq(make_dir_error, OK, "Should create the external GLB fixture directory")

	var destination_absolute := ProjectSettings.globalize_path(EXTERNAL_FIXTURE_PATH)
	var copy_error := DirAccess.copy_absolute(source_absolute, destination_absolute)
	assert_eq(copy_error, OK, "Should copy the packaged GLB fixture to an external absolute path")
	assert_true(FileAccess.file_exists(destination_absolute), "Copied external GLB fixture should exist")
	return destination_absolute

func _cleanup_external_fixture_dir() -> void:
	var external_dir_absolute := ProjectSettings.globalize_path(EXTERNAL_FIXTURE_DIR)
	if not DirAccess.dir_exists_absolute(external_dir_absolute):
		return
	_delete_tree_absolute(external_dir_absolute)

func _delete_tree_absolute(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		DirAccess.remove_absolute(path)
		return

	dir.list_dir_begin()
	while true:
		var entry := dir.get_next()
		if entry.is_empty():
			break
		if entry == "." or entry == "..":
			continue
		var child_path := path.path_join(entry)
		if dir.current_is_dir():
			_delete_tree_absolute(child_path)
		else:
			DirAccess.remove_absolute(child_path)
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
