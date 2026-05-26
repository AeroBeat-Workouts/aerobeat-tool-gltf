# AeroBeat Tool GLTF

Consumer-facing **GLTF/GLB facade** for AeroBeat repos that need 3D scene loading without directly owning Godot runtime/importer details.

This repo sits in the middle of the current stack:

- `aerobeat-vendor-godot-gltf` owns Godot/runtime-specific scene loading details.
- `aerobeat-tool-gltf` owns the stable consumer-facing GLTF/GLB abstraction.
- consumers like `aerobeat-environment-loader` should depend on this facade instead of talking to `GLTFDocument`, imported-resource constraints, or vendor-specific classes directly.

## Current first-slice contract

The initial truthful slice is intentionally narrow:

- supports **scene-oriented GLTF containers**: `.gltf` and `.glb`
- normalizes consumer requests into a small stable request shape
- delegates runtime loading to `aerobeat-vendor-godot-gltf`
- returns a scene bundle result that higher-level repos can attach/apply/configure
- does **not** own environment orchestration policy, config application, or scene placement rules

### Main facade

- Script: `src/AeroGLTFTool.gd`
- Class: `AeroGLTFTool`

### Consumer-facing methods

- `supports_container(container: String) -> bool`
- `supported_containers() -> PackedStringArray`
- `build_scene_request(asset_path: String, options: Dictionary = {}) -> Dictionary`
- `normalize_scene_request(request: Dictionary) -> Dictionary`
- `load_scene_from_path(asset_path: String, options: Dictionary = {}) -> Dictionary`
- `load_scene(request: Dictionary) -> Dictionary`
- `get_backend_contract() -> Dictionary`

### Normalized request shape

```gdscript
{
  "asset_path": "/absolute/or/resource/path/to/environment.glb",
  "container": "glb", # or "gltf"
  "format": "glb",    # same as container for this first slice
  "instantiate": true,
  "metadata": {}
}
```

### Result shape

Success:

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

- loader script: `res://addons/aerobeat-vendor-godot-gltf/loaders/aero_godot_gltf_runtime_loader.gd`
- vendor entry points:
  - `load_source(source: Dictionary, flags := 0) -> Dictionary`
  - `load_scene(source: Dictionary, flags := 0, scene_options := {}) -> Dictionary`

That vendor runtime loader should own the engine/runtime-specific GLTF/GLB parsing and scene generation mechanics, while this tool facade keeps the higher-level request/result shape stable for consumers.

## What `environment-loader` should consume next

The next integration seam for `aerobeat-environment-loader` is:

1. replace the current inline `_load_glb()` resource-loading branch with `AeroGLTFTool.load_scene(...)`
2. keep `environment-loader` responsible for:
   - environment request validation/orchestration
   - attaching the returned `scene_root` to `_world_root`
   - applying environment config after attach
   - mapping tool/runtime failures into environment-domain error payloads
3. stop directly encoding the current `res://` import-pipeline limitation in `environment-loader`; that limitation belongs in the vendor/tool stack result details instead

## GodotEnv development flow

This repo uses the AeroBeat GodotEnv package convention.

- Canonical dev/test manifest: `.testbed/addons.jsonc`
- Installed dev/test addons: `.testbed/addons/`
- GodotEnv cache: `.testbed/.addons/`
- Hidden workbench project: `.testbed/project.godot`
- Repo-local unit tests: `.testbed/tests/`
- Packaged GLB proving fixture: `.testbed/fixtures/models/alien-planet.glb`

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
godot --headless --path .testbed --script addons/gut/gut_cmdln.gd \
  -gdir=res://tests \
  -ginclude_subdirs \
  -gexit
```
