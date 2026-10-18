# Changelog (Лог изменений)

Лог изменений **DN1Sup Export 3D** (`dn1sup_export_3d`).
Формат версий соответствует правилам `MAJOR.MINOR.PATCH`.

## [0.9.13] — 2026-10-18

### DN1Sup Export 3D (v0.9.13)
- **Тулбар не создаётся, когда работает общая панель DN1Sup.** Пока в
  менеджере выключен параметр «Показывать отдельные тулбары расширений»
  (по умолчанию), свой тулбар не создаётся — его нет и в списке панелей
  SketchUp (View → Toolbars). Кнопка экспорта остаётся на общей панели
  и в меню DN1Sup.

## [0.9.12] — 2026-10-18

### DN1Sup Export 3D (v0.9.12)
- **Меню перенесено в общее «Extensions → DN1Sup».** Раньше подменю
  «Web 3D Export» добавлялось в меню «Plugins» — теперь используется
  общий корень всех расширений DN1Sup (`Dn1sup.common_menu`), как в
  остальных расширениях экосистемы.

## [0.9.11] — 2026-10-17

### DN1Sup Export 3D (v0.9.11)
- **Копия общего апдейтера выровнена с мастер-версией v5.** Раньше
  репозиторий нёс отдельную ветку v4 (без status_cb); теперь — единая
  копия для всех расширений DN1Sup: только GitHub Releases, заглушки
  локальных методов для менеджеров старых версий.
## [0.9.10] — 2026-10-17

### DN1Sup Export 3D (v0.9.10)
- **Обновление — только из GitHub Releases.** Локальные источники обновления
  удалены из апдейтера (`UPDATER_VERSION` 3 → 4): проверка и установка —
  только релиз + `registry.json` репозитория на GitHub. Вырезаны local-first
  логика, `dev_dir` из MANIFEST, ENV-переменные (`DN1SUP_*_DEV_DIR`,
  `SKETCHUP_EXT_ROOT`), сборка .rbz из папки разработки и копирование в
  Plugins. Для менеджера расширений старых версий оставлены заглушки
  («локального источника нет»); кнопка проверки обновлений и фоновая
  проверка работают как прежде, но только по GitHub.

## [0.9.9] — 2026-10-16

### DN1Sup Export 3D (v0.9.9)
- **Фирменная плитка DN1Sup в шапке GUI** — та же плитка, что в каталоге
  Extension Store (цветной квадрат, знак с «воздухом»); работает в светлой
  и тёмной теме. Источник — `dn1sup_extensions` (`tools/make_icons.rb`).
## [0.9.8] — 2026-10-16

### DN1Sup Export 3D (v0.9.8)
- **Фирменный знак тулбара DN1Sup** — единый стиль каталога Extension
  Store: изометрический куб (cyan), прозрачный фон, вырезы — настоящая прозрачность
  (SVG-маска; PNG 16/24 — альфа-канал). Источник знака —
  `dn1sup_extensions` → `icons/products/` (`tools/make_icons.rb`).


## [0.9.7] — 2026-10-16

- feat: новая иконка тулбара — куб + зелёный бейдж со стрелкой экспорта:
  новый векторный исходник `dn1sup_export_3d/icons/export.svg`, растры
  `export_16.png` / `export_24.png` перегенерированы скриптом
  `tools/make_icons.rb` (чистый Ruby, 4x суперсэмплинг).
- fix: `write_png` в `tools/make_icons.rb` пишет корректный IHDR (13 байт,
  `N2 + C5`) — вариант `pack("N5")` из `dn1sup_create_project` даёт 20 байт
  и невалидный PNG.

## [0.9.6] — 2026-10-16

- fix(test): `write_png` в `test/test_helper.rb` создаёт каталог назначения
  (`mkdir_p`) перед записью PNG-фикстуры — убран `ENOENT` при чистом tmp.

## [0.9.5] — 2026-10-16

- chore: убран переходный чек маркера `.sketchup_dev.json` из `dev_source?`
  в `shared/dn1sup_updater.rb` и внутренней копии `dn1sup_updater.rb`
  (период миграции со старых `_dev`-установок завершён); self-update
  рабочей копии определяется только по пути загрузки (вне папки `Plugins`).

## [0.9.4] — 2026-10-15

- fix: лоадер не регистрирует расширение, если нет папки с `main.rb`
  (частично отзеркаленный профиль) — вместо модальной ошибки SketchUp
  «Failed to load file» пропуск с предупреждением в консоли Ruby.

## [0.9.3] — 2026-10-15

- fix: лоадер `dn1sup_export_3d.rb` устойчив к битой установке (неполный
  клон профиля: есть `.rb`, нет папки с `version.rb`) — вместо `LoadError`
  при старте SketchUp расширение регистрируется с версией-заглушкой `0.0.0`.
- chore: `build/package.rb` требует `version.rb` с явным расширением.

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
