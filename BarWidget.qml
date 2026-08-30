import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "youtube.control-center"

  readonly property var mediaService: bar?.shell?.serviceFor("youtube.control-center")
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
    if (mediaService && player && mediaService.focusPlayerWindow(player))
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

  function launchBrowserApp(url, appClass, profileName) {
    if (launchProcess.running) return
    launchFailed = false

    var dataHome = Quickshell.env("XDG_DATA_HOME")
    if (!dataHome) dataHome = Quickshell.env("HOME") + "/.local/share"
    var profilePath = dataHome + "/youtube-control-center/" + profileName
    var browserCommand = "uwsm-app -- /usr/bin/chromium"
      + " --user-data-dir=" + shellQuote(profilePath)
      + " --no-first-run --no-default-browser-check --new-window --app=" + shellQuote(url)
    var lua = "if _G.youtube_control_center_launch_rule then "
      + "_G.youtube_control_center_launch_rule:set_enabled(false) end; "
      + "local ws = hl.get_active_workspace(); "
      + "assert(ws, \"no active workspace\"); "
      + "local app_class = " + JSON.stringify(appClass) + "; "
      + "_G.youtube_control_center_launch_rule = hl.window_rule({ "
      + "name = \"youtube-control-center-launch\", "
      + "match = { class = app_class }, "
      + "workspace = tostring(ws.id) .. \" silent\"}); "
      + "hl.exec_cmd(" + JSON.stringify(browserCommand) + ")"

    launchProcess.command = ["hyprctl", "eval", lua]
    launchProcess.running = true
    launchRuleCleanup.restart()
    popupOpen = false
  }

  function launchYoutubeMusic(query) {
    var cleanQuery = String(query || "").trim()
    var url = cleanQuery === ""
      ? "https://music.youtube.com/"
      : "https://music.youtube.com/search?q=" + encodeURIComponent(cleanQuery)
    launchBrowserApp(url, "^chrome-music\\.youtube\\.com__.*$", "youtube-music")
  }

  function launchYoutube(query) {
    var cleanQuery = String(query || "").trim()
    var url = cleanQuery === ""
      ? "https://www.youtube.com/"
      : "https://www.youtube.com/results?search_query=" + encodeURIComponent(cleanQuery)
    launchBrowserApp(url, "^chrome-www\\.youtube\\.com__.*$", "youtube")
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
          tooltipText: "Show video window"
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

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    // PopupWindow is non-focusable by default; enable keyboard input for searchField.
    focusable: true
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
          : "Independent app profiles allow both rows to play. Sign in once in each app."
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
            }

            PlayerGroup {
              appName: "YouTube Music"
              appIcon: "󰝚"
              players: root.musicPlayers
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

  Timer {
    id: launchRuleCleanup
    interval: 8000
    repeat: false
    onTriggered: {
      if (cleanupProcess.running) return
      cleanupProcess.command = [
        "hyprctl",
        "eval",
        "if _G.youtube_control_center_launch_rule then "
          + "_G.youtube_control_center_launch_rule:set_enabled(false); "
          + "_G.youtube_control_center_launch_rule = nil end"
      ]
      cleanupProcess.running = true
    }
  }

  Process {
    id: cleanupProcess
    running: false
  }
}
