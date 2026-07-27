#!/usr/bin/env bash
#
# Установка русификации Grim Fandango Remastered (Steam, macOS) из сети.
#
# Скачивает ассеты во временную папку, ставит их в игру через local-install.sh
# и предлагает убрать за собой.
#
# Если репозиторий уже склонирован — этот скрипт не нужен, запускайте
# local-install.sh напрямую.
#
# Использование:
#   ./install.sh                       установить
#   ./install.sh --dry-run             показать план, ничего не менять
#   ./install.sh --keep-temp           не удалять скачанное
#   ./install.sh -y                    не спрашивать про удаление
#   ./install.sh "/путь/к/GrimFandango.app"
#
# Одной строкой:
#   curl -fsSL https://raw.githubusercontent.com/maximgorbatyuk/grim-fandango-steam-rus/main/install.sh | bash
#
set -euo pipefail

REPO_URL="${GRIM_RUS_REPO:-https://github.com/maximgorbatyuk/grim-fandango-steam-rus.git}"
REF="${GRIM_RUS_REF:-main}"

DOWNLOAD_SIZE="~640 МБ"

KEEP_TEMP=0
ASSUME_YES=0
PASS=()
TMP=""
INSTALL_OK=0

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
		Установка русификации Grim Fandango Remastered (Steam, macOS) из сети.

		  ./install.sh [ключи] [путь-к-GrimFandango.app]

		    --dry-run      показать план, ничего не устанавливать
		    --keep-temp    не удалять временную папку со скачанным
		    -y, --yes      не спрашивать про удаление временных файлов
		    --ref ИМЯ      ветка или тег репозитория (по умолчанию: $REF)
		    --repo URL     другой репозиторий
		    -h, --help

		Скачивается $DOWNLOAD_SIZE во временную папку. Она удаляется после
		установки — с вашего согласия.
	EOF
}

# ------------------------------------------------------------ аргументы

while [ $# -gt 0 ]; do
	case "$1" in
		-h|--help)   usage; exit 0 ;;
		--keep-temp) KEEP_TEMP=1; shift ;;
		-y|--yes)    ASSUME_YES=1; shift ;;
		--ref)       [ $# -ge 2 ] || die "--ref без значения"; REF="$2"; shift 2 ;;
		--repo)      [ $# -ge 2 ] || die "--repo без значения"; REPO_URL="$2"; shift 2 ;;
		*)           PASS+=("$1"); shift ;;
	esac
done

# ------------------------------------------------------------- уборка

cleanup() {
	[ -n "$TMP" ] && [ -d "$TMP" ] || return 0

	if [ "$KEEP_TEMP" -eq 1 ]; then
		step "Временные файлы"
		info "оставлены по вашей просьбе: $TMP"
		return 0
	fi

	if [ "$INSTALL_OK" -ne 1 ]; then
		step "Временные файлы"
		info "оставлены для разбора: $TMP"
		dim "удалить вручную: rm -rf \"$TMP\""
		return 0
	fi

	local size
	size="$(du -sh "$TMP" 2>/dev/null | cut -f1 || echo '?')"

	step "Временные файлы"

	if [ "$ASSUME_YES" -eq 1 ] || [ ! -t 0 ]; then
		rm -rf "$TMP"
		info "удалено $size из $TMP"
		return 0
	fi

	local answer=""
	printf '    Удалить временную папку (%s, %s)? [Y/n] ' "$size" "$TMP"
	read -r answer || true
	case "$answer" in
		[nNнН]*) info "оставляю: $TMP"; dim "удалить вручную: rm -rf \"$TMP\"" ;;
		*)       rm -rf "$TMP"; info "удалено $size" ;;
	esac
}

on_signal() {
	printf '\n'
	warn "прервано"
	[ -n "$TMP" ] && [ -d "$TMP" ] && { rm -rf "$TMP"; info "временные файлы убраны"; }
	exit 130
}

trap cleanup EXIT
trap on_signal INT TERM

# ------------------------------------------------- проверка окружения

step "Проверяю окружение"

[ "$(uname -s)" = "Darwin" ] || die "скрипт рассчитан на macOS."

if [ "$(id -u)" -eq 0 ]; then
	die "не запускайте через sudo — с ним установка как раз и сломается.

Папка Steam лежит в ~/Library/Application Support, а это защищённая TCC зона.
Разрешение на неё выдано вашему терминалу, а не root: под sudo процесс теряет
это разрешение и получает отказ даже с полными правами.

Запустите ту же команду без sudo."
fi

command -v git >/dev/null 2>&1 \
	|| die "не найден git. Установите Command Line Tools: xcode-select --install"

git lfs version >/dev/null 2>&1 \
	|| die "не найден git-lfs, без него скачаются заглушки вместо роликов.

  brew install git-lfs && git lfs install"

for tool in codesign xattr; do
	command -v "$tool" >/dev/null 2>&1 \
		|| die "не найден $tool. Установите Command Line Tools: xcode-select --install"
done

dim "macOS $(sw_vers -productVersion), $(uname -m), $(git lfs version | head -1)"

# ---------------------------------------------------------- скачивание

step "Скачиваю русификацию ($DOWNLOAD_SIZE)"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/grim-rus.XXXXXX")"
dim "временная папка: $TMP"
info "источник: $REPO_URL ($REF)"

if ! git clone --depth 1 --single-branch --branch "$REF" \
		"$REPO_URL" "$TMP/repo" 2>&1 | sed 's/^/    /'; then
	die "не удалось склонировать репозиторий.

Проверьте соединение и что ветка '$REF' существует:
  git ls-remote $REPO_URL"
fi

# ------------------------------------------------------ проверка скачанного

step "Проверяю скачанное"

RUNNER="$TMP/repo/local-install.sh"

[ -f "$RUNNER" ] \
	|| die "в репозитории нет local-install.sh — похоже, ветка '$REF' не та."

chmod +x "$RUNNER"

# git-lfs мог не подтянуть объекты: тогда вместо роликов лежат
# текстовые указатели в пару сотен байт.
sample="$(find "$TMP/repo/rus-movies" -name '*.ogv' -type f 2>/dev/null | head -1)"
if [ -n "$sample" ]; then
	bytes="$(wc -c < "$sample" | tr -d ' ')"
	if [ "$bytes" -lt 100000 ]; then
		die "скачались LFS-указатели, а не сами файлы ($(basename "$sample") — $bytes байт).

Включите git-lfs и повторите:
  git lfs install"
	fi
	dim "ассеты на месте (проверочный файл: $(basename "$sample"), $bytes байт)"
else
	die "в скачанном репозитории нет роликов в rus-movies/."
fi

# ------------------------------------------------------------ установка

step "Запускаю установку"

set +e
"$RUNNER" ${PASS[@]+"${PASS[@]}"}
rc=$?
set -e

if [ "$rc" -ne 0 ]; then
	printf '\n%sУстановка не завершилась%s (код %d). Вывод выше.\n' "$RED" "$OFF" "$rc" >&2
	exit "$rc"
fi

INSTALL_OK=1
