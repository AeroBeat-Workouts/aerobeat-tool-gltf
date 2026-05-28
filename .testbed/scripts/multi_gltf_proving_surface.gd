extends Node3D

const TOOL_CANDIDATE_PATHS := [
	"res://addons/aerobeat-tool-gltf-loader/src/AeroGLTFTool.gd",
	"res://addons/aerobeat-tool-gltf-loader/src/AeroGLTFTool.gd",
]
const FIXTURE_PATH := "res://fixtures/models/alien-planet.glb"
const POSITION_PRESETS := [
	Vector3(-3.0, 0.0, 0.0),
	Vector3(0.0, 0.5, -1.5),
	Vector3(3.0, 1.0, 0.5),
]
const ROTATION_PRESETS := [
	Vector3.ZERO,
	Vector3(0.0, 35.0, 0.0),
	Vector3(-15.0, 90.0, 0.0),
]
const SCALE_PRESETS := [
	Vector3.ONE * 0.6,
	Vector3.ONE,
	Vector3.ONE * 1.4,
]

var _tool: Variant = null
var _aggregate_root: Node3D = null
var _instance_roots: Array[Node3D] = []
var _position_indices: Array[int] = [0, 2]
var _rotation_indices: Array[int] = [0, 1]
var _scale_indices: Array[int] = [1, 0]
var _selected_instance_index := 0

@onready var _hud_label: RichTextLabel = $CanvasLayer/HUDMargin/HUDLabel

func _ready() -> void:
	_tool = _create_tool()
	if _tool == null:
		push_error("[tool-multi-gltf-proving-surface] Failed to load AeroGLTFTool")
		set_process_unhandled_input(false)
		return
	_build_scene()
	_print_snapshot()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	match event.keycode:
		KEY_1:
			_select_instance(0)
		KEY_2:
			_select_instance(1)
		KEY_TAB:
			_select_instance((_selected_instance_index + 1) % max(_instance_roots.size(), 1))
		KEY_P:
			_cycle_dimension("position")
		KEY_R:
			_cycle_dimension("rotation")
		KEY_S:
			_cycle_dimension("scale")
		KEY_V:
			_print_snapshot()

func _build_scene() -> void:
	if _aggregate_root != null:
		_aggregate_root.queue_free()
		_instance_roots.clear()

	var result: Dictionary = _tool.load_scene_collection([
		{
			"asset_path": FIXTURE_PATH,
			"instance": {
				"name": "PlanetLeft",
				"transform": {
					"position": POSITION_PRESETS[_position_indices[0]],
					"rotation_degrees": ROTATION_PRESETS[_rotation_indices[0]],
					"scale": SCALE_PRESETS[_scale_indices[0]],
				},
			},
		},
		{
			"asset_path": FIXTURE_PATH,
			"instance": {
				"name": "PlanetRight",
				"transform": {
					"position": POSITION_PRESETS[_position_indices[1]],
					"rotation_degrees": ROTATION_PRESETS[_rotation_indices[1]],
					"scale": SCALE_PRESETS[_scale_indices[1]],
				},
			},
		},
	], {"scene_options": {"root_name": "ToolGLTFMultiFixtureRoot"}})
	if not bool(result.get("ok", false)):
		push_error("[tool-multi-gltf-proving-surface] %s" % result.get("message", "Tool GLTF multi-instance load failed"))
		_update_hud("Load failed")
		return

	_aggregate_root = result.get("scene_root", null) as Node3D
	if _aggregate_root == null:
		push_error("[tool-multi-gltf-proving-surface] Tool GLTF collection did not return a Node3D root")
		_update_hud("Invalid scene root")
		return

	add_child(_aggregate_root)
	for instance_detail_variant in result.get("instances", []):
		if not (instance_detail_variant is Dictionary):
			continue
		var instance_detail: Dictionary = instance_detail_variant
		var instance_root := instance_detail.get("instance_root", null) as Node3D
		if instance_root != null:
			_instance_roots.append(instance_root)

	_update_hud()

func _cycle_dimension(dimension: String) -> void:
	if _instance_roots.is_empty():
		return

	match dimension:
		"position":
			_position_indices[_selected_instance_index] = (_position_indices[_selected_instance_index] + 1) % POSITION_PRESETS.size()
			_instance_roots[_selected_instance_index].position = POSITION_PRESETS[_position_indices[_selected_instance_index]]
		"rotation":
			_rotation_indices[_selected_instance_index] = (_rotation_indices[_selected_instance_index] + 1) % ROTATION_PRESETS.size()
			_instance_roots[_selected_instance_index].rotation_degrees = ROTATION_PRESETS[_rotation_indices[_selected_instance_index]]
		"scale":
			_scale_indices[_selected_instance_index] = (_scale_indices[_selected_instance_index] + 1) % SCALE_PRESETS.size()
			_instance_roots[_selected_instance_index].scale = SCALE_PRESETS[_scale_indices[_selected_instance_index]]

	_update_hud()

func _select_instance(index: int) -> void:
	if index < 0 or index >= _instance_roots.size():
		return
	_selected_instance_index = index
	_update_hud()

func _update_hud(status: String = "Ready") -> void:
	if _hud_label == null:
		return
	_hud_label.text = "[b]Tool GLTF multi-instance proving surface[/b]\nFixture: %s\n\nControls\n- [b]1[/b]/[b]2[/b] select instance\n- [b]Tab[/b] cycle selected instance\n- [b]P[/b] cycle parent position preset\n- [b]R[/b] cycle parent rotation preset\n- [b]S[/b] cycle parent scale preset\n- [b]V[/b] print transform snapshot\n\nStatus: %s\nSelected instance: %s\n\nSnapshots\n%s" % [
		FIXTURE_PATH,
		status,
		_selected_instance_index + 1,
		"\n".join(_snapshot_lines()),
	]

func _snapshot_lines() -> Array[String]:
	var lines: Array[String] = []
	for index in range(_instance_roots.size()):
		var instance_root := _instance_roots[index]
		var marker := ">" if index == _selected_instance_index else "-"
		lines.append("%s %s pos=%s rot=%s scale=%s child=%s" % [
			marker,
			instance_root.name,
			_var_to_pretty(instance_root.position),
			_var_to_pretty(instance_root.rotation_degrees),
			_var_to_pretty(instance_root.scale),
			instance_root.get_child(0).name if instance_root.get_child_count() > 0 else "<none>",
		])
	return lines

func _print_snapshot() -> void:
	if _instance_roots.is_empty():
		return
	print("[tool-multi-gltf-proving-surface] snapshots => %s" % " | ".join(_snapshot_lines()))
	_update_hud("Snapshot printed")

func _create_tool() -> Variant:
	for candidate_path in TOOL_CANDIDATE_PATHS:
		if not ResourceLoader.exists(candidate_path, "Script"):
			continue
		var script_resource: Variant = load(candidate_path)
		if script_resource != null and script_resource.has_method("new"):
			return script_resource.new()
	return null

func _var_to_pretty(value: Variant) -> String:
	return var_to_str(value).replace("\n", "")
