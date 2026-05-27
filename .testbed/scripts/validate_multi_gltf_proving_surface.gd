extends SceneTree

const SCENE_PATH := "res://scenes/multi_gltf_proving_surface.tscn"

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

	print("[validate-tool-multi-gltf-proving-surface] OK left=%s right=%s" % [
		var_to_str(left_anchor.position),
		var_to_str(right_anchor.position),
	])
	quit(0)

func _fail(message: String) -> void:
	push_error("[validate-tool-multi-gltf-proving-surface] %s" % message)
	quit(1)
