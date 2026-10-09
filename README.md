# dn1sup_export_3d

SketchUp 2026 extension that exports models (or the current selection) to
**glTF 2.0 / GLB** and views the result interactively with **Three.js** —
in a browser, or right inside SketchUp in an `UI::HtmlDialog`. Both GUIs
(the export dialog and the 3D viewer) are built with **Vue 3 + Tailwind CSS**.

```
SketchUp 2026 (Ruby API)
        │  dn1sup_export_3d (this extension)
        ▼
     model.glb  +  <name>_web3d/ package  +  <name>.html (single file)
        │
        ▼
Three.js viewer  (browser / HtmlDialog / any website / e-mail to a customer)
```

## Install

- **From RBZ**: SketchUp → Extension Manager → Install Extension →
  `build/dn1sup_export_3d.rbz` (build it with `ruby build/package.rb`; the
  archive ships pre-built UI assets, Node.js is only needed for development).
- **From source**: copy `dn1sup_export_3d.rb` and `dn1sup_export_3d/` into
  your SketchUp `Plugins` folder (both must sit side by side, exactly as in
  this repository).

After installation, the menu **Extensions → Web 3D Export** appears with:

- *Export to GLB…* — the export dialog (recommended);
- *Quick export current model to GLB* — one-click export of everything
  visible, straight to a save panel;
- *Quick export selection to GLB* — same, for the current selection.

### Export dialog

The dialog (Russian UI, 1200×760, resizable) is a two-pane workspace:

- **Left: live 3D preview** — the same Three.js engine as the big viewer,
  fed by the same exporter in a lightweight mode (textures off by default,
  toggleable via the «Текстуры» chip). The preview follows the export
  settings: switch the scope to «Только выделенное» (or change the
  selection) and it rebuilds automatically. The toolbar has refresh, fit,
  wireframe and edge-contour buttons; the bottom bar shows object and
  triangle counts. Building progress is reported in the preview overlay.
  **Selection is synchronized both ways**: clicking an object in the preview
  selects it in SketchUp, and SketchUp selection changes highlight in the
  preview (a `SelectionObserver` pushes the persistent ids while the dialog
  is open);
- **Right: settings and feedback**:
  - **Что экспортировать** — radio cards: the entire model or the current
    selection (live object count, disabled while the selection is empty);
  - **Куда сохранить** — folder field plus an «Обзор…» directory picker
    (defaults to the last used folder, then next to the model file; the
    choice is remembered between sessions). The file name is not typed:
    it is derived automatically from the model file name, transliterated
    to Latin characters (passport scheme: «Кухня-Мечта 2.0» →
    `Kuhnya-Mechta_2.0.glb`), so the artifacts stay web-safe; the dialog
    shows the resulting name before export;
  - **Один HTML-файл со встроенной моделью** — on by default: next to the
    GLB a single `<name>.html` is written with the viewer and the model
    (base64) inlined; a customer can open it by double-click, no hosting
    needed;
  - **Веб-пакет для сайта** — on by default: the `<name>_web3d/` folder
    described below;
  - **Включая скрытую геометрию** — off by default, matching the exporter's
    visibility rules;
  - **Progress with cancellation** — the export runs stepwise on a
    `UI.start_timer` loop (the UI thread stays responsive), with a progress
    bar, the current stage (Геометрия → Сборка GLB → Веб-пакет → Один
    HTML-файл), the name of the object being processed and a working
    «Отмена» button;
  - **Result panel** — faces/triangles/meshes/materials/textures, GLB size,
    elapsed time, the produced artifacts (single HTML with its size, web
    package), exporter warnings (e.g. a texture that fell back to a solid
    color), and the actions «Открыть 3D-просмотр», «Открыть HTML в браузере»
    and «Открыть папку».

Errors (bad path, empty selection, export failures) are reported inside the
dialog, not by crashing. The dialog uses the same bridge as the viewer:
`window.sketchup.*` for JS → Ruby (`dialog_ready`, `browse_output`,
`export_start`, `export_cancel`, `preview_refresh`, `preview_object_selected`,
`open_viewer`, `open_folder`, `open_html`, `close`, `pong`) and `execute_script`
for Ruby → JS (`window.exporter.receiveState / receiveProgress /
receivePreviewStatus / receivePreviewStart / receivePreviewChunk /
receivePreviewEnd / receiveSelection / setOutputFolder`).

**Bridge heartbeat.** SketchUp 2026 CEF can rot the dialog's JS ↔ Ruby channel
after it has lived through exports and native modals: action callbacks start
arriving with delays of tens of seconds, so result-panel buttons look dead
(the DOM-side facet of the same bug is worked around in
`web/src/shared/cef_event_bridge.js`). The dialog self-heals: a repeating
timer pings the page (`pong`), and when the roundtrip stalls for ~30 s the
dialog is recreated with its state preserved (a fresh HtmlDialog renderer has
a healthy channel — verified live). After two recreations without a single
pong the auto-heal stops and the user is told to reopen the dialog or
restart SketchUp.

The exporter writes `model.glb` next to the chosen path and copies a
self-contained web package to `<name>_web3d/`:

```
<name>_web3d/
├── model.glb        # the exported model
├── index.html
├── README.txt       # how to view / what to send (Russian)
└── assets/
    └── viewer.js    # the whole viewer (Vue + Three.js) as one classic script
<name>.html          # optional single file: viewer + model, double-clickable
```

Upload that folder anywhere — or send the single `<name>.html`; the same
GLB loads without SketchUp. (Browsers forbid `file://` pages from fetching
neighboring files, so the folder variant needs hosting or SketchUp; the
single-file variant embeds the model as a data URI and works anywhere.)

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

The viewer is a Vue 3 app (`web/src/viewer/`) over a framework-agnostic
Three.js engine (`ViewerEngine.js`). Layout: a header with the model name
and actions, a side panel with «Объекты» (search + object tree + per-object
visibility) and «Свойства» (selected object: name, type, persistent_id,
layer) tabs, a status bar with object/triangle counts and a mouse hint, and
full-screen overlays for loading (with progress), load errors (with a
double-click hint when opened as a local file) and help.

The scene uses a fixed studio setup on a white background: a
`RoomEnvironment` IBL for soft fill, a frontal key light and a back rim
light; both cast shadows onto an invisible `ShadowMaterial` floor, so a
soft shadow puddle stays visible under the model from any angle. The total
light energy is tuned so a lit face reads close to the material's real
color (neutral tone mapping, no wash-out), keeping the exported base
colors/textures recognizable. The light rig and shadow frustum are
re-fitted to the model bounds on every load.

Every mesh gets thin **contour lines** on its feature edges (SketchUp-like
look): an `EdgesGeometry` overlay per mesh with a 30° threshold, so
triangulation diagonals stay invisible while real shape breaks are drawn
as 1px dark lines. Edges are on by default, toggled from the header
(**E**), shared between instances of the same component, hidden together
with their object, and never intercept picking.

`window.viewer` exposes a small API (AGENTS.md §22):

```js
viewer.loadModel(url);      // load a GLB (http(s) or data: URI)
viewer.selectObject(pid);   // highlight by SketchUp persistent_id -> bool
viewer.focusObject(pid);    // move camera to the object -> bool
viewer.getObject(pid);      // extras.sketchup metadata or null
viewer.setShowObject(pid, visible); // viewer-side show/hide -> bool
viewer.clearSelection();
viewer.toggleEdges();       // contour lines on/off -> bool
viewer.fit(); viewer.reset();
viewer.on("viewerReady", cb);             // {url, objects, triangles}
viewer.on("objectSelected", cb);          // {pid, extras, chain|null}
viewer.on("selectionCleared", cb);
viewer.on("objectVisibilityChanged", cb); // {pid, visible}
viewer.on("loadError", cb);               // {url, error}
viewer.on("loadStart" / "progress" / "wireframe" / "edges", cb); // extra events
```

### Interaction

- **click** in 3D or in the tree selects the object (and syncs into SketchUp
  via the bridge); a 3D click switches the panel to «Свойства»;
- **double-click** focuses the camera on the object;
- the **eye** toggles viewer-side visibility of the object (hidden objects
  are also excluded from picking; hidden rows are struck through);
- the **filter box** matches names/types, showing matching rows and their
  ancestors; the ☰ button collapses the panel;
- header actions: fit (**F**), reset camera (**R**), wireframe (**W**),
  contour edges (**E**), PNG screenshot, fullscreen, help (**?**); **Esc**
  clears the selection or closes overlays.

Clicks raycast meshes (metadata is inherited from the owning node chain),
highlight via per-mesh material clones (instances share materials), and all
model data is rendered as text — never injected as HTML. Works both in a
plain browser and inside the HtmlDialog.

## Toolbar

The extension registers a **Web 3D Export** toolbar with a single cube-icon
button that opens the export dialog (see `build/gen_icons.rb` for how the
PNG icons are generated).

## HtmlDialog bridge

Attached in `main.rb` before `dialog.show`; JS calls Ruby through the
`window.sketchup` object that HtmlDialog injects (absent in normal browsers,
which doubles as feature detection):

| JS (viewer) | Ruby callback | Effect |
|---|---|---|
| `sketchup.viewer_ready(<n>)` | `viewer_ready` | logs that the viewer is up |
| `sketchup.object_selected(<pid>, …)` | `object_selected` | receives the clicked object's pid chain (part first, its component instance last) and selects the first pid that exists as an entity in the model |

Ruby → JS is available via `dialog.execute_script` (e.g.
`window.viewer.selectObject(...)`); callbacks must be (re-)attached before
`show`, because HtmlDialog clears them on close. The dialog reference is
retained by the module (an unreferenced HtmlDialog can be garbage-collected).

## Development

The GUI sources live in `web/` (Vue 3 + Tailwind CSS 4 + Vite + npm
`three`); the built assets are committed so that the RBZ can be packaged
without Node:

```
dn1sup_export_3d.rb          # registrar (sits next to the folder, like in Plugins)
dn1sup_export_3d/
├── main.rb                  # menus, export flow, web package, HtmlDialog bridge
├── ui/                      # export dialog: export_dialog.rb + built
│                            # export_dialog.html + assets/ (built from web/)
├── version.rb               # version source; mirrors: registry.json and
│                            # web/package.json (enforced by build/package.rb)
├── logger.rb
├── exporter/                # coordinate.rb, buffer.rb, geometry.rb,
│                            # materials.rb, glb_exporter.rb
└── viewer/                  # built viewer: index.html + assets/viewer.js
web/                         # GUI sources (dev-only, not packaged)
├── src/viewer/              # App.vue, engine/ViewerEngine.js, components/
├── src/dialog/              # export dialog app
├── src/shared/              # bridge.js, plural.js, format.js
├── index.html, export_dialog.html            # Vite entries
├── vite.viewer.config.mjs, vite.dialog.config.mjs
└── scripts/                 # build helpers (classic <script> tag plugin)
test/                        # test suite (dev-only, not packaged)
build/                       # check_glb.rb, package.rb (dev-only)
```

Both Vite builds target `es2017` and emit a single **IIFE** chunk per app
(the small `classicScriptTag` plugin rewrites Vite's `<script type=module>`
tag), so the result is a plain classic script: it runs in the HtmlDialog and
by double-clicking `index.html` on `file://`, where Chrome blocks ES
modules. CSS is inlined into the JS bundle by Vite for IIFE output.

To work on the GUI:

```
cd web
npm install
npm run dev:viewer     # or dev:dialog
npm run build          # writes dn1sup_export_3d/viewer/ and dn1sup_export_3d/ui/
```

### Dependencies

| Name | Version | License | Purpose | Distribution |
|------|---------|---------|---------|--------------|
| [three](https://threejs.org) | 0.186.1 | MIT | 3D engine, GLTFLoader/OrbitControls in the viewer | bundled into `viewer/assets/viewer.js`, notice in `THIRD-PARTY-NOTICES.txt` |
| [vue](https://vuejs.org) | 3.5.43 | MIT | UI framework of both GUIs | bundled into both `assets/*.js`, notice in `THIRD-PARTY-NOTICES.txt` |
| vite | 7.3.7 | MIT | bundler (dev-only) | not distributed |
| @vitejs/plugin-vue | 6.0.9 | MIT | Vue SFC support in Vite (dev-only) | not distributed |
| tailwindcss / @tailwindcss/vite | 4.3.3 | MIT | CSS framework (dev-only) | not distributed |

Node.js and the `web/` folder are needed only for development; the RBZ and
the exported web packages ship pre-built, committed assets only.

`build_single_file_html` (main.rb) inlines the built viewer and the GLB
(base64 `window.__VIEWER_BOOT.model`) into the single-file HTML at export
time — pure Ruby, no Node on the user's machine.

Note on layout: the registrar lives at the repository root rather than in
`src/` so that repository layout == RBZ layout == installed Plugins layout
(the registrar and the extension folder must be siblings).

### Tests

The suite runs **inside SketchUp** (33 tests: GLB structure, geometry and
transforms, materials/textures/UVs, instancing/metadata, export edge cases
including the dialog's `include_hidden` option, export stats, and the
stepwise export API — byte-identical output, in-memory GLB, progress
accounting, texture embedding toggle). Scenes
are built inside an undo operation that is always aborted, so the user's
model is never touched. Open the Ruby console and run:

```ruby
# replace with the path to your repository checkout
load "U:/path/to/dn1sup_export_3d/dn1sup_export_3d/test/run_all.rb"
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

MIT — see [LICENSE](LICENSE). The bundled three.js and Vue.js keep their MIT
notices in every distributed artifact: `THIRD-PARTY-NOTICES.txt` travels in
the RBZ and in every exported `_web3d/` package, and the single-file HTML
export embeds a short notice as an HTML comment.

---

## Публикация на GitHub

Как оформить репозиторий, чтобы DN1Sup Extension Store находил расширение,
показывал его в каталоге и предлагал обновления, — см. [PUBLISHING.md](PUBLISHING.md).
