# dn1sup_export_3d

SketchUp 2026 extension that exports models (or the current selection) to
**glTF 2.0 / GLB** and views the result interactively with **Three.js** —
in a browser, or right inside SketchUp in an `UI::HtmlDialog`.

```
SketchUp 2026 (Ruby API)
        │  dn1sup_export_3d (this extension)
        ▼
     model.glb  +  <name>_web3d/ package
        │
        ▼
Three.js viewer  (browser / HtmlDialog / any website)
```

## Install

- **From RBZ**: SketchUp → Extension Manager → Install Extension →
  `build/dn1sup_export_3d.rbz` (build it with `ruby build/package.rb`).
- **From source**: copy `dn1sup_export_3d.rb` and `dn1sup_export_3d/` into
  your SketchUp `Plugins` folder (both must sit side by side, exactly as in
  this repository).

After installation, the menu **Extensions → Web 3D Export** appears with:

- *Export current model to GLB* — exports everything visible;
- *Export selected objects to GLB* — exports only the current selection.

The exporter writes `model.glb` next to the chosen path and copies a
self-contained web package to `<name>_web3d/`:

```
<name>_web3d/
├── model.glb        # the exported model
├── index.html
├── viewer.js
├── viewer.css
└── vendor/three/    # vendored Three.js, no CDN needed
```

Upload that folder anywhere (or open `index.html` locally in a browser);
the same GLB loads without SketchUp.

## Exporter

### Coordinate system and units

Centralized in `dn1sup_export_3d/exporter/coordinate.rb`:

| | SketchUp | glTF 2.0 |
|---|---|---|
| Handedness | right-handed | right-handed |
| Up axis | +Z | +Y |
| Unit | 1 inch | 1 meter |

Axis mapping: `(x, y, z)su → (x, z, -y)gltf`, scale `× 0.0254`. The mapping
is a proper rotation (determinant +1), so triangle winding is preserved.
Transformations are exported as glTF node matrices (conjugated with the
basis change: `M_gltf = C · M_su · C⁻¹`), so mirrored instances keep their
negative determinant and renderers flip winding per the glTF spec.

### Structure

- The glTF node tree mirrors the SketchUp object tree (groups and component
  instances become nodes; transforms live on nodes, not in vertex data).
- A component definition's geometry is exported **once**; each instance
  clones the definition's node subtree and shares the mesh data.
- Every instance/group node carries `extras.sketchup` metadata:

```json
{
  "sketchup": {
    "persistent_id": 12345,
    "entity_type": "ComponentInstance",
    "name": "Cabinet",
    "layer": "Kitchen"
  }
}
```

- Triangulation uses SketchUp's own `PolygonMesh` (`face.mesh`), which
  handles convex, concave and holed faces (validated by tests: the exported
  triangle area equals `face.area`).

### Materials and textures

- Untextured material: `material.color` → `baseColorFactor`.
- Textured material: the image is embedded into the GLB (PNG/JPEG as-is;
  anything else — or images that only live inside the .skp — is re-exported
  as PNG via `Texture#write`), `baseColorFactor` stays white.
- `material.alpha` (a 0.0..1.0 float) < 1 → `alphaMode: "BLEND"`.
- UVs from `face.get_UVHelper().get_front_UVQ` → `TEXCOORD_0`, with the
  V flip required by glTF's top-left UV origin (`v_gltf = 1 - v_sketchup`).
- Textures repeat (`wrapS/wrapT = REPEAT`), matching SketchUp tiling.

Documented fallbacks (SketchUp has no glTF equivalent):

- `back_material` is not mapped; materials export `doubleSided: true` so
  back faces render with the front material.
- SketchUp's per-material "colorize" mode is not modeled (the factor would
  double-tint), hence the white factor on textured materials.
- Roughness/metallic do not exist in core SketchUp: fixed neutral values
  (0.9 / 0.0) are used instead of invented PBR data.

### Visibility

Hidden entities and entities on hidden tags/layers are skipped at every
level. Page-specific visibility overrides and "hide rest of model" are not
applied. The export never modifies the model (verified by a test).

## Viewer

`viewer.js` exposes a small API (`window.viewer`, AGENTS.md §22):

```js
viewer.loadModel(url);      // load a GLB
viewer.selectObject(pid);   // highlight by SketchUp persistent_id -> bool
viewer.focusObject(pid);    // move camera to the object -> bool
viewer.getObject(pid);      // extras.sketchup metadata or null
viewer.clearSelection();
viewer.fit(); viewer.reset();
viewer.on("viewerReady", cb);      // {url, objects, triangles}
viewer.on("objectSelected", cb);   // extras.sketchup of the clicked object
viewer.on("selectionCleared", cb);
viewer.on("loadError", cb);        // {url, error}
```

Clicks raycast meshes (metadata is inherited from the owning node),
highlight via per-mesh material clones (instances share materials), and the
info panel uses `textContent` only — model metadata is never injected as
HTML. Works both in a plain browser and inside the HtmlDialog.

## HtmlDialog bridge

Attached in `main.rb` before `dialog.show`; JS calls Ruby through the
`window.sketchup` object that HtmlDialog injects (absent in normal browsers,
which doubles as feature detection):

| JS (viewer.js) | Ruby callback | Effect |
|---|---|---|
| `sketchup.viewer_ready(<n>)` | `viewer_ready` | logs that the viewer is up |
| `sketchup.object_selected(<pid>, …)` | `object_selected` | receives the clicked object's pid chain (part first, its component instance last) and selects the first pid that exists as an entity in the model |

Ruby → JS is available via `dialog.execute_script` (e.g.
`window.viewer.selectObject(...)`); callbacks must be (re-)attached before
`show`, because HtmlDialog clears them on close. The dialog reference is
retained by the module (an unreferenced HtmlDialog can be garbage-collected).

## Development

```
dn1sup_export_3d.rb          # registrar (sits next to the folder, like in Plugins)
dn1sup_export_3d/
├── main.rb                  # menus, export flow, HtmlDialog bridge
├── version.rb               # single source of the version
├── logger.rb
├── exporter/                # coordinate.rb, buffer.rb, geometry.rb,
│                            # materials.rb, glb_exporter.rb
├── viewer/                  # index.html, viewer.js, viewer.css
└── vendor/                  # vendored Three.js ES modules (MIT), no CDN
    ├── three/               # three.module.min.js, GLTFLoader.js, OrbitControls.js
    └── utils/               # BufferGeometryUtils.js (imported by GLTFLoader)
test/                        # test suite (dev-only, not packaged)
build/                       # check_glb.rb, package.rb (dev-only)
```

Note on layout: the registrar lives at the repository root rather than in
`src/` so that repository layout == RBZ layout == installed Plugins layout
(the registrar and the extension folder must be siblings).

### Tests

The suite runs **inside SketchUp** (27 tests: GLB structure, geometry and
transforms, materials/textures/UVs, instancing/metadata, export edge
cases). Scenes are built inside an undo operation that is always aborted,
so the user's model is never touched. Open the Ruby console and run:

```ruby
load "U:/dn1code/sketchup_ext/dn1sup_export_3d/dn1sup_export_3d/test/run_all.rb"
```

`run_all.rb` force-reloads the extension code, so it always exercises the
current sources. A GLB can be checked outside SketchUp with:

```
ruby build/check_glb.rb path/to/model.glb
```

### Packaging

```
ruby build/package.rb     # -> build/dn1sup_export_3d.rbz (uses bsdtar, no gems)
```

### Known limitations

- Component definitions referenced cyclically are cut off with a warning
  (SketchUp's UI prevents creating them; the guard is defensive).
- Faces with holes rely on `face.mesh` triangulation, which matched
  `face.area` in all tested cases; pathological self-intersecting input
  geometry is exported as SketchUp triangulates it.
- Normals are per-face (flat shading); non-uniform instance scaling is
  represented faithfully in node matrices.

## License

MIT — see [LICENSE](LICENSE). Bundled Three.js modules keep their
[MIT notice](dn1sup_export_3d/vendor/three/LICENSE).
