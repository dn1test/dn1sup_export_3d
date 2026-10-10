# Changelog (Лог изменений)

Лог изменений **DN1Sup Export 3D** (`dn1sup_export_3d`).
Формат версий соответствует правилам `MAJOR.MINOR.PATCH`.

## [0.8.2] — 2026-10-09

- fix(ci): pick System32 bsdtar explicitly - GNU tar on runners cannot write ZIP
- feat: publish for Extension Store - registrar ext.id, registry.json, release workflow; docs: PUBLISHING.md + README link
- feat: shared CEF event bridge, apply to viewer too (0.8.3)
- fix: result-panel clicks survive SU2026 CEF listener loss
- fix: deliver picked folder to dialog after native modal
- fix: dialog buttons dead in SketchUp CEF - re-register Vue listeners
- fix: reset export dialog state on reopen
- feat: folder-only export dialog with auto Latin file name (0.8.0)
- feat: viewer edge outlines and material-faithful lighting (0.7.0)
- docs: align AGENTS.md and README with the Vue/Vite build pipeline
- chore: add third-party license notices and package guard (AGENTS.md #34)
- feat: rewrite viewer and export dialog UI in Vue 3 + Tailwind, add single-file HTML export
- feat: viewer object tree panel and SketchUp toolbar
- feat: user-facing export dialog (AGENTS.md Phase 9)
- feat: selection pid chain, vendored BufferGeometryUtils, docs and packaging
- test: in-SketchUp test suite with pure-Ruby GLB validator (27 tests)
- fix: correct axis mapping, node tree and object identity; add textures, UVs and HtmlDialog bridge
- chore: import existing exporter/viewer prototype (pre-rewrite baseline)
