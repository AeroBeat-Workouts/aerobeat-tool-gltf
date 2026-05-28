extends SceneTree

const SCENE_PATH := "res://scenes/multi_gltf_proving_surface.tscn"
const PACKAGED_FIXTURE_PATH := "res://assets/models/alien-planet.glb"
const URL_FIXTURE := "https://example.com/models/test.glb"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed_scene := load(SCENE_PATH) as PackedScene
	if packed_scene == null:
		_fail("Could not load proving surface scene: %s" % SCENE_PATH)
		return

	var scene_root := packed_scene.instantiate()
	get_root().add_child(scene_root)
	await process_frame
	await process_frame

	var aggregate_root := scene_root.get_node_or_null("ToolGLTFMultiFixtureRoot") as Node3D
	if aggregate_root == null:
		_fail("Proving surface did not add the aggregate tool GLTF instance root")
		return
	if aggregate_root.get_child_count() != 2:
		_fail("Expected two GLTF instance anchors, got %d" % aggregate_root.get_child_count())
		return

	var left_anchor := aggregate_root.get_node_or_null("PlanetLeft") as Node3D
	var right_anchor := aggregate_root.get_node_or_null("PlanetRight") as Node3D
	if left_anchor == null or right_anchor == null:
		_fail("Expected both PlanetLeft and PlanetRight anchors to exist")
		return
	if left_anchor.position == right_anchor.position:
		_fail("Expected independent instance positions for proving surface anchors")
		return
	if left_anchor.scale == right_anchor.scale:
		_fail("Expected independent instance scales for proving surface anchors")
		return
	if left_anchor.get_child_count() != 1 or right_anchor.get_child_count() != 1:
		_fail("Expected each instance anchor to own one loaded GLTF child")
		return
	var left_position := left_anchor.position
	var right_position := right_anchor.position

	var source_input := scene_root.get_node_or_null("CanvasLayer/OverlayMargin/OverlayRow/ControlsPanel/ControlsMargin/ControlsVBox/SourceInput") as LineEdit
	var browse_button := scene_root.get_node_or_null("CanvasLayer/OverlayMargin/OverlayRow/ControlsPanel/ControlsMargin/ControlsVBox/TypedSourceButtons/BrowseButton") as Button
	var file_dialog := scene_root.get_node_or_null("CanvasLayer/SourceFileDialog") as FileDialog
	if source_input == null or browse_button == null or file_dialog == null:
		_fail("Expected source input, browse button, and file dialog proving controls to exist")
		return
	if file_dialog.access != FileDialog.ACCESS_FILESYSTEM:
		_fail("Expected proving surface file picker to browse the local filesystem")
		return

	var packaged_source: Dictionary = scene_root.call("_manual_source_from_text", PACKAGED_FIXTURE_PATH)
	if packaged_source.get("path", "") != PACKAGED_FIXTURE_PATH or packaged_source.get("format", "") != "glb":
		_fail("Expected typed packaged source parsing to preserve res:// GLB paths")
		return

	var url_source: Dictionary = scene_root.call("_manual_source_from_text", URL_FIXTURE)
	if url_source.get("url", "") != URL_FIXTURE or url_source.get("format", "") != "glb":
		_fail("Expected typed URL source parsing to preserve remote GLB URLs")
		return

	var absolute_path := ProjectSettings.globalize_path(PACKAGED_FIXTURE_PATH)
	source_input.text = absolute_path
	scene_root.call("_on_apply_source_button_pressed")
	await process_frame
	await process_frame

	aggregate_root = scene_root.get_node_or_null("ToolGLTFMultiFixtureRoot") as Node3D
	if aggregate_root == null or aggregate_root.get_child_count() != 2:
		_fail("Expected typed absolute-path load to rebuild the aggregate root")
		return

	print("[validate-tool-multi-gltf-proving-surface] OK left=%s right=%s typed=%s" % [
		var_to_str(left_position),
		var_to_str(right_position),
		absolute_path,
	])
	quit(0)

func _fail(message: String) -> void:
	push_error("[validate-tool-multi-gltf-proving-surface] %s" % message)
	quit(1)
