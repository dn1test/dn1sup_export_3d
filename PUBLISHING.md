# Публикация расширения на GitHub

> Полная общая инструкция — мастер `U:\dn1code\sketchup_ext\PUBLISHING.md`
> (единственная полная копия: как Store ищет репозитории, обязательные
> требования, registry.json, версии и changelog, релизы). Ниже — локальный
> чек-лист этого репозитория.

## Чек-лист этого репозитория

| Требование | Статус |
|---|---|
| Имя `dn1sup_*` в аккаунте `dn1test` | ⏳ создайте репозиторий на GitHub и добавьте remote |
| Не archived | ✅ (применимо после публикации) |
| `registry.json` в корне `main` | ✅ создан (id, name, description, version 0.8.3) |
| Стабильные релизы с `.rbz` | ⏳ workflow `.github/workflows/release.yml` добавлен — нужен push и тег |
| Теги `vMAJOR.MINOR.PATCH` | ⏳ проставьте тег `v0.8.3` при публикации |
| Регистратор `<id>.rb` + `ext.id` | ✅ `ext.id = "dn1sup_export_3d"` задан |

Осталось опубликовать:

1. Создайте на GitHub `dn1test/dn1sup_export_3d` и добавьте remote:
   `git remote add origin git@github.com:dn1test/dn1sup_export_3d.git`.
2. Закоммитьте изменения и запушьте ветку `main` (перед этим убедитесь,
   что собранные ассеты `dn1sup_export_3d/viewer/assets/` и `ui/assets/`
   закоммичены — их наличие требует `build/package.rb`).
3. Первая публикация: тег `v0.8.3` → workflow соберёт
   `build/dn1sup_export_3d.rbz` и приложит к релизу.
4. По желанию: `shared/dn1sup_updater.rb` для «Проверить обновления».
