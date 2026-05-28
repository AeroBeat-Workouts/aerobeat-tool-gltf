extends Node3D

const TOOL_CANDIDATE_PATHS := [
	"res://addons/aerobeat-tool-gltf-loader/src/AeroGLTFLoader.gd",
	"res://../src/AeroGLTFLoader.gd",
]
const PACKAGED_ASSET_PATH := "res://assets/models/alien-planet.glb"
const DEFAULT_REMOTE_URL := "http://127.0.0.1:8123/alien-planet.glb"
const EXTERNAL_FIXTURE_DIRECTORY_NAME := "aerobeat-tool-gltf-loader-testbed"
const EXTERNAL_FIXTURE_FILE_NAME := "alien-planet-external.glb"
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
const CAMERA_MOVE_SPEED := 8.0
const CAMERA_FAST_MULTIPLIER := 2.0
const CAMERA_LOOK_SENSITIVITY := 0.2

var _tool: Variant = null
var _aggregate_root: Node3D = null
var _instance_roots: Array[Node3D] = []
var _position_indices: Array[int] = [0, 2]
var _rotation_indices: Array[int] = [0, 1]
var _scale_indices: Array[int] = [1, 0]
var _selected_instance_index := 0
var _current_source_mode := "packaged"
var _last_result: Dictionary = {}
var _drag_rotating := false
var _camera_pitch_degrees := -12.0
var _camera_yaw_degrees := 0.0

@export var packaged_source_path := PACKAGED_ASSET_PATH
@export var external_source_path := ""
@export var remote_source_url := DEFAULT_REMOTE_URL

@onready var _camera: Camera3D = $Camera3D
@onready var _hud_label: RichTextLabel = $CanvasLayer/HUDMargin/HUDLabel

func _ready() -> void:
	_tool = _create_tool()
	if _tool == null:
		push_error("[tool-multi-gltf-proving-surface] Failed to load AeroGLTFLoader")
		set_process_unhandled_input(false)
		set_process(false)
		return
	if external_source_path.is_empty():
		external_source_path = _make_external_fixture_copy()
	_sync_camera_rotation()
	_load_source_mode(_current_source_mode)

func _process(delta: float) -> void:
	if _camera == null:
		return
	var input_vector := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		input_vector -= _camera.global_basis.z
	if Input.is_key_pressed(KEY_S):
		input_vector += _camera.global_basis.z
	if Input.is_key_pressed(KEY_A):
		input_vector -= _camera.global_basis.x
	if Input.is_key_pressed(KEY_D):
		input_vector += _camera.global_basis.x
	if Input.is_key_pressed(KEY_Q):
		input_vector -= _camera.global_basis.y
	if Input.is_key_pressed(KEY_E):
		input_vector += _camera.global_basis.y
	if input_vector == Vector3.ZERO:
		return
	var speed := CAMERA_MOVE_SPEED * (CAMERA_FAST_MULTIPLIER if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	_camera.global_position += input_vector.normalized() * speed * delta
	_update_hud("Flying")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_drag_rotating = event.pressed
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if _drag_rotating else Input.MOUSE_MODE_VISIBLE)
		if not _drag_rotating:
			_update_hud()
		return

	if event is InputEventMouseMotion and _drag_rotating:
		_camera_yaw_degrees -= event.relative.x * CAMERA_LOOK_SENSITIVITY
		_camera_pitch_degrees = clamp(_camera_pitch_degrees - event.relative.y * CAMERA_LOOK_SENSITIVITY, -89.0, 89.0)
		_sync_camera_rotation()
		_update_hud("Camera look")
		return

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
		KEY_F1:
			_load_source_mode("packaged")
		KEY_F2:
			_load_source_mode("external")
		KEY_F3:
			_load_source_mode("url")
		KEY_L:
			_load_source_mode(_current_source_mode)
		KEY_U:
			_unload_current_result()

func _load_source_mode(source_mode: String) -> void:
	_current_source_mode = source_mode
	_unload_current_result(false)
	_instance_roots.clear()

	var source := _source_for_mode(source_mode)
	var result: Dictionary = _tool.load_scene_collection([
		{
			"source": source,
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
			"source": source,
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
	_last_result = result.duplicate(true)
	if not bool(result.get("ok", false)):
		push_error("[tool-multi-gltf-proving-surface] %s" % result.get("message", "Tool GLTF collection load failed"))
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
		var instance_root := instance_detail.get("instance_root") as Node3D
		if instance_root != null:
			_instance_roots.append(instance_root)
	_update_hud("Loaded %s" % source_mode)

func _unload_current_result(show_status: bool = true) -> void:
	if _aggregate_root == null and _last_result.is_empty():
		if show_status:
			_update_hud("Nothing to unload")
		return
	if _tool != null and not _last_result.is_empty() and _tool.has_method("unload_result"):
		_tool.unload_result(_last_result)
	_last_result = {}
	_aggregate_root = null
	_instance_roots.clear()
	if show_status:
		_update_hud("Unloaded")

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

func _source_for_mode(source_mode: String) -> Dictionary:
	match source_mode:
		"external":
			return {"path": external_source_path, "format": "glb"}
		"url":
			return {"url": remote_source_url, "format": "glb"}
		_:
			return {"path": packaged_source_path, "format": "glb"}

func _update_hud(status: String = "Ready") -> void:
	if _hud_label == null:
		return
	var snapshots := _snapshot_lines()
	_hud_label.text = "[b]Tool GLTF proving surface[/b]\nSource mode: %s\nPackaged: %s\nExternal: %s\nURL: %s\n\nSource controls\n- [b]F1[/b]/[b]F2[/b]/[b]F3[/b] load packaged, external, or URL source\n- [b]L[/b] reload current source\n- [b]U[/b] unload current result\n\nTransform controls\n- [b]1[/b]/[b]2[/b] select instance\n- [b]Tab[/b] cycle selected instance\n- [b]P[/b] cycle position preset\n- [b]R[/b] cycle rotation preset\n- [b]S[/b] cycle scale preset\n- [b]V[/b] print transform snapshot\n\nFly camera\n- [b]WASD[/b] move horizontally\n- [b]Q[/b]/[b]E[/b] move down/up\n- hold [b]Shift[/b] to move faster\n- hold left mouse and drag to rotate\n\nStatus: %s\nSelected instance: %s\nCamera: pos=%s pitch=%.2f yaw=%.2f\n\nSnapshots\n%s" % [
		_current_source_mode,
		packaged_source_path,
		external_source_path,
		remote_source_url,
		status,
		_selected_instance_index + 1,
		_var_to_pretty(_camera.global_position) if _camera != null else "<none>",
		_camera_pitch_degrees,
		_camera_yaw_degrees,
		"\n".join(snapshots),
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

func _make_external_fixture_copy() -> String:
	var temp_root := OS.get_environment("TMPDIR")
	if temp_root.is_empty():
		temp_root = "/tmp"
	var target_directory := temp_root.path_join(EXTERNAL_FIXTURE_DIRECTORY_NAME)
	DirAccess.make_dir_recursive_absolute(target_directory)
	var target_path := target_directory.path_join(EXTERNAL_FIXTURE_FILE_NAME)
	DirAccess.copy_absolute(ProjectSettings.globalize_path(PACKAGED_ASSET_PATH), target_path)
	return target_path

func _sync_camera_rotation() -> void:
	if _camera == null:
		return
	_camera.rotation_degrees = Vector3(_camera_pitch_degrees, _camera_yaw_degrees, 0.0)

func _var_to_pretty(value: Variant) -> String:
	return var_to_str(value).replace("\n", "")
