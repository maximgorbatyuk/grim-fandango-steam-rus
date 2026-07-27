#!/usr/bin/env bash
#
# Установка русификации Grim Fandango Remastered (Steam, macOS).
#
# Что делает:
#   1. проверяет, что игра установлена и бандл на месте;
#   2. копирует файлы русификации из репозитория внутрь .app;
#   3. приводит имена VOX-архивов к регистру, который ждёт игра;
#   4. снимает карантин и переподписывает бандл ad-hoc подписью;
#   5. проверяет, что подпись сходится.
#
# Зачем шаги 4-5: файлы лежат внутри подписанного .app. Любая подмена
# ломает печать подписи, Gatekeeper убивает процесс при запуске.
# Переподписывание пересобирает печать по текущему содержимому.
#
# Прогонять заново после каждого обновления игры в Steam и после
# «Проверить целостность файлов» — Steam возвращает оригиналы.
#
# Использование:
#   ./install.sh [путь-к-GrimFandango.app]
#   ./install.sh --dry-run
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DEFAULT_APP="$HOME/Library/Application Support/Steam/steamapps/common/Grim Fandango Remastered/GrimFandango.app"

DRY_RUN=0
APP=""

# ---------------------------------------------------------------- вывод

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; OFF=$'\033[0m'
[ -t 1 ] || { RED=""; GREEN=""; YELLOW=""; DIM=""; OFF=""; }

step() { printf '\n%s==>%s %s\n' "$GREEN" "$OFF" "$1"; }
info() { printf '    %s\n' "$1"; }
dim()  { printf '    %s%s%s\n' "$DIM" "$1" "$OFF"; }
warn() { printf '    %s! %s%s\n' "$YELLOW" "$1" "$OFF"; }
die()  { printf '\n%sОшибка:%s %s\n' "$RED" "$OFF" "$1" >&2; exit 1; }

usage() {
	cat <<-EOF
		Установка русификации Grim Fandango Remastered (Steam, macOS).

		  ./install.sh [путь-к-GrimFandango.app]
		  ./install.sh --dry-run     показать план, ничего не менять
		  ./install.sh --help

		Без аргументов игра ищется по стандартному пути библиотеки Steam:
		  $DEFAULT_APP
	EOF
}

# ------------------------------------------------------------ аргументы

while [ $# -gt 0 ]; do
	case "$1" in
		-h|--help)    usage; exit 0 ;;
		-n|--dry-run) DRY_RUN=1; shift ;;
		-*)           die "неизвестный ключ: $1" ;;
		*)            APP="$1"; shift ;;
	esac
done

APP="${APP:-${GRIM_APP:-$DEFAULT_APP}}"
APP="${APP%/}"
RES="$APP/Contents/Resources"

# ------------------------------------------------- проверка окружения

step "Проверяю окружение"

[ "$(uname -s)" = "Darwin" ] || die "скрипт рассчитан на macOS."

if [ "$(id -u)" -eq 0 ]; then
	die "не запускайте через sudo — с ним скрипт как раз и сломается.

Папка Steam лежит в ~/Library/Application Support, а это защищённая TCC зона.
Разрешение на неё выдано вашему терминалу, а не root: под sudo процесс теряет
это разрешение и получает отказ даже с полными правами.

Бандл игры принадлежит вам, root не нужен. Запустите ту же команду без sudo."
fi

for tool in codesign xattr; do
	command -v "$tool" >/dev/null 2>&1 \
		|| die "не найден $tool. Установите Command Line Tools: xcode-select --install"
done

dim "macOS $(sw_vers -productVersion), $(uname -m)"

# ------------------------------------------------- проверка установки

step "Проверяю, что игра установлена"

if [ ! -d "$APP" ]; then
	die "игра не найдена по пути:
  $APP

Установите Grim Fandango Remastered в Steam, либо укажите путь вручную:
  ./install.sh \"/путь/к/GrimFandango.app\""
fi

[ -x "$APP/Contents/MacOS/GrimFandango" ] \
	|| die "по пути $APP нет исполняемого файла Contents/MacOS/GrimFandango.
Похоже, это не бандл игры или установка повреждена."

[ -d "$RES" ] \
	|| die "в бандле нет каталога Contents/Resources — установка повреждена.
Переустановите игру: удалите папку игры и поставьте заново из Steam."

[ -d "$RES/MoviesHD" ] \
	|| die "в бандле нет каталога Contents/Resources/MoviesHD — установка неполная.
В Steam: свойства игры -> Установленные файлы -> Проверить целостность."

# Пробный прогон ничего не пишет и не трогает процесс игры,
# поэтому ниже это лишь предупреждения, а не отказ.
if [ ! -w "$APP" ]; then
	if [ "$DRY_RUN" -eq 1 ]; then
		warn "нет прав на запись в бандл — установка в этом виде не пройдёт"
	else
		die "нет прав на запись в бандл игры:
  $APP

Проверьте владельца: ls -ld \"\$(dirname \"$APP\")\"
Если владелец не вы — верните права:
  sudo chown -R \"\$(id -un)\" \"$APP\"
и запустите скрипт снова уже без sudo."
	fi
fi

if pgrep -x GrimFandango >/dev/null 2>&1; then
	if [ "$DRY_RUN" -eq 1 ]; then
		warn "игра сейчас запущена — перед установкой её нужно закрыть"
	else
		die "игра запущена. Закройте её и повторите."
	fi
fi

info "игра на месте: $APP"

# --------------------------------------------- проверка файлов перевода

step "Проверяю файлы русификации"

# каталог в репозитории : каталог назначения внутри бандла : обязателен ли
ASSETS=(
	"rus-movies:$RES/MoviesHD:да"
	"sound:$RES:да"
	"fonts:$RES/FontsHD:нет"
)

PLAN=()
TOTAL=0

for entry in "${ASSETS[@]}"; do
	IFS=":" read -r subdir dest required <<< "$entry"
	src="$REPO/$subdir"

	if [ ! -d "$src" ]; then
		if [ "$required" = "да" ]; then
			die "в репозитории нет каталога '$subdir' — без него русификация неполная."
		fi
		dim "$subdir/ — нет в репозитории, пропускаю"
		continue
	fi

	count=$(find "$src" -type f ! -name '.*' | wc -l | tr -d ' ')
	if [ "$count" -eq 0 ]; then
		if [ "$required" = "да" ]; then
			die "каталог '$subdir' пуст."
		fi
		dim "$subdir/ — пуст, пропускаю"
		continue
	fi

	PLAN+=("$src:$dest")
	TOTAL=$((TOTAL + count))
	info "$subdir/ — $count файл(ов) -> ${dest#"$APP"/}"
done

[ "$TOTAL" -gt 0 ] || die "нечего устанавливать."

if [ ! -d "$REPO/fonts" ]; then
	warn "каталога fonts/ нет. Если кириллица в игре не отображается,
      добавьте в него шрифты *-ENPY.ttf из архива русификатора."
fi

if [ "$DRY_RUN" -eq 1 ]; then
	step "Пробный прогон — ничего не изменено"
	info "к установке: $TOTAL файл(ов)"
	exit 0
fi

# ----------------------------------------------- нормализация регистра

step "Привожу имена VOX-архивов к верхнему регистру"

shopt -s nullglob
renamed=0
for f in "$RES"/VOX*.lab; do
	target="${f%.lab}.LAB"
	mv "$f" "$target"
	dim "$(basename "$f") -> $(basename "$target")"
	renamed=$((renamed + 1))
done
shopt -u nullglob
[ "$renamed" -gt 0 ] || dim "переименовывать нечего"

# ------------------------------------------------------ копирование

step "Копирую файлы русификации ($TOTAL шт., это займёт минуту)"

copied=0
unknown=0

for item in "${PLAN[@]}"; do
	src="${item%%:*}"
	dest="${item#*:}"

	mkdir -p "$dest"

	while IFS= read -r f; do
		name="$(basename "$f")"
		[ -e "$dest/$name" ] || { warn "$name — в игре нет такого файла, добавляю как новый"; unknown=$((unknown + 1)); }
		cp -f "$f" "$dest/$name"
		copied=$((copied + 1))
		if [ -t 1 ]; then printf '\r    %d/%d' "$copied" "$TOTAL"; fi
	done < <(find "$src" -type f ! -name '.*' | sort)
done

if [ -t 1 ]; then printf '\r'; fi
printf '    %d/%d — готово\n' "$copied" "$TOTAL"
[ "$unknown" -eq 0 ] || warn "$unknown файл(ов) не совпали с именами в игре — проверьте, те ли это файлы"

# ---------------------------------------------------------- подпись

step "Снимаю карантин"
xattr -cr "$APP"
info "расширенные атрибуты очищены"

step "Переподписываю бандл"
codesign --force --deep --sign - "$APP" 2>&1 | sed 's/^/    /'

step "Проверяю подпись"
if codesign --verify --deep --verbose=2 "$APP" 2>&1 | sed 's/^/    /'; then
	printf '\n%sГотово.%s Русификация установлена, подпись сходится — можно запускать из Steam.\n\n' "$GREEN" "$OFF"
else
	die "подпись не сходится. Вывод codesign выше.

Скорее всего в бандле есть ещё чьи-то изменённые файлы. Чистый старт:
  1. удалите папку игры целиком
  2. установите заново из Steam
  3. прогоните этот скрипт"
fi
