#!/usr/bin/env bash
# WPF calls Environment.FailFast from TypefaceMap.MapUnresolvedCharacters
# when a character has no font. Wine's FontLink chain names Segoe UI and
# other faces that are not installed. Point those names at fonts this
# distro actually ships.
. "$(dirname "$0")/lib.sh"

need_cmd wine
need_cmd fc-list
refuse_if_ets_running

droid=$(fc-list "Droid Sans Fallback" file | awk -F: 'NR==1 {print $1}')
[ -n "$droid" ] || die "Droid Sans Fallback is not installed (fonts-droid-fallback)"
fc-list "Liberation Sans" file | grep -q . || die "Liberation Sans is not installed"
fc-list "Carlito" file | grep -q . || die "Carlito is not installed (fonts-crosextra-carlito)"

add_repl() {
  wine reg add 'HKCU\Software\Wine\Fonts\Replacements' /v "$1" /d "$2" /f >/dev/null
}
add_repl "Segoe UI" "Carlito"
add_repl "Segoe UI Symbol" "Droid Sans Fallback"
add_repl "Segoe UI Emoji" "Droid Sans Fallback"
add_repl "Segoe UI Historic" "Droid Sans Fallback"
add_repl "Arial" "Liberation Sans"
add_repl "Microsoft Sans Serif" "Liberation Sans"
add_repl "Tahoma" "Liberation Sans"

link='HKLM\Software\Microsoft\Windows NT\CurrentVersion\FontLink\SystemLink'
fallback='DroidSansFallbackFull.ttf,Droid Sans Fallback'
for face in "Microsoft Sans Serif" "Segoe UI" "Arial" "Tahoma"; do
  wine reg add "$link" /v "$face" /t REG_MULTI_SZ /d "$fallback" /f >/dev/null
done

rm -rf "$WINEPREFIX/drive_c/users/$USER/AppData/Local/Microsoft/FontCache" \
       "$WINEPREFIX/drive_c/users/$USER/AppData/Local/FontCache" || true

# Plain Win32 layered windows (classic tooltips, TrackPopupMenu) come out
# solid black under a compositor unless Wine is told to skip XShape and
# use a real ARGB window instead.
wine reg add 'HKCU\Software\Wine\X11 Driver' /v ShapeLayeredWindows /d N /f >/dev/null

# ETS5's own menus and tooltips are WPF Popup controls, which render through
# a different path (Avalon/Direct3D) than the Win32 layered windows above.
# Wine's Direct3D-backed WPF compositing comes out solid black here too, so
# WPF has to fall back to its CPU software rasterizer instead. See Wine bug
# 49055.
wine reg add 'HKCU\Software\Microsoft\Avalon.Graphics' /v DisableHWAcceleration /t REG_DWORD /d 1 /f >/dev/null

printf 'font fallback registered\n'
