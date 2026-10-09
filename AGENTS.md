# AGENTS.md

## Project

SketchUp 2026 Extension for exporting SketchUp models to a web-compatible 3D format and viewing them through HTML/JavaScript.

Primary target:

```text
SketchUp 2026
Ruby 3.2 (bundled)
        │
        ▼
   Ruby Extension
        │
        ▼
      GLB
        │
        ▼
 HTML / JavaScript
        │
        ▼
 Three.js Web Viewer
```

The extension must allow a SketchUp model to be exported for interactive viewing in a browser or SketchUp `UI::HtmlDialog`.

---

# 1. Core requirements

The project must:

- target SketchUp 2026;
- use the Ruby version/API provided by SketchUp;
- be implemented primarily in Ruby;
- use `SketchupExtension`;
- support `UI::HtmlDialog` for the local viewer;
- export SketchUp geometry to a web-compatible 3D format;
- use GLB/glTF as the primary web model format;
- preserve useful SketchUp model structure;
- preserve materials and textures where technically possible;
- preserve stable object identifiers;
- allow JavaScript to identify/select exported objects;
- be suitable for both:
  - local HTML viewer inside SketchUp;
  - external web site;
- avoid unnecessary external dependencies;
- avoid Docker;
- avoid requiring Python;
- avoid requiring a separate server for basic local viewing.

---

# 2. Important development rule

Do not guess SketchUp API behavior.

If an API method, class, property, file format behavior, or SketchUp 2026 limitation is uncertain:

1. check the official SketchUp Ruby API documentation;
2. inspect the actual SketchUp API behavior if possible;
3. only then implement the feature.

Never present an assumption as a confirmed API capability.

---

# 3. Target environment

Primary environment:

```text
SketchUp 2026
Windows 11
Ruby 3.2 (interpreter bundled with SketchUp 2026)
```

The extension must use the Ruby environment shipped with SketchUp.

Do not require the user to install:

- Ruby;
- Python;
- Node.js;
- Rust;
- Docker;

for the basic extension to function.

Node.js may be used during development/building of the web frontend, but the distributed extension must contain the required built assets.

---

# 4. Architecture

Use a clear separation between:

```text
SketchUp Extension
│
├── Ruby
│   ├── extension entry point
│   ├── exporter
│   ├── geometry processing
│   ├── material processing
│   ├── texture processing
│   ├── object metadata
│   └── HTMLDialog bridge
│
└── Web Viewer
    ├── HTML
    ├── CSS
    ├── JavaScript
    └── Three.js
```

Actual structure (repository root). The registrar sits at the root, not in
`src/`, so that repository layout == RBZ layout == installed Plugins layout:

```text
dn1sup_export_3d/                 (repository root)
│
├── AGENTS.md
├── README.md
├── PUBLISHING.md                 (Extension Store publishing rules)
├── LICENSE                       (MIT)
├── registry.json                 (Extension Store card: id, name, version;
│                                  mirrors VERSION, enforced by package.rb)
│
├── dn1sup_export_3d.rb           (lightweight registrar, at the root)
│
├── dn1sup_export_3d/             (extension folder = RBZ payload)
│   ├── main.rb                   (menu, toolbar, viewer HtmlDialog, export)
│   ├── version.rb                (VERSION — single authoritative source)
│   ├── logger.rb
│   ├── filename.rb               (safe output filename transliteration)
│   │
│   ├── exporter/
│   │   ├── glb_exporter.rb       (GLB assembly + node metadata/extras)
│   │   ├── geometry.rb           (triangulation via Sketchup::Face#mesh)
│   │   ├── materials.rb          (materials + texture embedding)
│   │   ├── coordinate.rb         (the only place axes/units are converted)
│   │   └── buffer.rb             (GLB binary buffer writer)
│   │
│   ├── viewer/
│   │   ├── index.html
│   │   └── assets/
│   │       └── viewer.js         (built bundle, committed)
│   │
│   ├── ui/
│   │   ├── export_dialog.rb
│   │   ├── export_driver.rb      (stepwise export via UI.start_timer)
│   │   ├── selection_sync.rb     (SelectionObserver: dialog follows the
│   │   │                          SketchUp selection while the dialog is open)
│   │   ├── export_dialog.html
│   │   └── assets/
│   │       └── export_dialog.js  (built bundle, committed)
│   │
│   ├── icons/                    (export_16.png, export_24.png)
│   ├── test/                     (in-SketchUp tests; excluded from RBZ)
│   └── THIRD-PARTY-NOTICES.txt
│
├── web/                          (npm/Vite sources of the GUIs; not distributed)
│   ├── package.json
│   ├── index.html                (viewer entry)
│   ├── export_dialog.html        (dialog entry)
│   ├── vite.viewer.config.mjs
│   ├── vite.dialog.config.mjs
│   ├── scripts/
│   │   └── vite-plugin-classic-html.mjs
│   └── src/
│
├── build/                        (dev tooling; not distributed)
│   ├── package.rb                (RBZ packager)
│   ├── check_glb.rb              (standalone GLB validator, plain Ruby)
│   └── gen_icons.rb
│
└── .github/workflows/release.yml (tag v* → package.rb → .rbz attached to
                                    a GitHub Release; no npm in CI)
```

Texture handling lives in `exporter/materials.rb`; node metadata lives in
`exporter/glb_exporter.rb` — there are no separate `textures.rb`/`metadata.rb`.

The exact directory structure may evolve if there is a clear technical reason.

---

# 5. SketchUp extension registration

The extension must follow SketchUp's normal extension registration pattern.

Use:

```ruby
SketchupExtension.new(...)
Sketchup.register_extension(...)
```

The top-level registration file should remain lightweight.

Do not put the entire extension implementation into the registration file.

Example conceptual structure:

```ruby
module WebViewerExtension
  # implementation
end
```

Use a unique top-level module namespace.

Do not pollute the global Ruby namespace.

---

# 6. Ruby namespace

Use one main namespace.

Example:

```ruby
module WebViewer
  VERSION = "0.1.0"
end
```

All implementation classes should be placed under this namespace.

Example:

```ruby
module WebViewer
  module Exporter
    class GLBExporter
    end
  end
end
```

Avoid generic global classes such as:

```ruby
class Exporter
end
```

---

# 7. Export pipeline

The exporter should work approximately as follows:

```text
Sketchup.active_model
        │
        ▼
model.entities / selected entities
        │
        ▼
recursive traversal
        │
        ├── Group
        ├── ComponentInstance
        ├── Face
        ├── Edge
        └── nested entities
        │
        ▼
triangulation
        │
        ▼
vertices
normals
UV coordinates
indices
materials
        │
        ▼
GLTF representation
        │
        ▼
GLB binary
```

The exporter must not modify the user's SketchUp model.

Exporting must not:

- explode groups;
- explode components;
- change materials;
- change layers/tags;
- change visibility;
- alter transformations;
- modify component definitions.

---

# 8. Geometry

The exporter must correctly handle:

- `Sketchup::Face`;
- nested groups;
- component instances;
- nested component instances;
- transformations;
- mirrored transformations;
- face orientation;
- triangulation;
- normals;
- UV coordinates where available.

Pay particular attention to transformation composition.

For nested instances:

```text
Root transform
    ×
Group transform
    ×
Component transform
    ×
Nested component transform
```

The final vertex positions must be calculated using the correct accumulated transformation.

Do not assume that `entities` coordinates are already in world coordinates.

---

# 9. Triangulation

GLB/glTF geometry should ultimately consist of triangles.

SketchUp faces can contain:

- triangles;
- quads;
- polygons;
- holes;
- inner loops.

The implementation must use SketchUp's available mesh/geometry APIs appropriately.

Do not implement a custom polygon triangulation algorithm unless there is a demonstrated need.

Prefer SketchUp's own geometry information where possible.

Validate:

- convex faces;
- concave faces;
- faces with holes;
- reversed faces;
- non-planar/problematic geometry.

---

# 10. Coordinate system

SketchUp and glTF use different coordinate conventions.

The exporter must explicitly define the coordinate-system conversion.

Do not silently assume that coordinates can simply be copied.

Document:

- axis mapping;
- handedness;
- up axis;
- units;
- scaling.

The conversion must be centralized in one place.

Example conceptual API:

```ruby
CoordinateConverter.transform(position)
CoordinateConverter.normal(normal)
CoordinateConverter.transform_matrix(transformation)
```

Do not scatter coordinate conversions throughout the exporter.

---

# 11. Units

SketchUp internally uses its own length representation.

The exported model must use a clearly documented unit convention.

The web representation is:

```text
1 unit = 1 meter
```

This is the confirmed glTF 2.0 convention — the spec defines geometry units
as meters. The single conversion constant `INCH_TO_METER = 0.0254` (SketchUp
stores lengths in inches) lives in `exporter/coordinate.rb`.

All conversion constants must be centralized.

Never hard-code unexplained conversion factors throughout the code.

---

# 12. Materials

Export SketchUp materials to glTF-compatible materials.

At minimum support:

- material name;
- diffuse/base color;
- opacity;
- texture;
- texture coordinates.

Where possible support:

- roughness;
- metallic properties;
- normal maps;
- transparency.

Do not invent physically-based values when SketchUp does not provide equivalent information.

If a property cannot be reliably mapped, document the fallback.

---

# 13. Textures

Texture handling must:

1. detect whether a material has a texture;
2. obtain the texture image;
3. export the image into the web package or embed it in GLB;
4. preserve UV coordinates;
5. reference the texture correctly from glTF.

Prefer GLB embedding where practical.

The implementation must correctly handle texture paths that contain:

- spaces;
- Unicode characters;
- non-ASCII filenames.

Do not assume all textures are JPEG.

Support common image formats that can be reliably consumed by the browser/glTF pipeline.

---

# 14. Object identity

Object identity is important.

The browser must be able to identify which SketchUp object generated a particular mesh/node.

Each exported logical object should have metadata such as:

```json
{
  "sketchup_id": 123456,
  "name": "Cabinet",
  "type": "component"
}
```

Do not rely exclusively on array indexes.

SketchUp `persistent_id` should be investigated and preferred when appropriate because ordinary runtime entity IDs may not provide the desired long-term identity.

Before implementation, verify the exact SketchUp 2026 API behavior for persistent IDs.

---

# 15. Metadata

The exporter should support an optional metadata structure.

Example:

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

Metadata may be stored in glTF extras or another documented mechanism.

Do not duplicate large amounts of geometry data in metadata.

Metadata should remain compact.

---

# 16. Groups and components

The exporter must distinguish:

```text
Group
ComponentDefinition
ComponentInstance
```

A component definition may be reused by multiple instances.

Avoid unnecessarily duplicating geometry when the glTF structure can represent reusable meshes/nodes.

However, correctness is more important than premature optimization.

First implement:

```text
correct geometry
correct transforms
correct materials
correct metadata
```

Then optimize duplication.

---

# 17. Visibility

Respect SketchUp visibility.

At minimum consider:

- hidden entities;
- hidden groups;
- hidden component instances;
- hidden tags/layers;
- section-related visibility where applicable.

The exporter's visibility rules must be explicitly documented.

Do not silently export hidden geometry unless the user selected an explicit option to do so.

---

# 18. Selection modes

The exporter should eventually support:

```text
Export entire model
Export current selection
Export visible geometry
```

Design the exporter API so that this can be implemented without rewriting the geometry pipeline.

Example:

```ruby
Exporter::GLBExporter.new(
  model: Sketchup.active_model,
  scope: :selection
)
```

Possible scopes:

```ruby
:all
:selection
:visible
```

Status: `:all` and `:selection` are implemented (`SCOPES` in
`exporter/glb_exporter.rb`); `:visible` is pending.

---

# 19. Web viewer

The viewer should use Three.js unless there is a documented reason to choose another engine.

Responsibilities:

- load GLB;
- display model;
- orbit camera;
- zoom;
- pan;
- fit model;
- reset camera;
- select objects;
- highlight selected object;
- display metadata;
- optionally hide/show objects;
- optionally switch display modes.

Keep the viewer independent from SketchUp.

The same viewer should ideally work in:

```text
SketchUp UI::HtmlDialog
```

and:

```text
ordinary web browser
```

---

# 20. Three.js

Three.js should be used through `GLTFLoader` for GLB loading.

Do not make the viewer dependent on a remote CDN for the distributed SketchUp extension.

Three.js (and the other runtime GUI libraries, e.g. Vue.js) are npm
dependencies of the `web/` project and are bundled by Vite into the
committed single-file IIFE assets (`viewer/assets/viewer.js`,
`ui/assets/export_dialog.js`). Their MIT license notices must ship with
every distributed artifact (THIRD-PARTY-NOTICES.txt / HTML comment).

A production web deployment may use npm/bundling/CDN according to the website's architecture.

---

# 21. HTMLDialog communication

The Ruby side and JavaScript side must communicate through a small, explicit bridge.

Conceptually:

```text
Ruby
 │
 │ execute_script / callbacks
 ▼
JavaScript
 │
 │ event
 ▼
Ruby
```

Keep the bridge API documented.

Example conceptual commands:

```text
loadModel
selectObject
getObjectInfo
exportModel
refreshModel
```

Actual bridge implemented in this project (see README for the full table):

```text
JS → Ruby action callbacks
  viewer dialog:  viewer_ready, object_selected
  export dialog:  dialog_ready, browse_output, export_start, export_cancel,
                  preview_refresh, preview_object_selected, open_viewer,
                  open_folder, open_html, close

Ruby → JS (window.exporter.*)
  receiveState, setOutputFolder, receiveProgress, receivePreviewStatus,
  receivePreviewStart, receivePreviewChunk, receivePreviewEnd, receiveSelection
```

All payloads are JSON (`JSON.parse` / `JSON.generate` on the Ruby side;
U+2028/U+2029 are escaped when embedding into `execute_script`).

Do not allow arbitrary Ruby code to be executed from JavaScript.

Never construct Ruby source code from unsanitized user input.

---

# 22. Viewer API

The JavaScript viewer should expose a small API.

Example:

```javascript
viewer.loadModel(url);

viewer.selectObject(id);

viewer.focusObject(id);

viewer.getObject(id);

viewer.clearSelection();
```

The actual `window.viewer` API (exported by `web/src/viewer/App.vue`) is a
superset of the example:

```javascript
viewer.loadModel(url);
viewer.selectObject(pid);
viewer.focusObject(pid);
viewer.getObject(pid);
viewer.setShowObject(pid, visible);
viewer.clearSelection();
viewer.toggleEdges();
viewer.fit();
viewer.reset();
viewer.on(event, callback);  // loadStart, progress, viewerReady, loadError,
                             // objectSelected, selectionCleared,
                             // objectVisibilityChanged, wireframe, edges
viewer.selectedPid;          // getter
```

The viewer should communicate through events rather than tightly coupling UI components to Three.js internals.

Example:

```javascript
viewer.on("objectSelected", callback);
```

---

# 23. Web-site deployment

The exported model should be usable independently of SketchUp.

Preferred package:

```text
model/
├── model.glb
├── metadata.json
└── preview.jpg
```

or:

```text
model.glb
```

if metadata is embedded.

The website should be able to load:

```text
https://example.com/models/project/model.glb
```

without requiring SketchUp.

---

# 24. Security

Never trust model metadata when displayed on a website.

Escape text inserted into HTML.

Do not use:

```javascript
element.innerHTML = userData;
```

unless the data is explicitly sanitized.

Prefer:

```javascript
element.textContent = userData;
```

Do not execute JavaScript originating from model metadata.

---

# 25. Performance

Large furniture/interior models can contain substantial geometry.

Design for:

```text
10 MB
50 MB
100+ MB
```

GLB files.

Avoid unnecessary allocations.

Do not create thousands of independent Three.js objects if a smaller number of meshes/nodes can represent the same model.

Possible later optimizations:

- mesh deduplication;
- material deduplication;
- geometry merging;
- instancing;
- Draco compression;
- Meshopt compression;
- texture resizing;
- level of detail.

Do not introduce compression before the basic exporter is correct.

---

# 26. Large models

The exporter must not freeze SketchUp unnecessarily during long exports.

If export becomes expensive, investigate:

- progress dialog;
- staged processing;
- user cancellation;
- `UI.start_timer`;
- incremental processing.

Do not use threads with SketchUp API objects unless SketchUp explicitly permits the operation.

Assume SketchUp API access is not thread-safe unless documentation proves otherwise.

---

# 27. Error handling

Errors must be useful to the user.

Bad:

```text
Export failed
```

Better:

```text
GLB export failed.

Object:
Kitchen / Cabinet / Door

Reason:
Unable to obtain texture image.
```

Log technical details separately.

Do not silently rescue all exceptions.

Avoid:

```ruby
rescue StandardError
end
```

unless there is a specific documented reason.

---

# 28. Logging

Implement a simple logger.

Example:

```ruby
Logger.info("Starting GLB export")
Logger.info("Faces: #{face_count}")
Logger.info("Materials: #{material_count}")
Logger.info("Textures: #{texture_count}")
```

Do not log sensitive filesystem information unnecessarily.

Provide a debug mode.

---

# 29. Testing

Tests should cover at least:

### Geometry

- simple cube;
- rectangular cabinet;
- rotated component;
- nested groups;
- nested components;
- mirrored component;
- concave face;
- multiple materials.

### Materials

- solid color;
- texture;
- transparent material;
- repeated material.

### Structure

- group;
- component definition;
- multiple component instances.

### Export

- empty model;
- selection export;
- large model;
- Unicode filenames;
- paths containing spaces.

### Viewer

- GLB loading;
- camera;
- selection;
- object metadata;
- object highlighting.

---

# 30. Development workflow

When modifying the exporter:

1. inspect the relevant SketchUp API;
2. make the smallest change;
3. test on a minimal `.skp`;
4. test nested geometry;
5. test the generated GLB in the browser;
6. test the same GLB in the SketchUp HTMLDialog;
7. only then optimize.

Never change several independent parts of the exporter at once without testing.

---

# 31. Debugging GLB

When an exported GLB is invalid:

Check in this order:

```text
1. GLB container
2. JSON chunk
3. BIN chunk
4. buffer lengths
5. bufferViews
6. accessors
7. meshes
8. nodes
9. scenes
10. materials
11. textures
```

Use a known-good GLB as a reference.

Do not randomly modify offsets and buffer lengths.

---

# 32. Build system

The GUIs (viewer and export dialog) are Vue 3 + Tailwind apps built by
Vite from the `web/` sources:

```text
web/
├── package.json
├── index.html              (viewer entry)
├── export_dialog.html      (dialog entry)
├── vite.viewer.config.mjs
├── vite.dialog.config.mjs
└── src/
```

`npm run build` writes the built assets directly into the extension
folders (`dn1sup_export_3d/viewer/`, `dn1sup_export_3d/ui/`). The output
is a classic-script IIFE bundle (`base: "./"`, `target: "es2017"`, CSS
inlined) so it works in `UI::HtmlDialog` and from a double-clicked
`file://` page. Built bundles are committed to git.

The distributed RBZ is packaged from the extension folder with
`ruby build/package.rb` and must not require npm; `package.rb` refuses
to run when the built bundles are missing.

Releases: `.github/workflows/release.yml` runs on a `v*` tag, executes
`ruby build/package.rb` (no npm step — the committed bundles are used) and
attaches `build/dn1sup_export_3d.rbz` to a GitHub Release. Store publishing
rules are documented in PUBLISHING.md.

---

# 33. Dependencies

Minimize dependencies.

Every dependency must have a reason.

For each dependency document:

```text
name
version
license
purpose
distribution method
```

Do not add a library merely because it makes a small task easier.

---

# 34. Licensing

Before distributing the extension:

- verify SketchUp API usage requirements;
- verify Three.js license;
- verify all bundled libraries;
- verify texture/image libraries;
- include required license notices.

Do not copy third-party code without checking its license.

---

# 35. RBZ packaging

The final extension should be distributable as:

```text
extension_name.rbz
```

The RBZ must contain only the files required by the extension.

Do not include:

```text
node_modules/
.git/
tests/
temporary files
large source assets
```

unless explicitly required.

---

# 36. Versioning

Use semantic versioning:

```text
MAJOR.MINOR.PATCH
```

Example:

```text
0.1.0
0.2.0
1.0.0
```

The authoritative version source is `dn1sup_export_3d/version.rb`
(`Dn1supExport3d::VERSION`).

Two mirrors must be bumped in the same commit and must always carry the
same value:

- `registry.json` — the Extension Store card; the store reads its
  `version` when checking for updates;
- `web/package.json` — dev-only npm metadata (not distributed).

`build/package.rb` verifies that both mirrors match `VERSION` and aborts
on mismatch, so the release CI fails instead of shipping a desynchronized
store card.

---

# 37. Git

Use Git.

Recommended branches:

```text
main
develop
feature/*
fix/*
```

Commits should be small and meaningful.

Examples:

```text
feat: add SketchUp face triangulation
feat: export material textures
feat: add GLB metadata
fix: preserve nested component transforms
fix: correct mirrored component winding
```

Do not combine unrelated changes in one commit.

---

# 38. AI agent behavior

The AI coding agent must:

- inspect existing code before modifying it;
- preserve working functionality;
- avoid unnecessary rewrites;
- explain architectural changes;
- verify assumptions;
- prefer official documentation for SketchUp API questions;
- not invent API methods;
- not invent glTF/GLB structures;
- not silently change dependencies;
- not introduce Python unless explicitly requested;
- not introduce Docker;
- not replace Ruby with another backend language.

If requirements are ambiguous and the decision affects architecture, ask the user before implementing.

---

# 39. Important constraint: no assumptions

When information is missing, do not guess.

Examples:

Bad:

> SketchUp 2026 definitely provides X.

Good:

> I need to verify whether SketchUp 2026 exposes X through the Ruby API before implementing this.

If two implementation approaches are possible and the choice affects the architecture, explain both and ask for a decision.

---

# 40. Initial implementation phases

Implement in this order.

## Phase 1 — Extension skeleton

Create:

```text
SketchUp Extension
├── registration
├── menu item
└── basic command
```

The command should prove that the extension loads correctly.

---

## Phase 2 — Geometry extraction

Implement:

```text
Face
Group
ComponentInstance
Transformation
```

Export a minimal internal geometry representation.

Do not implement GLB yet.

---

## Phase 3 — GLB generation

Implement:

```text
buffers
bufferViews
accessors
meshes
nodes
scenes
```

Generate the smallest valid GLB possible.

Test it independently in a browser.

---

## Phase 4 — Materials

Add:

```text
base color
texture
UV
opacity
```

---

## Phase 5 — Metadata

Add:

```text
persistent_id
name
entity type
hierarchy
```

---

## Phase 6 — Three.js viewer

Implement:

```text
load GLB
camera
orbit
zoom
pan
fit
```

---

## Phase 7 — Object selection

Implement:

```text
click object
       ↓
Three.js node
       ↓
SketchUp persistent_id
       ↓
metadata
```

---

## Phase 8 — SketchUp HTMLDialog

Connect:

```text
Ruby
  ↕
HTMLDialog
  ↕
Three.js
```

---

## Phase 9 — Production export

Add:

- progress;
- cancellation;
- error reporting;
- export options;
- output directory;
- filename handling.

---

# 41. Future features

Potential future functionality:

```text
☐ section planes
☐ camera export
☐ scenes/pages
☐ shadows
☐ environment lighting
☐ PBR materials
☐ object tree
☐ object visibility
☐ measurement tool
☐ annotations
☐ dimensions
☐ screenshots
☐ AR
☐ WebXR
☐ model sharing
☐ cloud upload
☐ automatic website publishing
```

Do not implement future functionality until the core exporter/viewer is stable.

---

# 42. Definition of done

The first production-capable version is considered complete when:

- SketchUp 2026 loads the extension;
- a model can be exported;
- GLB is valid;
- geometry is positioned correctly;
- nested transformations work;
- materials are visible;
- textures work;
- model can be loaded by Three.js;
- camera controls work;
- objects can be selected;
- selected objects can be mapped back to SketchUp persistent IDs;
- the same GLB can be used on an external website;
- no external Ruby/Python installation is required;
- the extension can be packaged as RBZ;
- licensing information is included;
- errors are reported clearly.

---

# 43. Priority order

When trade-offs are necessary, use this priority:

```text
1. Correctness
2. SketchUp API compatibility
3. GLB validity
4. Data integrity
5. Stability
6. Performance
7. Visual quality
8. Convenience
9. Optimization
```

Never sacrifice model correctness for performance without explicit approval.

---

# 44. Final architectural goal

The final system should make this workflow possible:

```text
                 SKETCHUP 2026
                      │
                      │ Ruby API
                      ▼
              ┌───────────────┐
              │   Exporter    │
              └───────┬───────┘
                      │
             ┌────────┴────────┐
             ▼                 ▼
          model.glb       metadata
             │                 │
             └────────┬────────┘
                      ▼
               THREE.JS VIEWER
                      │
          ┌───────────┼───────────┐
          ▼           ▼           ▼
       Browser    HTMLDialog   Website
          │           │           │
          └───────────┴───────────┘
                      │
                      ▼
               Interactive 3D
```

The same exported model should be reusable across all viewers.

The exporter is the core of the system. Keep the exporter independent from the UI so that it can eventually be used for:

- local preview;
- HTMLDialog;
- web site;
- cloud storage;
- API-based model publishing;
- future AR/WebXR applications.
