extends SceneTree

const DEFAULT_REMOTE_URL := "http://127.0.0.1:8123/alien-planet.glb"
const TOOL_CANDIDATE_PATHS := [
	"res://addons/aerobeat-tool-gltf-loader/src/AeroGLTFLoader.gd",
	"res://../src/AeroGLTFLoader.gd",
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var tool: Variant = _create_tool()
	if tool == null:
		_fail("Could not create the AeroGLTFLoader facade")
		return
	var url := OS.get_environment("AEROBEAT_GLTF_TEST_URL")
	if url.is_empty():
		url = DEFAULT_REMOTE_URL
	var result: Dictionary = tool.load_scene_from_source({"url": url, "format": "glb"})
	if not bool(result.get("ok", false)):
		_fail("URL source load failed: %s" % result.get("message", "unknown"))
		return
	var scene_root := result.get("scene_root", null) as Node
	if scene_root == null:
		_fail("URL source load did not produce a scene root")
		return
	var unload_result: Dictionary = tool.unload_result(result)
	if not bool(unload_result.get("ok", false)):
		_fail("URL source unload failed")
		return
	print("[validate-tool-url-source-flow] OK url=%s" % url)
	quit(0)

func _create_tool() -> Variant:
	for candidate_path in TOOL_CANDIDATE_PATHS:
		if not ResourceLoader.exists(candidate_path, "Script"):
			continue
		var script_resource: Variant = load(candidate_path)
		if script_resource != null and script_resource.has_method("new"):
			return script_resource.new()
	return null

func _fail(message: String) -> void:
	push_error("[validate-tool-url-source-flow] %s" % message)
	quit(1)
