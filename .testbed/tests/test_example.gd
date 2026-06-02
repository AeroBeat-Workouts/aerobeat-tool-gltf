extends GutTest

const README_PATH := "../README.md"
const PLUGIN_CFG_PATH := "../plugin.cfg"
const ADDONS_MANIFEST_PATH := "addons.jsonc"
const EXPECTED_PLUGIN_DESCRIPTION := "Consumer-facing GLTF/GLB facade for AeroBeat tools. Delegates Godot runtime loading details to aerobeat-vendor-godot-gltf."

func _read_repo_file(relative_path: String) -> String:
	var absolute_path := ProjectSettings.globalize_path("res://%s" % relative_path)
	assert_true(FileAccess.file_exists(absolute_path), "Expected repo file to exist: %s" % absolute_path)
	var file := FileAccess.open(absolute_path, FileAccess.READ)
	assert_true(file != null, "Expected repo file to open: %s" % absolute_path)
	return file.get_as_text()

func test_readme_describes_vendor_to_tool_to_consumer_stack() -> void:
	var readme_text := _read_repo_file(README_PATH)
	assert_true(readme_text.contains("Consumer-facing **GLTF/GLB facade**"), "README should describe the repo as a GLTF/GLB facade")
	assert_true(readme_text.contains("aerobeat-vendor-godot-gltf"), "README should point at the vendor runtime repo")
	assert_true(readme_text.contains("aerobeat-environment-loader"), "README should describe the intended consumer seam")
	assert_true(readme_text.contains("load_scene_instances(instances, flags := 0, scene_options := {}) -> Dictionary"), "README should document the vendor multi-instance contract")
	assert_true(readme_text.contains("Tool GLTF multi-instance proving surface"), "README should call out the tool-facing proving surface")

func test_plugin_cfg_matches_gltf_facade_identity() -> void:
	var config := ConfigFile.new()
	var error := config.load(ProjectSettings.globalize_path("res://%s" % PLUGIN_CFG_PATH))
	assert_eq(error, OK, "plugin.cfg should parse cleanly")
	assert_eq(config.get_value("plugin", "name", ""), "AeroBeat Tool GLTF", "plugin.cfg name should match the repo identity")
	assert_eq(
		config.get_value("plugin", "description", ""),
		EXPECTED_PLUGIN_DESCRIPTION,
		"plugin.cfg description should stay aligned with the GLTF facade contract"
	)
	assert_eq(config.get_value("plugin", "version", ""), "0.3.0", "plugin version should reflect renamed facade + source selection + unload support")

func test_addons_manifest_includes_vendor_runtime_dependency() -> void:
	var manifest_text := _read_repo_file(ADDONS_MANIFEST_PATH)
	assert_true(manifest_text.contains('"aerobeat-tool-core"'), "addons manifest should keep aerobeat-tool-core")
	assert_true(manifest_text.contains('"aerobeat-vendor-godot-gltf"'), "addons manifest should include the vendor GLTF runtime addon")
	assert_true(manifest_text.contains('"aerobeat-vendor-godot-unit-test"'), "addons manifest should keep gut for repo-local tests")
	assert_false(manifest_text.contains('"aerobeat-core"'), "addons manifest should not reintroduce stale aerobeat-core drift")
