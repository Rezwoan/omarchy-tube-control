# Changelog

## 1.2.0

### Changed

- **Launches your default browser, not a bundled Chromium.** Search and
  playback windows now open in whatever browser `xdg-settings` reports as
  the desktop's default — reusing its existing YouTube / YouTube Music
  sign-in instead of a separate, empty Chromium profile that needed its own
  login. Detection lives in `bin/detect-default-browser.sh`.
- If the default browser is Chromium-based (Chrome, Chromium, Brave,
  Vivaldi, Edge, Opera, ...), it still opens as a real `--app=` window, so
  independent MPRIS control, per-window PipeWire volume/mute, focus, and
  close all keep working exactly as before — just against the browser you
  actually use.
- If the default browser doesn't support app-mode windows (e.g. Firefox),
  the widget falls back to a normal `xdg-open` window. Playback and
  transport controls keep working via MPRIS; window isolation for the
  focus/close/volume controls is best-effort (matched by window title
  instead of a dedicated window class).
- Dropped the two isolated `~/.local/share/youtube-control-center/*`
  Chromium profiles entirely — nothing to sign into twice, nothing to clean
  up on removal.

### Requirements

- Chromium is no longer required. Any browser can be the default; Chromium-
  family browsers get the full experience described above.
