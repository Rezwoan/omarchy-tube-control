# Tube Control

YouTube and YouTube Music finally behave like two real desktop players—not two tabs fighting over the same controls.

A fork of [janooh37-hue/omarchy-youtube-control-center](https://github.com/janooh37-hue/omarchy-youtube-control-center).

![Tube Control — hand playback between YouTube and YouTube Music](preview.png)

![Tube Control widget showing independent YouTube and YouTube Music players](preview-widget.png)

## What makes it different

- **Keep both worlds separate.** YouTube and YouTube Music each get their own isolated Chromium app profile and independent player row. A paused video never disappears just because music started, and closing one never affects the other.
- **Headless by default.** Search opens the player in the background — it plays immediately, but the window stays hidden until you ask to see it. No popup stealing focus while you're doing something else.
- **Floating window on demand.** Tap the video icon on any player row to show it as a small floating window, and tap again to tuck it back away. Playback never stops either way.
- **Hand off instead of hunting tabs.** One button starts the player you want and pauses every other player, so switching from a video to music never creates overlapping audio.
- **Change the player, not the whole desktop.** Volume and mute controls target the exact YouTube or Music stream while system volume stays untouched.
- **Search where you mean to listen.** Type once, then send the query directly to YouTube or YouTube Music. Each service remembers its own sign-in after the first launch.
- **See every session at once.** Multiple active players remain visible and controllable from one compact Omarchy bar popup.

## Use it

Open the YouTube icon in the Omarchy bar. Search for a song, artist, or video, then choose YouTube or YouTube Music — it opens in the background right away. Tap the video icon on that player's row whenever you want to see it as a small floating window; tap it again to hide it. Every active session gets its own transport, window, handoff, volume, mute, and close controls.

The circular-arrows button is the shortcut that changes the experience: it plays that row and pauses the others.

## Install

```bash
omarchy plugin add https://github.com/Rezwoan/omarchy-tube-control.git
omarchy plugin enable io.github.rezwoan.tube-control
```

The plugin replaces Omarchy's built-in media widget while installed. Removing it restores the built-in widget.

## Remove

```bash
omarchy plugin remove io.github.rezwoan.tube-control
```

The plugin stores its two Chromium profiles under `${XDG_DATA_HOME:-~/.local/share}/tube-control/`. Removing the plugin does not delete those profiles, so browser sign-ins are never erased without your explicit action.

## Requirements and permissions

- Omarchy Quattro with the Omarchy shell
- Chromium at `/usr/bin/chromium`
- PipeWire for exact per-player volume and mute controls
- Hyprland and `uwsm-app`, included with Omarchy

No YouTube API key is required. The plugin launches local Chromium app windows — one isolated profile per service, so each gets its own independent MPRIS player, matching PipeWire stream, and window — and uses Hyprland's special workspaces to keep them headless until you ask to see one. It runs entirely without elevated privileges and does not install packages or overwrite user configuration.

### Why isolated Chromium profiles, not your regular browser

Chromium exposes exactly one MPRIS player *per browser process*. Reusing your everyday browser window would put both services in the same process, collapsing them into a single shared player — only one of the two would ever be trackable or controllable, and closing one window could affect the other's playback. Separate profiles force Chromium to run each service as its own process, which is what makes independent play/pause, volume, and close possible. You sign into each profile once; it stays signed in after that.

## License

MIT — see [LICENSE](LICENSE).
