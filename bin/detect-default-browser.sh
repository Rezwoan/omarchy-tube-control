#!/bin/bash
# Resolves the user's configured default web browser and reports whether it
# is Chromium-based (so it understands --app= "site app" windows and the
# chrome-<host>__<profile> WM_CLASS convention BarWidget.qml matches on).
# Emits {"exec":"<launch command>","family":"chromium|firefox|other"}.
#
# Deliberately does not fall back to launching an isolated browser profile:
# the whole point is to reuse whatever browser (and sign-in) the user
# already made default, not to open a second, separately-signed-in browser.
set -euo pipefail

desktop_id="$(xdg-settings get default-web-browser 2>/dev/null || true)"
desktop_id="${desktop_id//$'\r'/}"

data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
search_dirs=(
  "$data_home/applications"
  /usr/share/applications
  /usr/local/share/applications
  "$data_home/flatpak/exports/share/applications"
  /var/lib/flatpak/exports/share/applications
)

exec_line=""
if [ -n "$desktop_id" ]; then
  for dir in "${search_dirs[@]}"; do
    file="$dir/$desktop_id"
    if [ -f "$file" ]; then
      # Strip desktop-entry field codes (%U, %u, %f, ...) - we build our own args.
      exec_line="$(grep -m1 '^Exec=' "$file" | cut -d= -f2- | sed -E 's/ ?%[a-zA-Z]//g')"
      break
    fi
  done
fi

# xdg-settings can be unset on a fresh system; probe common binaries as a
# last resort so the widget still has a browser to launch.
if [ -z "$exec_line" ]; then
  for bin in google-chrome-stable google-chrome chromium chromium-browser \
             brave-browser brave vivaldi-stable vivaldi \
             microsoft-edge-stable microsoft-edge opera thorium-browser firefox; do
    if command -v "$bin" >/dev/null 2>&1; then
      exec_line="$bin"
      break
    fi
  done
fi

haystack="${exec_line,,} ${desktop_id,,}"
family="other"
case "$haystack" in
  *firefox*|*librewolf*|*waterfox*|*floorp*|*seamonkey*|*icecat*|*zen-browser*)
    family="firefox" ;;
  *chromium*|*chrome*|*brave*|*vivaldi*|*edge*|*opera*|*thorium*)
    family="chromium" ;;
esac

jq -n --arg exec "$exec_line" --arg family "$family" '{exec: $exec, family: $family}'
