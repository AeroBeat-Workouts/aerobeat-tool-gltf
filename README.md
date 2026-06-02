# AeroBeat Tool GLTF Loader

Consumer-facing **GLTF/GLB facade** for AeroBeat repos that need 3D scene loading without directly owning Godot runtime/importer details.

This repo sits in the middle of the current stack:

- `aerobeat-vendor-godot-gltf` owns Godot/runtime-specific scene loading details.
- `aerobeat-tool-gltf-loader` owns the stable consumer-facing GLTF/GLB abstraction.
- consumers like `aerobeat-environment-loader` should depend on this facade instead of talking to `GLTFDocument`, imported-resource constraints, or vendor-specific classes directly.

## Current contract slice

The current truthful slice stays consumer-facing while now covering single-scene, transformable single-instance, and multi-instance loading:

- supports **scene-oriented GLTF containers**: `.gltf` and `.glb`
- normalizes consumer requests into a small stable request shape
- delegates runtime loading to `aerobeat-vendor-godot-gltf`
- preserves existing packaged/internal and external/absolute GLB behavior
- adds vendor-agnostic transform controls for `position`, `rotation_degrees`, and `scale`
- adds multi-GLTF collection loading without exposing raw vendor loader entry points to consumers
- still does **not** own environment orchestration policy, config application, or scene placement rules beyond the requested instance transforms

### Main facade

- Script: `src/AeroGLTFLoader.gd`
- Class: `AeroGLTFLoader`

### Consumer-facing methods

- `supports_container(container: String) -> bool`
- `supported_containers() -> Array`
- `get_default_transform() -> Dictionary`
- `get_default_instance_options() -> Dictionary`
- `build_scene_request(asset_path: String, options: Dictionary = {}) -> Dictionary`
- `build_scene_request_from_source(source: Dictionary, options: Dictionary = {}) -> Dictionary`
- `build_scene_instance_request(asset_path: String, options: Dictionary = {}) -> Dictionary`
- `build_scene_collection_request(instances: Array, options: Dictionary = {}) -> Dictionary`
- `normalize_scene_request(request: Dictionary) -> Dictionary`
- `normalize_scene_instance_request(request: Dictionary) -> Dictionary`
- `normalize_scene_collection_request(request: Dictionary) -> Dictionary`
- `normalize_transform(transform_config: Dictionary) -> Dictionary`
- `normalize_instance_options(instance_options: Dictionary) -> Dictionary`
- `load_scene_from_path(asset_path: String, options: Dictionary = {}) -> Dictionary`
- `load_scene_from_source(source: Dictionary, options: Dictionary = {}) -> Dictionary`
- `load_scene_instance_from_path(asset_path: String, options: Dictionary = {}) -> Dictionary`
- `load_scene_collection(instances: Array, options: Dictionary = {}) -> Dictionary`
- `unload_result(result: Dictionary) -> Dictionary`
- `unload_last_result() -> Dictionary`
- `load_scene(request: Dictionary) -> Dictionary`
- `load_scene_instance(request: Dictionary) -> Dictionary`
- `load_scene_collection_request(request: Dictionary) -> Dictionary`
- `get_backend_contract() -> Dictionary`

### Normalized single-scene request shape

```gdscript
{
  "asset_path": "/absolute/or/resource/path/to/environment.glb",
  "container": "glb", # or "gltf"
  "format": "glb",
  "instantiate": true,
  "metadata": {}
}
```

### Normalized single-instance request shape

```gdscript
{
  "asset_path": "res://assets/models/alien-planet.glb",
  "container": "glb",
  "format": "glb",
  "instantiate": true,
  "metadata": {},
  "scene_options": {},
  "instance": {
    "name": "PlanetAnchor",
    "transform": {
      "position": Vector3(1, 2, 3),
      "rotation_degrees": Vector3(0, 45, 0),
      "scale": Vector3(0.5, 0.5, 0.5)
    },
    "metadata": {}
  }
}
```

### Normalized multi-instance collection request shape

```gdscript
{
  "instances": [
    {
      "asset_path": "res://assets/models/alien-planet.glb",
      "container": "glb",
      "format": "glb",
      "instantiate": true,
      "metadata": {},
      "scene_options": {},
      "instance": {
        "name": "PlanetLeft",
        "transform": {
          "position": Vector3(-2, 0, 0),
          "rotation_degrees": Vector3(0, -20, 0),
          "scale": Vector3.ONE
        },
        "metadata": {}
      }
    },
    {
      "asset_path": "/absolute/path/to/environment.glb",
      "container": "glb",
      "format": "glb",
      "instantiate": true,
      "metadata": {},
      "scene_options": {},
      "instance": {
        "name": "PlanetRight",
        "transform": {
          "position": Vector3(2, 0.75, 0),
          "rotation_degrees": Vector3(0, 35, 0),
          "scale": Vector3(1.25, 1.25, 1.25)
        },
        "metadata": {}
      }
    }
  ],
  "scene_options": {
    "root_name": "EnvironmentInstances"
  },
  "metadata": {}
}
```

### Result shapes

Single-scene success:

```gdscript
{
  "ok": true,
  "asset_path": "...",
  "absolute_path": "...",
  "resource_path": "...",
  "format": "glb",
  "container": "glb",
  "scene_root": Node,
  "packed_scene": PackedScene,
  "warnings": [],
  "details": {}
}
```

Single-instance success:

```gdscript
{
  "ok": true,
  "asset_path": "...",
  "absolute_path": "...",
  "resource_path": "...",
  "format": "glb",
  "container": "glb",
  "scene_root": Node3D,
  "instance_root": Node3D,
  "loaded_scene_root": Node,
  "packed_scene": PackedScene,
  "warnings": [],
  "details": {}
}
```

Multi-instance success:

```gdscript
{
  "ok": true,
  "scene_root": Node3D,
  "instances": [
    {
      "asset_path": "...",
      "absolute_path": "...",
      "resource_path": "...",
      "format": "glb",
      "container": "glb",
      "scene_root": Node3D,
      "instance_root": Node3D,
      "loaded_scene_root": Node,
      "warnings": [],
      "details": {}
    }
  ],
  "warnings": [],
  "details": {}
}
```

Failure:

```gdscript
{
  "ok": false,
  "request": {...},
  "error_code": "invalid_request|unsupported_format|backend_unavailable|backend_failed",
  "message": "...",
  "recoverable": true,
  "details": {}
}
```

## Runtime backend contract

This tool ships a default runtime adapter, `AeroVendorGodotGLTFBackendAdapter`, that bridges the facade contract onto `aerobeat-vendor-godot-gltf`'s Godot-native runtime loader.

The adapter expects `aerobeat-vendor-godot-gltf` to provide:

Tool-side source selection stays higher-level: callers can keep using `asset_path` for packaged/external files, or pass a normalized `source` dictionary with either `path` or `url` when they need explicit local-device or remote selection without teaching consumers the vendor runtime transport rules.

- loader script: `res://addons/aerobeat-vendor-godot-gltf/src/aero_godot_gltf_runtime_loader.gd`
- vendor entry points:
  - `load_source(source: Dictionary, flags := 0) -> Dictionary`
  - `load_scene(source: Dictionary, flags := 0, scene_options := {}) -> Dictionary`
  - `load_scene_instance(source, flags := 0, scene_options := {}, instance_options := {}) -> Dictionary`
  - `load_scene_instances(instances, flags := 0, scene_options := {}) -> Dictionary`

That vendor runtime loader should own the engine/runtime-specific GLTF/GLB parsing and scene generation mechanics, while this tool facade keeps the higher-level request/result shape stable for consumers.

## Example consumer usage

Single scene:

```gdscript
var tool := AeroGLTFLoader.new()
var result := tool.load_scene_from_path("res://assets/models/alien-planet.glb")
if result.get("ok", false):
  add_child(result["scene_root"])
```

Transformable single instance:

```gdscript
var result := tool.load_scene_instance_from_path("res://assets/models/alien-planet.glb", {
  "instance": {
    "name": "PlanetAnchor",
    "transform": {
      "position": [1, 2, 3],
      "rotation_degrees": [0, 45, 0],
      "scale": [0.5, 0.5, 0.5]
    }
  }
})
if result.get("ok", false):
  add_child(result["instance_root"])
```

Multi-instance collection:

```gdscript
var result := tool.load_scene_collection([
  {
    "asset_path": "res://assets/models/alien-planet.glb",
    "instance": {
      "name": "PlanetLeft",
      "transform": {"position": [-2, 0, 0]}
    }
  },
  {
    "asset_path": "/absolute/path/to/environment.glb",
    "instance": {
      "name": "PlanetRight",
      "transform": {
        "position": [2, 0.75, 0],
        "scale": [1.25, 1.25, 1.25]
      }
    }
  }
], {"scene_options": {"root_name": "EnvironmentInstances"}})
if result.get("ok", false):
  add_child(result["scene_root"])
```

## What `environment-loader` should consume next

The next integration seam for `aerobeat-environment-loader` is still:

1. replace direct vendor/runtime assumptions with `AeroGLTFLoader` calls
2. keep `environment-loader` responsible for:
   - environment request validation/orchestration
   - attaching the returned `scene_root` / `instance_root` to `_world_root`
   - applying environment config after attach when policy belongs above the tool
   - mapping tool/runtime failures into environment-domain error payloads
3. use the new instance/collection helpers when a workout or environment needs multiple GLTF anchors or transformable wrapper roots without teaching `environment-loader` the vendor API

## GodotEnv development flow

This repo uses the AeroBeat GodotEnv package convention.

- Canonical dev/test manifest: `.testbed/addons.jsonc`
- Installed dev/test addons: `.testbed/addons/`
- GodotEnv cache: `.testbed/.addons/`
- Hidden workbench project: `.testbed/project.godot`
- Repo-local unit tests: `.testbed/tests/`
- Packaged GLB proving fixture: `.testbed/assets/models/alien-planet.glb`
- Tool GLTF multi-instance proving surface scene: `.testbed/scenes/multi_gltf_proving_surface.tscn`
- Tool GLTF multi-instance proving surface script: `.testbed/scripts/multi_gltf_proving_surface.gd`

### Restore dev/test dependencies

From the repo root:

```bash
cd .testbed
godotenv addons install
```

### Import smoke check

From the repo root:

```bash
godot --headless --path .testbed --import
```

### Run unit tests

From the repo root:

```bash
godot --headless --path .testbed --script addons/aerobeat-vendor-godot-unit-test/gut_cmdln.gd \
  -gdir=res://tests \
  -ginclude_subdirs \
  -gexit
```

### Proving surface smoke check

From the repo root:

```bash
godot --headless --path .testbed --script res://scripts/validate_multi_gltf_proving_surface.gd
```

### Human proving surface

Open the hidden testbed project and run `.testbed/scenes/multi_gltf_proving_surface.tscn` to verify:

- two independent GLTF instances load through the tool facade under one aggregate root
- parent `position`, `rotation_degrees`, and `scale` controls apply after load
- each instance can be adjusted without mutating the other imported scene
- the proving surface stays tool-facing rather than talking to the vendor loader directly

Keyboard controls inside the proving surface:

- `F1` / `F2` / `F3` — load the packaged project path, copied external device path, or URL source
- `L` — reload the current source mode
- `U` — explicitly unload the current result
- `W` / `A` / `S` / `D` — fly the camera
- `Q` / `E` — move the camera down/up
- hold `Shift` — move the camera faster
- hold left mouse and drag — rotate the fly camera

- `1` / `2` — select the left or right instance
- `Tab` — cycle the selected instance
- `P` — cycle parent position preset
- `R` — cycle parent rotation preset
- `C` — cycle parent scale preset
- `V` — print a transform snapshot to the Godot output log
