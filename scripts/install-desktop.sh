#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

apps=$HOME/.local/share/applications
icons=$HOME/.local/share/icons/hicolor/scalable/apps
mkdir -p "$apps" "$icons" "$HOME/.local/bin"
cat > "$HOME/.local/bin/ets5" <<EOF
#!/bin/sh
exec '$ROOT/bin/ets5' "\$@"
EOF
chmod 0755 "$HOME/.local/bin/ets5"
install -m 0644 "$ROOT/desktop/ets5.svg" "$icons/ets5.svg"
sed "s|@BIN@|$HOME/.local/bin/ets5|g" "$ROOT/desktop/ets5.desktop.in" > "$apps/ets5.desktop"
chmod 0644 "$apps/ets5.desktop"
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$apps" >/dev/null 2>&1 || true
fi
printf 'menu entry installed: %s\n' "$apps/ets5.desktop"
