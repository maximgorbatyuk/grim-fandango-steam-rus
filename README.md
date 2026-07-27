# grim-fandango-steam-rus

Русификация Grim Fandango Remastered (Steam) для macOS на Apple Silicon.

## Установка

```bash
./install.sh
```

Скрипт сам найдёт игру в стандартной библиотеке Steam, скопирует файлы,
переподпишет бандл и проверит результат. Если игра стоит в другом месте:

```bash
./install.sh "/путь/к/GrimFandango.app"
```

Посмотреть план, ничего не меняя:

```bash
./install.sh --dry-run
```

## Что внутри

| Каталог      | Куда ставится                 | Что это                           |
|--------------|-------------------------------|-----------------------------------|
| `rus-movies` | `Contents/Resources/MoviesHD` | заставки с русскими надписями     |
| `sound`      | `Contents/Resources`          | VOX-архивы с переведённым текстом |
| `fonts`      | `Contents/Resources/FontsHD`  | шрифты с кириллицей (опционально) |

Перевод — [ENPY Studio](https://www.playground.ru/grim_fandango/file/rusifikator_grim_fandango_remastered_ot_enpy-937706).
Официальной Mac-сборки у русификатора нет, файлы извлечены из Windows-инсталлятора.

## Почему нужен скрипт, а не простое копирование

Все файлы игры лежат внутри подписанного `.app`. В `Contents/CodeResources`
хранится печать — хеш каждого файла бандла. Подменяете ролик или VOX-архив,
и печать перестаёт сходиться:

```
spctl: a sealed resource is missing or invalid
```

На Apple Silicon это не предупреждение, а приговор: ядро убивает процесс при
запуске (`killed`), Steam показывает «файлы могут быть повреждены».

Скрипт после копирования пересобирает печать по текущему содержимому:

```bash
xattr -cr "$APP"                        # снять карантин
codesign --force --deep --sign - "$APP" # переподписать ad-hoc
```

Подпись становится ad-hoc вместо нотаризованной Double Fine. Для запуска из
Steam это неважно.

## Регистр VOX-архивов

Windows-инсталлятор русификатора пишет `VOX0000.lab` строчными, а игра и
подпись ждут `VOX0000.LAB`. На регистронезависимой APFS игра файл найдёт,
а `codesign` — нет: он сверяет имена побайтово и объявит файл пропавшим.
Скрипт приводит регистр к верхнему перед копированием.

## После обновлений Steam

Steam возвращает оригинальные файлы при обновлении игры и при «Проверить
целостность файлов». Печать снова ломается. Лечится повторным запуском:

```bash
./install.sh
```

Чтобы это случалось реже: свойства игры в Steam → Обновления →
«Обновлять только при запуске».

## Откат

Штатными средствами Steam: свойства игры → Установленные файлы →
Проверить целостность. Steam вернёт оригиналы. После этого снимите карантин
и переподпишите заново, иначе игра снова не запустится:

```bash
APP="$HOME/Library/Application Support/Steam/steamapps/common/Grim Fandango Remastered/GrimFandango.app"
xattr -cr "$APP" && codesign --force --deep --sign - "$APP"
```

## Требования

- macOS, Command Line Tools (`xcode-select --install`) — нужны `codesign` и `xattr`
- установленная в Steam Grim Fandango Remastered
