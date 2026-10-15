# Changelog (Лог изменений)

Лог изменений **DN1Sup Export 3D** (`dn1sup_export_3d`).
Формат версий соответствует правилам `MAJOR.MINOR.PATCH`.

## [0.9.2] — 2026-10-15

- chore: синхронизация общего апдейтера v3 (`UPDATER_VERSION = 3`,
  `ensure_updater!` в менеджере догружает свою копию, если загруженная
  старше) — чинит соседство копий разных версий в памяти SketchUp.
- fix: `product_status` / `install_from_url` / `pick_freshest` принимают
  позиционный Hash опций плюс kwargs (совместимость Ruby 2.7-упаковки) —
  больше нет «wrong number of arguments (given 4, expected 3)» при
  установке/проверке обновлений из Store.
- chore: `ext.creator` / `ext.copyright` — `DN1Sup`.

## [0.9.1] — 2026-10-15

- fix: `build/package.rb` пакует `.rbz` чистым Ruby (stdlib `zlib`)
  вместо bsdtar (`tar -a`): ZIP от bsdtar SketchUp 2026 отклоняет при
  установке («Could not unzip archive» — проверено живьём, в т.ч. на
  минимальной пробе из 2 файлов); тот же состав через Deflate ставится
  (`install_from_archive → true`), тесты зелёные.
- fix: `require "tempfile"` под гардом `unless defined?(Tempfile)` —
  в сессиях с посторонним загрузчиком повторный require ронял загрузку
  (`superclass mismatch for class Tempfile`).

## [0.9.0] — 2026-10-15

- fix: синхронизирован `dn1sup_updater.rb` с менеджером — `pick_freshest`
  с kwargs (`installed_at:`, `github_time:`, `local_time:`) плюс
  `local_dev_mtime`/`to_unixtime`; чинит «Исключение при установке:
  wrong number of arguments (given 4, expected 3)» из Store-менеджера,
  когда старая копия модуля затирала новую.
- Удалён функционал dev/prod (второй id `dn1sup_export_3d_dev`): удалены
  `DEV_BUILD`, поле `dev_build` в состоянии диалога и бейдж DEV в шапке.
  Разработка — рабочая копия под тем же id. Файлы `.sketchup_dev.json`
  удалены.

## [0.8.5] — 2026-10-12

- feat: `Dn1supExport3d.unload!` — подготовка к переключателю каналов dev/prod
  в dn1sup_ext_manager (v0.12.0): выгрузка неймспейса закрывает окно
  просмотрщика (`close_dialog`) и скрывает тулбар; пункты меню остаются до
  перезапуска SketchUp (ограничение SketchUp API).

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
