extends GutTest

const PACKAGED_FIXTURE_PATH := "res://fixtures/models/alien-planet.glb"
const EXTERNAL_FIXTURE_DIR := "user://gltf-fixtures"
const EXTERNAL_FIXTURE_PATH := "user://gltf-fixtures/alien-planet.glb"

class FakeRuntimeBackend:
	extends RefCounted

	var last_request: Dictionary = {}
	var _next_result: Dictionary = {}

	func _init(next_result: Dictionary = {}) -> void:
		_next_result = next_result

	func load_scene_bundle(request: Dictionary) -> Dictionary:
		last_request = request.duplicate(true)
		return _next_result

func before_all() -> void:
	assert_true(FileAccess.file_exists(PACKAGED_FIXTURE_PATH), "Packaged GLB fixture should exist in the tool testbed")

func after_each() -> void:
	_cleanup_external_fixture_dir()

func test_repo_identity_is_gltf_specific() -> void:
	var tool := AeroGLTFTool.new()
	assert_eq(AeroGLTFTool.VERSION, "0.1.0", "Facade version should reflect the first real GLTF slice")
	assert_true(tool.supports_container("glb"), "Facade should explicitly support GLB")
	assert_true(tool.supports_container(".gltf"), "Facade should normalize dotted GLTF format hints")
	assert_false(tool.supports_container("png"), "Facade should reject unrelated container formats")

func test_build_scene_request_normalizes_supported_input() -> void:
	var tool := AeroGLTFTool.new()
	var result: Dictionary = tool.build_scene_request(" user://packs/environment.GLb ", {
		"metadata": {
			"source": "test",
		},
	})
	assert_true(result.get("ok", false), "GLB path should normalize into a valid request")
	assert_eq(result.request.asset_path, "user://packs/environment.GLb", "asset_path should be trimmed but otherwise preserved")
	assert_eq(result.request.container, "glb", "container should normalize from the extension")
	assert_eq(result.request.format, "glb", "format should mirror the container in this slice")
	assert_true(result.request.instantiate, "instantiate should default to true")
	assert_eq(result.request.metadata.source, "test", "metadata should round-trip")

func test_build_scene_request_rejects_unsupported_formats() -> void:
	var tool := AeroGLTFTool.new()
	var result: Dictionary = tool.build_scene_request("user://packs/environment.usdz")
	assert_false(result.get("ok", true), "Unsupported formats should fail early")
	assert_eq(result.error_code, AeroGLTFTool.ERROR_UNSUPPORTED_FORMAT, "Unsupported formats should report the facade error code")

func test_load_scene_delegates_to_runtime_backend_and_returns_scene_bundle() -> void:
	var tool := AeroGLTFTool.new()
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
	assert_eq(runtime_backend.last_request.asset_path, "user://packs/environment.glb", "Facade should forward the normalized asset path")
	assert_eq(runtime_backend.last_request.container, "glb", "Facade should forward the normalized container")
	assert_eq(runtime_backend.last_request.metadata.consumer, "environment-loader", "Facade should forward metadata")
	assert_same(result.scene_root, scene_root, "Facade should return the instantiated scene root without re-wrapping it")
	assert_eq(result.details.loader, "fake", "Facade should preserve backend details")
	assert_eq(result.warnings[0], "used imported fallback", "Facade should preserve backend warnings")
	scene_root.free()

func test_load_scene_reports_backend_failure_cleanly() -> void:
	var tool := AeroGLTFTool.new()
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
	assert_eq(result.error_code, "vendor_requires_imported_resource", "Facade should preserve backend-specific error codes for higher-level mapping")
	assert_true(result.recoverable, "Facade should preserve recoverability")
	assert_eq(result.details.resource_path, "", "Facade should preserve backend details for higher-level error mapping")

func test_load_scene_from_packaged_glb_fixture_uses_default_vendor_adapter() -> void:
	var tool := AeroGLTFTool.new()
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

func test_load_scene_from_external_copied_glb_fixture_uses_default_vendor_adapter() -> void:
	var tool := AeroGLTFTool.new()
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
