#!/usr/bin/env bash
# Host packages, WineHQ repository, kernel module, and udev rule.
# Usage: 00-host.sh client|server
. "$(dirname "$0")/lib.sh"

role=${1:-client}
case "$role" in
  client|server) ;;
  *) die "usage: $0 client|server" ;;
esac

if [ ! -r /etc/os-release ]; then
  die "expected a Debian/Ubuntu host"
fi
codename=$(os_codename)

as_root apt-get update
as_root apt-get install -y ca-certificates curl gnupg usbutils

if [ "$role" = client ]; then
  as_root install -d -m 0755 /etc/apt/keyrings
  tmp=$(mktemp)
  curl -fsSL https://dl.winehq.org/wine-builds/winehq.key -o "$tmp"
  fpr=$(gpg --show-keys --with-colons "$tmp" | awk -F: '/^fpr:/ {print $10; exit}')
  if [ "$fpr" != "$WINEHQ_FPR" ]; then
    rm -f "$tmp"
    die "WineHQ key fingerprint $fpr does not match $WINEHQ_FPR"
  fi
  gpg --dearmor < "$tmp" | as_root tee /etc/apt/keyrings/winehq-archive.gpg >/dev/null
  rm -f "$tmp"
  as_root chmod 0644 /etc/apt/keyrings/winehq-archive.gpg
  if ! dpkg --print-foreign-architectures | grep -qx i386; then
    as_root dpkg --add-architecture i386
  fi

  sources=/etc/apt/sources.list.d/winehq-${codename}.sources
  as_root tee "$sources" >/dev/null <<EOF
Types: deb
URIs: https://dl.winehq.org/wine-builds/ubuntu
Suites: ${codename}
Components: main
Architectures: amd64 i386
Signed-By: /etc/apt/keyrings/winehq-archive.gpg
EOF
  as_root apt-get update

  stable=$(apt-cache policy winehq-stable | awk '/Candidate:/ {print $2}')
  stable=${stable%%~*}
  stable=${stable%%-*}
  pkg=winehq-devel
  if [ -n "$stable" ] && [ "$stable" != "(none)" ] && dpkg --compare-versions "$stable" ge "$WINE_MIN_VERSION"; then
    pkg=winehq-stable
  fi
  printf 'installing %s (need Wine >= %s; winehq-stable candidate is %s)\n' "$pkg" "$WINE_MIN_VERSION" "${stable:-none}"
  as_root apt-get install -y "$pkg" p7zip-full msitools cabextract \
    fonts-droid-fallback fonts-liberation fonts-crosextra-carlito

  if ! wine_is_new_enough; then
    die "installed Wine $(wine_version_number) is older than $WINE_MIN_VERSION"
  fi
  printf 'Wine %s\n' "$(wine_version_number)"

  as_root install -m 0644 "$ROOT/modules/vhci-hcd.conf" /etc/modules-load.d/vhci-hcd.conf
  as_root modprobe vhci-hcd
  as_root install -m 0644 "$ROOT/udev/70-knx-ets-dongle.rules" /etc/udev/rules.d/70-knx-ets-dongle.rules
  as_root udevadm control --reload
  as_root udevadm trigger --subsystem-match=usb --subsystem-match=hidraw || true

  if ! id -nG "$USER" | tr ' ' '\n' | grep -qx plugdev; then
    as_root usermod -aG plugdev "$USER"
    printf 'added %s to plugdev; log out and back in before launching ETS\n' "$USER"
  fi
else
  as_root install -m 0644 "$ROOT/modules/usbip-host.conf" /etc/modules-load.d/usbip-host.conf
  # The module must exist before the server container's first start. Docker
  # otherwise creates a directory where the sysfs bind source should be.
  as_root modprobe usbip-host
  if ! command -v docker >/dev/null 2>&1; then
    die "docker is not installed; this script does not install Docker"
  fi
fi
