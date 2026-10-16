# Shared helpers. Source this; do not execute it.
if [ -z "${ETS5_LIB_LOADED:-}" ]; then
  ETS5_LIB_LOADED=1
  set -euo pipefail
fi

LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$LIB_DIR/.." && pwd)

export WINEPREFIX="${WINEPREFIX:-$HOME/.local/share/wineprefixes/ets5}"
export WINEARCH="${WINEARCH:-win64}"
export ETS5_CACHE="${ETS5_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/ets5-linux}"

# Microsoft redistributables. ETS itself is not downloaded.
DOTNET48_URL="https://download.microsoft.com/download/f/3/a/f3a6af84-da23-40a5-8d1c-49cc10c8e76f/NDP48-x86-x64-AllOS-ENU.exe"
DOTNET48_SHA256="0a3a390c47e639d0f7fc65b21195fee6b7f65b066f80f70c60fab191d14b7e40"
DOTNET40_URL="https://download.microsoft.com/download/9/5/A/95A9616B-7A37-4AF6-BC36-D6EA96C8DAAE/dotNetFx40_Full_x86_x64.exe"
DOTNET40_SHA256="65e064258f2e418816b304f646ff9e87af101e4c9552ab064bb74d281c38659f"

# .NET 4.8 offline installer writes this Release value when it actually installs.
DOTNET48_RELEASE=528049
# Wine 11.10 is the first release with the CM_Get_Parent fix ETS needs (bug 59604).
WINE_MIN_VERSION=11.10

WINEHQ_FPR="D43F640145369C51D786DDEA76F1A20FF987672F"
DONGLE_VIDPID="2a07:0102"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

refuse_if_ets_running() {
  if pgrep -f 'ETS[56]N?\.exe' >/dev/null 2>&1; then
    die "ETS is running. Close it before changing the Wine prefix."
  fi
}

# Parsed, not sourced. Compose accepts an unquoted value containing spaces,
# and MQTT_OPTIONS is one; the shell would read that as a command name.
# One layer of matching quotes is removed, which is what Compose does too.
load_env() {
  local file=$ROOT/.env line key value
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    [[ $line =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=(.*)$ ]] || continue
    key=${BASH_REMATCH[2]}
    value=${BASH_REMATCH[3]}
    value=${value%$'\r'}
    if [[ $value =~ ^\"(.*)\"$ ]] || [[ $value =~ ^\'(.*)\'$ ]]; then
      value=${BASH_REMATCH[1]}
    fi
    export "$key=$value"
  done < "$file"
}

# WineHQ keeps the real binaries in /opt/wine-*/bin. /usr/bin/wine is only
# a symlink, and apt deletes it when it removes a distro wine package in
# the same transaction that installs WineHQ.
wine_bindir() {
  local dir
  if command -v wine >/dev/null 2>&1; then
    dirname "$(command -v wine)"
    return 0
  fi
  for dir in /opt/wine-stable/bin /opt/wine-devel/bin; do
    if [ -x "$dir/wine" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
  done
  return 1
}

prepend_wine_path() {
  local dir
  dir=$(wine_bindir) || return 1
  case ":$PATH:" in
    *":$dir:"*) ;;
    *) export PATH="$dir:$PATH" ;;
  esac
}

wine_version_number() {
  local raw
  raw=$(wine --version 2>/dev/null | awk '{print $1}')
  raw=${raw#wine-}
  printf '%s\n' "$raw"
}

wine_is_new_enough() {
  local ver
  ver=$(wine_version_number)
  dpkg --compare-versions "$ver" ge "$WINE_MIN_VERSION"
}

# winecfg -v writes the version, then wineserver often stays up because
# winedevice never exits. Kill the server only when ETS is not running.
set_windows_version() {
  local ver=$1
  refuse_if_ets_running
  timeout 45 winecfg -v "$ver" >/dev/null 2>&1 || true
  wineserver -k >/dev/null 2>&1 || true
  sleep 1
}

# wine reg query writes CRLF. A leftover CR makes $((0x80eb1)) fail and
# leaves a Windows 7 product name that the 4.8 installer check rejects.
strip_cr() { tr -d '\r'; }

windows_product_name() {
  wine reg query 'HKLM\Software\Microsoft\Windows NT\CurrentVersion' /v ProductName 2>/dev/null \
    | strip_cr \
    | awk -F'REG_SZ' '/ProductName/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}'
}

dotnet_release() {
  local node=$1 raw
  raw=$(wine reg query "$node" /v Release 2>/dev/null | strip_cr | awk '/Release/ {print $NF}' || true)
  if [ -z "$raw" ]; then
    printf '0\n'
    return
  fi
  printf '%s\n' "$((raw))"
}

download() {
  local url=$1 dest=$2 sha=$3
  mkdir -p "$(dirname "$dest")"
  if [ -f "$dest" ]; then
    local got
    got=$(sha256sum "$dest" | awk '{print $1}')
    if [ "$got" = "$sha" ]; then
      return 0
    fi
    rm -f "$dest"
  fi
  curl -fL --retry 3 --retry-delay 2 -o "$dest.partial" "$url"
  local got
  got=$(sha256sum "$dest.partial" | awk '{print $1}')
  if [ "$got" != "$sha" ]; then
    rm -f "$dest.partial"
    die "checksum mismatch for $url"
  fi
  mv "$dest.partial" "$dest"
}

os_codename() {
  . /etc/os-release
  printf '%s\n' "${VERSION_CODENAME:?}"
}
