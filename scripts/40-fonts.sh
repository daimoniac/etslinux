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
printf 'font fallback registered\n'
