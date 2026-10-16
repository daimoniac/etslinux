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

# The window ETS opens is ets5n.exe. Wine's own menu entry says ets5.exe,
# so the panel cannot attach that entry's icon and draws a blank page.
# The icon name Wine invents (B850_Ets5Icons.0) also changes per prefix, and
# an SVG alone is not picked up at panel size. Copy the extracted PNGs to a
# stable name and point every entry at the real window class.
icon=ets5
wine_desktop=
if [ -d "$apps/wine" ]; then
  wine_desktop=$(find "$apps/wine" -type f -name 'ETS5.desktop' | awk 'NR==1 { print }')
fi
if [ -n "$wine_desktop" ]; then
  wine_icon=$(awk -F= '$1 == "Icon" { print $2; exit }' "$wine_desktop")
  icon_dirs=()
  [ -d "$HOME/.local/share/icons" ] && icon_dirs+=("$HOME/.local/share/icons")
  [ -d "$HOME/.icons" ] && icon_dirs+=("$HOME/.icons")
  if [ -n "$wine_icon" ] && [ "${#icon_dirs[@]}" -gt 0 ]; then
    while IFS= read -r src; do
      cp -f "$src" "$(dirname "$src")/ets5.png"
    done < <(find "${icon_dirs[@]}" -type f -name "$wine_icon.png")
  fi
  if grep -q '^StartupWMClass=' "$wine_desktop"; then
    sed -i 's/^StartupWMClass=.*/StartupWMClass=ets5n.exe/' "$wine_desktop"
  else
    printf '\nStartupWMClass=ets5n.exe\n' >> "$wine_desktop"
  fi
fi

sed -e "s|@BIN@|$HOME/.local/bin/ets5|g" -e "s|^Icon=.*|Icon=$icon|" \
  "$ROOT/desktop/ets5.desktop.in" > "$apps/ets5.desktop"
chmod 0644 "$apps/ets5.desktop"
# Wayland uses the window class as the app id and looks for a desktop file
# of that name. NoDisplay keeps it out of the menu, which already has ETS5.
sed -e "s|@BIN@|$HOME/.local/bin/ets5|g" -e "s|^Icon=.*|Icon=$icon|" \
  -e 's|^Name=.*|Name=ETS5|' \
  "$ROOT/desktop/ets5.desktop.in" > "$apps/ets5n.exe.desktop"
printf 'NoDisplay=true\n' >> "$apps/ets5n.exe.desktop"
chmod 0644 "$apps/ets5n.exe.desktop"
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$apps" >/dev/null 2>&1 || true
fi
printf 'menu entry installed: %s\n' "$apps/ets5.desktop"
