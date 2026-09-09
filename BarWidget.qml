import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "io.github.rezwoan.tube-control"

  readonly property var mediaService: bar?.shell?.serviceFor("io.github.rezwoan.tube-control")
  readonly property var activePlayer: mediaService ? mediaService.activePlayer : null
  readonly property var sourcePlayers: mediaService ? mediaService.sourcePlayers : []
  readonly property var youtubePlayers: mediaService ? mediaService.playersForGroup("youtube") : []
  readonly property var musicPlayers: mediaService ? mediaService.playersForGroup("music") : []
  readonly property var otherPlayers: mediaService ? mediaService.playersForGroup("other") : []

  readonly property bool hasPlayer: activePlayer !== null
  readonly property bool hasMedia: hasPlayer && (activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property string title: hasPlayer ? (activePlayer.trackTitle || activePlayer.identity || "Media") : ""
  readonly property string artist: hasPlayer ? (activePlayer.trackArtist || "") : ""
  readonly property int playingCount: countPlayingPlayers()

  function countPlayingPlayers() {
    var count = 0
    for (var i = 0; i < sourcePlayers.length; i++) {
      if (sourcePlayers[i] && sourcePlayers[i].isPlaying) count += 1
    }
    return count
  }

  property bool popupOpen: false
  readonly property bool opened: popupOpen
  property bool launchFailed: false

  function open() {
    popupOpen = true
  }

  function toggle() {
    popupOpen = !popupOpen
  }

  function close() {
    popupOpen = false
  }

  function playerKey(player) {
    return mediaService && player ? mediaService.playerKey(player) : ""
  }

  function runMediaAction(player, action) {
    if (mediaService && player)
      mediaService.runAction(action, false, playerKey(player))
  }

  function handoffTo(player) {
    if (mediaService && player) mediaService.handoffToPlayer(player)
  }

  function showPlayer(player) {
    if (mediaService && player && mediaService.toggleServiceWindow(player))
      popupOpen = false
  }

  // Toggles a service's special workspace directly by name, independent of
  // whether an MPRIS player currently exists for it — this is what lets a
  // freshly launched, not-yet-playing window be revealed at all.
  function toggleGroupWindow(specialWorkspace) {
    if (!specialWorkspace || toggleGroupProcess.running) return
    toggleGroupProcess.command = [
      "hyprctl", "dispatch",
      "hl.dsp.workspace.toggle_special(" + JSON.stringify(specialWorkspace) + ")"
    ]
    toggleGroupProcess.running = true
    popupOpen = false
  }
  function playerVolumeAvailable(player) {
    return !!(mediaService && player && mediaService.playerAudioAvailable(player))
  }

  function playerVolumePercent(player) {
    return playerVolumeAvailable(player)
      ? Math.round(mediaService.playerAudioVolume(player) * 100) : 0
  }

  function playerMuted(player) {
    return !!(mediaService && player && mediaService.playerAudioMuted(player))
  }
  function channelInitial(player) {
    var label = player
      ? String(player.trackArtist || player.identity || "").trim() : ""
    return label ? label.charAt(0).toUpperCase() : "•"
  }

  function adjustPlayerVolume(player, delta) {
    if (mediaService && player) mediaService.adjustPlayerVolume(player, delta)
  }

  function togglePlayerMute(player) {
    if (mediaService && player) mediaService.togglePlayerMute(player)
  }

  function closePlayer(player) {
    if (mediaService && player) mediaService.closePlayerWindow(player)
  }

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\"'\"'") + "'"
  }

  // Each service (YouTube / YouTube Music) gets its own isolated Chromium
  // profile, so Chromium starts a genuinely separate OS process per
  // service. This matters beyond sign-in isolation: Chromium exposes
  // exactly one MPRIS player PER PROCESS, so separate processes are the
  // only way to get independent play/pause/volume/close per service.
  // Sharing a browser process (e.g. the user's already-running default
  // browser) collapses both services into a single shared player.
  readonly property var serviceSpecs: ({
    youtube: {
      profile: "youtube",
      appClass: "^chrome-www\\.youtube\\.com__.*$",
      specialWorkspace: "tube-control-youtube"
    },
    music: {
      profile: "youtube-music",
      appClass: "^chrome-music\\.youtube\\.com__.*$",
      specialWorkspace: "tube-control-music"
    }
  })

  // Registers a permanent window rule per service: float, a compact
  // mini-player size, and — critically — open directly into a hidden
  // Hyprland "special workspace". That's what makes playback headless by
  // default: the window exists and plays from the moment it opens, but
  // is never shown until the player row's toggle button reveals it.
  function registerWindowRules() {
    var stmts = []
    for (var key in serviceSpecs) {
      var spec = serviceSpecs[key]
      var ruleVar = "_G.tube_control_rule_" + spec.profile.replace(/-/g, "_")
      stmts.push(
        "if " + ruleVar + " then " + ruleVar + ":set_enabled(false) end; "
        + ruleVar + " = hl.window_rule({ "
        + "name = " + JSON.stringify("tube-control-" + spec.profile) + ", "
        + "match = { class = " + JSON.stringify(spec.appClass) + " }, "
        + "workspace = " + JSON.stringify("special:" + spec.specialWorkspace) + ", "
        + "float = true, "
        + "size = \"640 420\" })"
      )
    }
    windowRuleProcess.command = ["hyprctl", "eval", stmts.join("; ")]
    windowRuleProcess.running = true
  }

  // A brand-new Hyprland special workspace shows itself the moment the
  // first window ever lands in it, even though the window_rule sends it
  // straight there — so a genuinely fresh launch briefly flashes visible.
  // Once hidden (or once it already has a window), it stays exactly as
  // last left, so this only ever needs to run once per service per
  // Hyprland session. Reusing an already-open window (the profile's
  // browser process is still running, e.g. a second search) never goes
  // through this at all, so it can't yank the window away from someone
  // currently watching it.
  property var pendingHide: null

  function checkPendingHide() {
    if (!pendingHide || pendingHideCheckProcess.running) return
    pendingHideCheckProcess.running = true
  }

  // Polls hyprctl directly (rather than the service's cached window list,
  // which only refreshes on player/popup events) so this reliably notices
  // the new window within a few hundred ms of it actually appearing.
  function applyPendingHideCheck(raw) {
    var pending = pendingHide
    if (!pending) return

    var found = false
    try {
      var list = JSON.parse(String(raw || "[]"))
      var re = new RegExp(pending.appClass)
      for (var i = 0; i < list.length; i++) {
        if (list[i] && re.test(String(list[i].class || ""))) { found = true; break }
      }
    } catch (error) {
      found = false
    }

    if (found) {
      hideSpecialProcess.command = [
        "hyprctl", "dispatch",
        "hl.dsp.workspace.toggle_special(" + JSON.stringify(pending.specialWorkspace) + ")"
      ]
      hideSpecialProcess.running = true
      pendingHide = null
      return
    }

    pending.attempts += 1
    if (pending.attempts >= 8) { pendingHide = null; return } // gave up quietly after ~3.2s
    pendingHide = pending
    hideAfterLaunchTimer.restart()
  }

  function launchBrowserApp(url, profileName, appClass, specialWorkspace) {
    if (launchProcess.running) return
    launchFailed = false

    var dataHome = Quickshell.env("XDG_DATA_HOME")
    if (!dataHome) dataHome = Quickshell.env("HOME") + "/.local/share"
    var profilePath = dataHome + "/tube-control/" + profileName
    var browserCommand = "uwsm-app -- /usr/bin/chromium"
      + " --user-data-dir=" + shellQuote(profilePath)
      + " --no-first-run --no-default-browser-check --new-window --app=" + shellQuote(url)

    var alreadyRunning = mediaService && mediaService.hasWindowMatchingClass(appClass)

    launchProcess.command = ["hyprctl", "eval", "hl.exec_cmd(" + JSON.stringify(browserCommand) + ")"]
    launchProcess.running = true
    popupOpen = false

    if (!alreadyRunning) {
      pendingHide = { appClass: appClass, specialWorkspace: specialWorkspace, attempts: 0 }
      hideAfterLaunchTimer.restart()
    }
  }

  function launchYoutubeMusic(query) {
    var cleanQuery = String(query || "").trim()
    var url = cleanQuery === ""
      ? "https://music.youtube.com/"
      : "https://music.youtube.com/search?q=" + encodeURIComponent(cleanQuery)
    launchBrowserApp(url, serviceSpecs.music.profile, serviceSpecs.music.appClass, serviceSpecs.music.specialWorkspace)
  }

  function launchYoutube(query) {
    var cleanQuery = String(query || "").trim()
    var url = cleanQuery === ""
      ? "https://www.youtube.com/"
      : "https://www.youtube.com/results?search_query=" + encodeURIComponent(cleanQuery)
    launchBrowserApp(url, serviceSpecs.youtube.profile, serviceSpecs.youtube.appClass, serviceSpecs.youtube.specialWorkspace)
  }

  onPopupOpenChanged: {
    if (popupOpen) {
      if (mediaService) mediaService.refreshMediaWindows()
      Qt.callLater(function() {
        searchField.forceActiveFocus()
        searchField.selectAll()
      })
    } else {
      searchField.focus = false
    }
  }

  Component.onCompleted: root.registerWindowRules()

  visible: true
  implicitWidth: youtubeButton.implicitWidth
  implicitHeight: barSize

  WidgetButton {
    id: youtubeButton
    anchors.fill: parent
    bar: root.bar
    text: "󰗃"
    fontSize: Style.font.iconLarge
    active: root.playingCount > 0
    useActiveColor: false
    horizontalMargin: 7
    tooltipText: root.playingCount > 1
      ? root.playingCount + " media sessions playing"
      : (root.hasMedia
          ? root.title + (root.artist ? " — " + root.artist : "")
          : "YouTube and YouTube Music")
    onPressed: root.toggle()
  }

  component PlayerRow: Item {
    id: playerRow

    required property var player
    required property string appName

    width: parent ? parent.width : 0
    implicitHeight: Style.space(88)

    BorderSurface {
      anchors.fill: parent
      radius: Style.spacing.labelGap
      color: Style.normalFillFor(root.bar.foreground, Color.accent)
      borderSpec: Border.controlSpec(
        playerRow.player && playerRow.player.isPlaying ? "active" : "normal",
        root.bar.foreground,
        Color.accent
      )
    }

    Column {
      id: rowContent
      anchors.fill: parent
      anchors.margins: Style.space(7)
      spacing: Style.space(5)

      Row {
        id: identityRow
        width: parent.width
        height: Style.space(34)
        spacing: Style.space(7)

        BorderSurface {
          id: channelAvatar
          width: identityRow.height
          height: width
          radius: width / 2
          color: Style.normalFillFor(Color.accent, root.bar.foreground)
          borderSpec: Border.controlSpec("active", root.bar.foreground, Color.accent)

          Text {
            anchors.centerIn: parent
            text: root.channelInitial(playerRow.player)
            textFormat: Text.PlainText
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }
        }

        Column {
          width: identityRow.width - channelAvatar.width - identityRow.spacing
          spacing: Style.space(1)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: playerRow.player
              ? (playerRow.player.trackTitle || playerRow.player.identity || playerRow.appName)
              : playerRow.appName
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: playerRow.player
              ? (playerRow.player.trackArtist || playerRow.player.identity || playerRow.appName)
              : ""
            color: Qt.darker(root.bar.foreground, 1.35)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }

      Row {
        id: controlRow
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(2)

        Button {
          iconText: "󰒮"
          foreground: root.bar.foreground
          enabled: playerRow.player && playerRow.player.canGoPrevious
          opacity: enabled ? 1 : 0.35
          tooltipText: "Previous in " + playerRow.appName
          onClicked: root.runMediaAction(playerRow.player, "previous")
        }

        Button {
          iconText: playerRow.player && playerRow.player.isPlaying ? "󰏤" : "󰐊"
          foreground: root.bar.foreground
          enabled: playerRow.player && (playerRow.player.canTogglePlaying
            || playerRow.player.canPlay || playerRow.player.canPause)
          opacity: enabled ? 1 : 0.35
          tooltipText: playerRow.player && playerRow.player.isPlaying
            ? "Pause this player" : "Play this player"
          onClicked: root.runMediaAction(playerRow.player, "playPause")
        }

        Button {
          iconText: "󰒭"
          foreground: root.bar.foreground
          enabled: playerRow.player && playerRow.player.canGoNext
          opacity: enabled ? 1 : 0.35
          tooltipText: "Next in " + playerRow.appName
          onClicked: root.runMediaAction(playerRow.player, "next")
        }

        Button {
          iconText: "󰕧"
          foreground: root.bar.foreground
          enabled: playerRow.player && root.mediaService
            && (root.mediaService.clientForPlayer(playerRow.player) || playerRow.player.canRaise)
          opacity: enabled ? 1 : 0.35
          tooltipText: "Show/hide the floating window (keeps playing either way)"
          onClicked: root.showPlayer(playerRow.player)
        }

        Button {
          iconText: "󰓦"
          foreground: root.bar.foreground
          enabled: playerRow.player && (playerRow.player.isPlaying
            || playerRow.player.canPlay || playerRow.player.canTogglePlaying)
          opacity: enabled ? 1 : 0.35
          tooltipText: "Play only this; pause every other player"
          onClicked: root.handoffTo(playerRow.player)
        }

        Button {
          iconText: "󰝞"
          foreground: root.bar.foreground
          enabled: root.playerVolumeAvailable(playerRow.player)
          opacity: enabled ? 1 : 0.35
          tooltipText: "Volume down (" + root.playerVolumePercent(playerRow.player) + "%)"
          onClicked: root.adjustPlayerVolume(playerRow.player, -0.1)
        }

        Button {
          iconText: root.playerMuted(playerRow.player) ? "󰝟" : "󰕾"
          foreground: root.bar.foreground
          enabled: root.playerVolumeAvailable(playerRow.player)
          opacity: enabled ? 1 : 0.35
          tooltipText: root.playerMuted(playerRow.player)
            ? "Unmute this player"
            : "Mute this player (" + root.playerVolumePercent(playerRow.player) + "%)"
          onClicked: root.togglePlayerMute(playerRow.player)
        }

        Button {
          iconText: "󰝝"
          foreground: root.bar.foreground
          enabled: root.playerVolumeAvailable(playerRow.player)
          opacity: enabled ? 1 : 0.35
          tooltipText: "Volume up (" + root.playerVolumePercent(playerRow.player) + "%)"
          onClicked: root.adjustPlayerVolume(playerRow.player, 0.1)
        }

        Button {
          iconText: "󰅖"
          foreground: Color.urgent
          enabled: playerRow.player && root.mediaService
            && root.mediaService.canClosePlayer(playerRow.player)
          opacity: enabled ? 1 : 0.35
          tooltipText: "Close this video window"
          onClicked: root.closePlayer(playerRow.player)
        }
      }
    }
  }

  component PlayerGroup: Column {
    id: playerGroup

    required property string appName
    required property string appIcon
    required property var players
    // Present only for services this plugin itself launches (YouTube /
    // YouTube Music); empty for "Other media". Lets the group be shown
    // even before any MPRIS player exists yet — a freshly launched,
    // not-yet-playing window has no player to hang a per-row button off,
    // so this is the only way to reveal it for that first interaction.
    property string specialWorkspace: ""

    width: parent ? parent.width : 0
    spacing: Style.space(5)

    Row {
      width: parent.width
      spacing: Style.space(6)

      Text {
        text: playerGroup.appIcon
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.icon
      }

      Text {
        text: playerGroup.appName
        textFormat: Text.PlainText
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      Text {
        text: playerGroup.players.length > 2
          ? "2+"
          : (playerGroup.players.length > 0 ? String(playerGroup.players.length) : "")
        color: Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }

      Button {
        visible: playerGroup.specialWorkspace !== ""
        iconText: "󰕧"
        foreground: root.bar.foreground
        tooltipText: "Show/hide the " + playerGroup.appName + " window (keeps playing either way)"
        onClicked: root.toggleGroupWindow(playerGroup.specialWorkspace)
      }
    }

    Text {
      width: parent.width
      visible: playerGroup.players.length === 0
      text: "No active " + playerGroup.appName + " session"
      textFormat: Text.PlainText
      color: Qt.darker(root.bar.foreground, 1.45)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.caption
    }

    Repeater {
      model: playerGroup.players.slice(0, 2)

      PlayerRow {
        required property var modelData
        width: playerGroup.width
        player: modelData
        appName: playerGroup.appName
      }
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    // PopupWindow (xdg-popup) never gets map-time keyboard focus; KeyboardPanel
    // is the layer-shell variant that primes focus for searchField.
    focusTarget: searchField
    contentWidth: popup.fittedContentWidth(Style.space(400))
    contentHeight: popup.fittedContentHeight(content.implicitHeight)

    Column {
      id: content
      anchors.fill: parent
      spacing: Style.space(10)


      Text {
        text: "Search"
        textFormat: Text.PlainText
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      TextField {
        id: searchField
        width: parent.width
        placeholderText: "Song, artist, or video"
        foreground: root.bar.foreground
        accent: Color.accent
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        onAccepted: root.launchYoutubeMusic(text)
        Keys.onEscapePressed: root.close()
      }

      Column {
        width: parent.width
        spacing: Style.space(6)

        Button {
          width: parent.width
          iconText: "󰗃"
          text: searchField.text.trim() === "" ? "YouTube" : "Search YouTube"
          foreground: root.bar.foreground
          bordered: true
          enabled: !launchProcess.running
          opacity: enabled ? 1 : 0.5
          onClicked: root.launchYoutube(searchField.text)
        }

        Button {
          width: parent.width
          iconText: "󰝚"
          text: searchField.text.trim() === "" ? "YouTube Music" : "Search Music"
          foreground: root.bar.foreground
          bordered: true
          enabled: !launchProcess.running
          opacity: enabled ? 1 : 0.5
          onClicked: root.launchYoutubeMusic(searchField.text)
        }
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.launchFailed
          ? "Could not open the Chromium app window."
          : "Opens headless in the background. Sign in once per app, then use the video icon to show or hide it."
        color: root.launchFailed ? Color.urgent : Qt.darker(root.bar.foreground, 1.5)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      PanelSeparator {
        foreground: root.bar.foreground
      }

      Text {
        text: "Players"
        textFormat: Text.PlainText
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      Item {
        id: playerViewport
        width: parent.width
        height: Math.min(playerGroups.implicitHeight, Style.space(300))
        clip: true

        Flickable {
          anchors.fill: parent
          contentWidth: width
          contentHeight: playerGroups.implicitHeight
          interactive: contentHeight > height
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: playerGroups
            width: parent.width
            spacing: Style.space(10)

            PlayerGroup {
              appName: "YouTube"
              appIcon: "󰗃"
              players: root.youtubePlayers
              specialWorkspace: root.serviceSpecs.youtube.specialWorkspace
            }

            PlayerGroup {
              appName: "YouTube Music"
              appIcon: "󰝚"
              players: root.musicPlayers
              specialWorkspace: root.serviceSpecs.music.specialWorkspace
            }

            PlayerGroup {
              visible: root.otherPlayers.length > 0
              appName: "Other media"
              appIcon: "󰎆"
              players: root.otherPlayers
            }
          }
        }
      }
    }
  }

  Process {
    id: launchProcess
    running: false
    onExited: function(exitCode) {
      root.launchFailed = exitCode !== 0
    }
  }

  Process {
    id: windowRuleProcess
    running: false
  }

  Timer {
    id: hideAfterLaunchTimer
    interval: 400
    repeat: false
    onTriggered: root.checkPendingHide()
  }

  Process {
    id: hideSpecialProcess
    running: false
  }

  Process {
    id: toggleGroupProcess
    running: false
  }

  Process {
    id: pendingHideCheckProcess
    command: ["hyprctl", "clients", "-j"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyPendingHideCheck(text)
    }
  }
}
