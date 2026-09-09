import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import "MediaModel.js" as MediaModel

Item {
  id: root

  property var shell: null
  property string preferredPlayerKey: ""
  property var playerStartedAt: ({})
  property var mediaWindows: []
  property bool mediaWindowRefreshPending: false
  property var processParents: ({})
  property bool processTreeRefreshPending: false
  property var pendingTrackOsd: null
  property int playSerial: 0

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var playbackStreams: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.isStream && isPlaybackStream(n) && n.audio) list.push(n)
    }
    return list
  }
  readonly property var sourcePlayers: orderedSourcePlayers()
  readonly property var sourceCyclePlayers: orderedCycleSourcePlayers()
  readonly property var activePlayer: selectActivePlayer()
  readonly property bool hasMedia: activePlayer !== null && (activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property string title: activePlayer ? (activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? (activePlayer.trackArtist || "") : ""
  readonly property string album: activePlayer && activePlayer.trackAlbum ? activePlayer.trackAlbum : ""
  readonly property string artUrl: activePlayer && activePlayer.trackArtUrl ? activePlayer.trackArtUrl : ""
  readonly property string identity: activePlayer ? (activePlayer.identity || activePlayer.desktopEntry || "") : ""

  function isProxyPlayer(player) {
    return MediaModel.isProxyPlayer(player)
  }

  function hasMetadata(player) {
    return MediaModel.hasMetadata(player)
  }

  function hasTrackMetadata(player) {
    return MediaModel.hasTrackMetadata(player)
  }

  function playerCanControl(player) {
    return MediaModel.playerCanControl(player)
  }

  function canHandleAction(player, action) {
    return MediaModel.canHandleAction(player, action)
  }

  function canCycleSource(player) {
    return MediaModel.canCycleSource(player)
  }

  function nodeProps(node) {
    return MediaModel.nodeProps(node)
  }

  function isPlaybackStream(node) {
    return MediaModel.isPlaybackStream(node)
  }

  function streamLabelKey(label) {
    return MediaModel.streamLabelKey(label)
  }

  function rawStreamLabel(node) {
    return MediaModel.rawStreamLabel(node)
  }

  function playerAppLabel(player) {
    return MediaModel.playerAppLabel(player)
  }

  function playerHasPlaybackStream(player) {
    return MediaModel.playerHasPlaybackStream(player, playbackStreams)
  }

  function playerKey(player) {
    return MediaModel.playerKey(player)
  }

  function playerForKey(key) {
    if (!key) return null
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (playerKey(p) === key) return p
    }
    return null
  }
  function playerPid(player) {
    var match = /\.instance(\d+)$/.exec(playerKey(player))
    return match ? Number(match[1]) : -1
  }

  function normalizedWindowTitle(value) {
    return String(value || "")
      .replace(/[\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, "")
      .replace(/\s+/g, " ")
      .trim()
      .toLowerCase()
  }

  function processClientsFor(player) {
    var pid = playerPid(player)
    var matches = []
    if (pid < 0) return matches

    for (var i = 0; i < mediaWindows.length; i++) {
      var client = mediaWindows[i]
      if (client && Number(client.pid) === pid) matches.push(client)
    }
    return matches
  }

  function clientForPlayer(player) {
    var clients = processClientsFor(player)
    if (clients.length === 0) return null

    var track = normalizedWindowTitle(player && player.trackTitle)
    if (track) {
      for (var i = 0; i < clients.length; i++) {
        var title = normalizedWindowTitle(clients[i].title)
        if (title.indexOf(track) !== -1 || track.indexOf(title) !== -1)
          return clients[i]
      }
    }

    return clients.length === 1 ? clients[0] : null
  }

  function groupForClient(client) {
    if (!client) return ""
    var appClass = String(client.class || "").toLowerCase()
    var title = normalizedWindowTitle(client.title)
    if (appClass.indexOf("music.youtube.com") !== -1 || title.indexOf("youtube music") !== -1)
      return "music"
    if (appClass.indexOf("youtube.com") !== -1 || title.indexOf("youtube") !== -1)
      return "youtube"
    return ""
  }

  function playerGroup(player) {
    if (!player) return "other"

    var metadata = player.metadata || {}
    var mediaUrl = String(metadata["xesam:url"] || "").toLowerCase()
    if (mediaUrl.indexOf("music.youtube.com") !== -1) return "music"
    if (mediaUrl.indexOf("youtube.com") !== -1 || mediaUrl.indexOf("youtu.be") !== -1)
      return "youtube"

    var matchedGroup = groupForClient(clientForPlayer(player))
    if (matchedGroup) return matchedGroup

    var clients = processClientsFor(player)
    var sawMusic = false
    var sawYoutube = false
    for (var i = 0; i < clients.length; i++) {
      var group = groupForClient(clients[i])
      if (group === "music") sawMusic = true
      else if (group === "youtube") sawYoutube = true
    }
    if (sawMusic && !sawYoutube) return "music"
    if (sawYoutube && !sawMusic) return "youtube"

    var identity = String(player.identity || player.desktopEntry || "").toLowerCase()
    if (identity.indexOf("youtube music") !== -1) return "music"
    if (identity.indexOf("youtube") !== -1) return "youtube"
    return "other"
  }

  function playersForGroup(group) {
    var matches = []
    for (var i = 0; i < sourcePlayers.length; i++) {
      if (playerGroup(sourcePlayers[i]) === group) matches.push(sourcePlayers[i])
    }
    return matches
  }

  function refreshMediaWindows() {
    if (mediaWindowProcess.running) {
      mediaWindowRefreshPending = true
      return
    }
    mediaWindowRefreshPending = false
    mediaWindowProcess.running = true
  }

  function applyMediaWindows(raw) {
    try {
      var parsed = JSON.parse(String(raw || "[]"))
      mediaWindows = Array.isArray(parsed) ? parsed : []
    } catch (error) {
      mediaWindows = []
    }
  }

  function hasWindowMatchingClass(pattern) {
    if (!pattern) return false
    var re
    try { re = new RegExp(pattern) } catch (error) { return false }
    for (var i = 0; i < mediaWindows.length; i++) {
      var w = mediaWindows[i]
      if (w && re.test(String(w.class || ""))) return true
    }
    return false
  }

  function focusPlayerWindow(player) {
    if (!player) return false

    var client = clientForPlayer(player)
    if (!client) {
      var wantedGroup = playerGroup(player)
      var clients = processClientsFor(player)
      for (var i = 0; i < clients.length; i++) {
        if (groupForClient(clients[i]) === wantedGroup) {
          client = clients[i]
          break
        }
      }
    }

    if (client && client.address && !focusWindowProcess.running) {
      focusWindowProcess.command = [
        "hyprctl",
        "dispatch",
        "hl.dsp.focus({ window = \"address:" + String(client.address) + "\" })"
      ]
      focusWindowProcess.running = true
      return true
    }

    if (player.canRaise) {
      player.raise()
      return true
    }
    return false
  }

  // Players launched by this plugin always open into a dedicated hidden
  // Hyprland "special workspace" per service (see BarWidget.qml's
  // registerWindowRules) so playback starts headless. Toggling that
  // special workspace shows/hides the window as a small floating player
  // without touching playback at all. Anything else (e.g. a player from a
  // regular browser tab, not one of this plugin's app windows) has no
  // dedicated special workspace, so fall back to a normal focus/raise.
  function specialWorkspaceForGroup(group) {
    if (group === "youtube") return "tube-control-youtube"
    if (group === "music") return "tube-control-music"
    return ""
  }

  function toggleServiceWindow(player) {
    if (!player) return false

    var wsName = specialWorkspaceForGroup(playerGroup(player))
    if (wsName && !toggleWorkspaceProcess.running) {
      toggleWorkspaceProcess.command = [
        "hyprctl",
        "dispatch",
        "hl.dsp.workspace.toggle_special(" + JSON.stringify(wsName) + ")"
      ]
      toggleWorkspaceProcess.running = true
      return true
    }

    return focusPlayerWindow(player)
  }

  function canClosePlayer(player) {
    return !!(player && (clientForPlayer(player) || player.canQuit))
  }

  function closePlayerWindow(player) {
    if (!player) return false

    var client = clientForPlayer(player)
    if (client && client.address && !closeWindowProcess.running) {
      closeWindowProcess.command = [
        "hyprctl",
        "dispatch",
        "hl.dsp.window.close({ window = \"address:" + String(client.address) + "\" })"
      ]
      closeWindowProcess.running = true
      return true
    }

    if (player.canQuit) {
      player.quit()
      return true
    }
    return false
  }

  function clampPlayerVolume(value) {
    return Math.max(0, Math.min(1, Number(value)))
  }

  function processPidForNode(node) {
    var props = nodeProps(node)
    return Number(props["application.process.id"] || -1)
  }

  function processBelongsToPlayer(processId, playerProcessId) {
    var current = Number(processId)
    var target = Number(playerProcessId)
    if (current < 0 || target < 0) return false

    for (var depth = 0; depth < 32 && current > 0; depth++) {
      if (current === target) return true
      var parent = Number(processParents[String(current)] || 0)
      if (parent <= 0 || parent === current) break
      current = parent
    }
    return false
  }

  function streamLabelMatchesPlayer(node, player) {
    var playerLabel = streamLabelKey(playerAppLabel(player))
    var streamLabel = streamLabelKey(rawStreamLabel(node))
    return !!(playerLabel && streamLabel
      && (playerLabel === streamLabel
        || playerLabel.indexOf(streamLabel) !== -1
        || streamLabel.indexOf(playerLabel) !== -1))
  }

  function audioStreamsForPlayer(player) {
    var matches = []
    if (!player) return matches

    var mainPid = playerPid(player)
    for (var i = 0; i < playbackStreams.length; i++) {
      var stream = playbackStreams[i]
      if (stream && stream.audio
          && processBelongsToPlayer(processPidForNode(stream), mainPid))
        matches.push(stream)
    }

    if (matches.length === 0 && sourcePlayers.length === 1) {
      for (var fallbackIndex = 0; fallbackIndex < playbackStreams.length; fallbackIndex++) {
        var fallback = playbackStreams[fallbackIndex]
        if (fallback && fallback.audio && streamLabelMatchesPlayer(fallback, player))
          matches.push(fallback)
      }
    }
    return matches
  }

  function playerAudioAvailable(player) {
    return audioStreamsForPlayer(player).length > 0
  }

  function playerAudioVolume(player) {
    var streams = audioStreamsForPlayer(player)
    return streams.length > 0 && streams[0].audio
      ? clampPlayerVolume(streams[0].audio.volume) : 0
  }

  function playerAudioMuted(player) {
    var streams = audioStreamsForPlayer(player)
    if (streams.length === 0) return false
    for (var i = 0; i < streams.length; i++) {
      if (streams[i].audio && streams[i].audio.muted) return true
    }
    return false
  }

  function adjustPlayerVolume(player, delta) {
    var streams = audioStreamsForPlayer(player)
    if (streams.length === 0) return false

    for (var i = 0; i < streams.length; i++) {
      var audio = streams[i].audio
      if (audio) audio.volume = clampPlayerVolume(Number(audio.volume) + Number(delta))
    }
    return true
  }

  function togglePlayerMute(player) {
    var streams = audioStreamsForPlayer(player)
    if (streams.length === 0) return false

    var mute = false
    for (var i = 0; i < streams.length; i++) {
      if (streams[i].audio && !streams[i].audio.muted) {
        mute = true
        break
      }
    }
    for (var streamIndex = 0; streamIndex < streams.length; streamIndex++) {
      if (streams[streamIndex].audio) streams[streamIndex].audio.muted = mute
    }
    return true
  }

  function refreshProcessTree() {
    if (processTreeProcess.running) {
      processTreeRefreshPending = true
      return
    }
    processTreeRefreshPending = false
    processTreeProcess.running = true
  }

  function applyProcessTree(raw) {
    var parents = ({})
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var match = /^\s*(\d+)\s+(\d+)\s*$/.exec(lines[i])
      if (match) parents[match[1]] = Number(match[2])
    }
    processParents = parents
  }

  function playerOrder(player, fallback) {
    var key = playerKey(player)
    var value = key ? playerStartedAt[key] : undefined
    return value === undefined ? fallback : value
  }

  function syncPlayingOrder() {
    var next = {}
    var alive = {}
    var serial = playSerial

    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      var key = playerKey(p)
      if (!key) continue

      alive[key] = true
      if (!p.isPlaying) continue

      if (playerStartedAt[key] === undefined) {
        serial += 1
        next[key] = serial
      } else {
        next[key] = playerStartedAt[key]
      }
    }

    if (preferredPlayerKey && !alive[preferredPlayerKey]) preferredPlayerKey = ""

    playSerial = serial
    playerStartedAt = next
  }

  function orderedSourcePlayers() {
    var direct = []
    var proxies = []
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!hasMetadata(p)) continue
      if (isProxyPlayer(p)) proxies.push(p)
      else direct.push(p)
    }

    var list = direct.length > 0 ? direct : proxies
    list.sort(function(a, b) {
      if (!!a.isPlaying !== !!b.isPlaying) return a.isPlaying ? -1 : 1
      if (a.isPlaying && b.isPlaying) {
        var orderDelta = playerOrder(a, 1000) - playerOrder(b, 1000)
        if (orderDelta !== 0) return orderDelta
      }
      return labelFor(a).localeCompare(labelFor(b))
    })

    return list
  }

  function orderedCycleSourcePlayers() {
    var list = []
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (canCycleSource(p)) list.push(p)
    }

    list.sort(function(a, b) {
      if (isProxyPlayer(a) !== isProxyPlayer(b)) return isProxyPlayer(a) ? 1 : -1
      return labelFor(a).localeCompare(labelFor(b))
    })

    return list
  }

  function oldestPlayingPlayer(requirePlaybackStream) {
    var oldest = null
    var oldestOrder = 0
    var playingProxy = null
    var proxyOrder = 0

    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p) continue

      var proxyPlayer = isProxyPlayer(p)
      if (p.isPlaying) {
        if (requirePlaybackStream && !playerHasPlaybackStream(p)) continue

        var order = playerOrder(p, i + 1000)
        if (!proxyPlayer && (!oldest || order < oldestOrder)) {
          oldest = p
          oldestOrder = order
        } else if (proxyPlayer && (!playingProxy || order < proxyOrder)) {
          playingProxy = p
          proxyOrder = order
        }
      }
    }

    return oldest || playingProxy || null
  }

  function selectActivePlayer() {
    var preferred = null
    var trackPlayer = null
    var trackProxy = null
    var streamPlayer = null
    var streamProxy = null
    var controllablePlayer = null
    var controllableProxy = null
    var identityPlayer = null
    var identityProxy = null

    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p) continue

      var proxy = isProxyPlayer(p)

      if (preferredPlayerKey && playerKey(p) === preferredPlayerKey && hasMetadata(p)) preferred = p

      if (playerHasPlaybackStream(p)) {
        if (!proxy && !streamPlayer) streamPlayer = p
        else if (proxy && !streamProxy) streamProxy = p
      } else if (hasTrackMetadata(p)) {
        if (!proxy && !trackPlayer) trackPlayer = p
        else if (proxy && !trackProxy) trackProxy = p
      } else if (playerCanControl(p)) {
        if (!proxy && !controllablePlayer) controllablePlayer = p
        else if (proxy && !controllableProxy) controllableProxy = p
      } else if (hasMetadata(p)) {
        if (!proxy && !identityPlayer) identityPlayer = p
        else if (proxy && !identityProxy) identityProxy = p
      }
    }

    if (preferred && preferred.isPlaying) return preferred
    var streamCandidate = streamPlayer || streamProxy
    var streamPreferred = preferred && playerHasPlaybackStream(preferred) ? preferred : null
    return oldestPlayingPlayer(true) || oldestPlayingPlayer(false) || streamPreferred || streamCandidate || preferred || trackPlayer || trackProxy || controllablePlayer || controllableProxy || identityPlayer || identityProxy || null
  }

  function labelFor(player) {
    return MediaModel.labelFor(player)
  }

  function osdMessage(player, fallback) {
    return MediaModel.osdMessage(player, fallback)
  }

  function trackSignature(player) {
    return MediaModel.trackSignature(player)
  }

  function showOsd(actionLabel, iconName, player) {
    if (!shell) return
    shell.summon("omarchy.osd", JSON.stringify({
      icon: iconName || "media",
      message: osdMessage(player || activePlayer, actionLabel)
    }))
  }

  function scheduleOsd(actionLabel, iconName, player, waitForTrackChange, beforeTrackSignature) {
    if (waitForTrackChange) {
      pendingTrackOsd = {
        actionLabel: actionLabel,
        iconName: iconName,
        player: player,
        playerKey: playerKey(player),
        before: beforeTrackSignature,
        attempts: 0
      }
      trackOsdTimer.restart()
    } else {
      Qt.callLater(function() { root.showOsd(actionLabel, iconName, player) })
    }
  }

  function flushPendingTrackOsd(force) {
    var pending = pendingTrackOsd
    if (!pending) return

    var player = playerForKey(pending.playerKey) || pending.player
    if (force || MediaModel.trackChanged(pending.before, player) || pending.attempts >= 10) {
      pendingTrackOsd = null
      trackOsdTimer.stop()
      root.showOsd(pending.actionLabel, pending.iconName, player)
      return
    }

    pending.attempts = pending.attempts + 1
    pendingTrackOsd = pending
    trackOsdTimer.restart()
  }

  function selectPlayer(key) {
    var player = playerForKey(key)
    if (!player || !hasMetadata(player)) return false
    preferredPlayerKey = playerKey(player)
    return true
  }

  function playPlayer(player) {
    if (!player) return false
    if (player.canPlay) {
      player.play()
      return true
    }
    return false
  }

  function pausePlayer(player) {
    if (!player) return false
    if (player.canPause) {
      player.pause()
      return true
    }
    if (player.canTogglePlaying && player.isPlaying) {
      player.togglePlaying()
      return true
    }
    return false
  }
  function handoffToPlayer(player) {
    if (!player) return false

    var targetReady = player.isPlaying || playPlayer(player)
    if (!targetReady) return false

    var targetKey = playerKey(player)
    for (var i = 0; i < sourcePlayers.length; i++) {
      var other = sourcePlayers[i]
      if (playerKey(other) !== targetKey && other.isPlaying) pausePlayer(other)
    }

    preferredPlayerKey = targetKey
    return true
  }

  function switchSource(delta, transferPlayback, showFeedback) {
    var list = sourceCyclePlayers
    if (!list || list.length === 0) return false

    var activeKey = playerKey(activePlayer)
    var index = 0
    for (var i = 0; i < list.length; i++) {
      if (playerKey(list[i]) === activeKey) {
        index = i
        break
      }
    }

    index = (index + delta + list.length) % list.length
    var current = activePlayer
    var next = list[index]
    var currentWasPlaying = current && current.isPlaying
    var currentKey = playerKey(current)
    var nextKey = playerKey(next)

    preferredPlayerKey = nextKey

    if (transferPlayback && currentWasPlaying && next && nextKey !== currentKey) {
      var nextWasPlaying = next.isPlaying
      var nextStarted = nextWasPlaying || playPlayer(next)
      if (nextStarted) pausePlayer(current)
    }

    if (showFeedback !== false) Qt.callLater(function() {
      root.showOsd("Source", "media-source", next)
    })

    return true
  }

  function playerForAction(action, targetKey) {
    var targeted = playerForKey(targetKey)
    if (targeted) return targeted

    if (action === "pause" || action === "playPause") {
      var oldest = oldestPlayingPlayer(true) || oldestPlayingPlayer(false)
      if (oldest) return oldest
    }

    if (canHandleAction(activePlayer, action)) return activePlayer

    var list = sourcePlayers
    for (var i = 0; i < list.length; i++) {
      if (canHandleAction(list[i], action)) return list[i]
    }

    return activePlayer
  }

  function runAction(action, showFeedback, targetKey) {
    var player = playerForAction(action, targetKey)
    var key = playerKey(player)
    var actionLabel = "Play/pause"
    var iconName = "media"
    var beforeTrackSignature = trackSignature(player)
    var handled = false

    if (action === "next") {
      actionLabel = "Next"
      iconName = "media-next"
      if (player && player.canGoNext) {
        player.next()
        handled = true
      }
    } else if (action === "previous") {
      actionLabel = "Previous"
      iconName = "media-previous"
      if (player && player.canGoPrevious) {
        player.previous()
        handled = true
      }
    } else if (action === "play") {
      actionLabel = "Play"
      iconName = "media-play"
      if (player && player.canPlay) {
        player.play()
        handled = true
      } else if (player && player.canTogglePlaying && !player.isPlaying) {
        player.togglePlaying()
        handled = true
      }
    } else if (action === "pause") {
      actionLabel = "Pause"
      iconName = "media-pause"
      if (player && player.canPause) {
        player.pause()
        handled = true
      } else if (player && player.canTogglePlaying && player.isPlaying) {
        player.togglePlaying()
        handled = true
      }
    } else if (action === "playPause") {
      actionLabel = player && player.isPlaying ? "Pause" : "Play"
      iconName = player && player.isPlaying ? "media-pause" : "media-play"
      if (player && player.isPlaying && player.canPause) {
        player.pause()
        handled = true
      } else if (player && !player.isPlaying && player.canPlay) {
        player.play()
        handled = true
      } else if (player && player.canTogglePlaying) {
        player.togglePlaying()
        handled = true
      }
    }

    if (handled && key) preferredPlayerKey = key
    if (showFeedback !== false)
      scheduleOsd(actionLabel, iconName, player, handled && (action === "next" || action === "previous"), beforeTrackSignature)
    return handled
  }

  // Recompute play-order reactively instead of polling every 500ms.
  // syncPlayingOrder only depends on the set of players and each player's
  // isPlaying state: onPlayersChanged covers players appearing/disappearing,
  // and the Instantiator wires isPlayingChanged for each live player.
  Component.onCompleted: {
    root.syncPlayingOrder()
    root.refreshMediaWindows()
    root.refreshProcessTree()
  }
  onPlayersChanged: {
    root.syncPlayingOrder()
    root.refreshMediaWindows()
    root.refreshProcessTree()
  }
  onPlaybackStreamsChanged: root.refreshProcessTree()

  Instantiator {
    model: root.players
    delegate: Connections {
      required property var modelData
      target: modelData
      function onIsPlayingChanged() { root.syncPlayingOrder() }
      function onTrackTitleChanged() { root.refreshMediaWindows() }
      function onIdentityChanged() { root.refreshMediaWindows() }
    }
  }

  Process {
    id: mediaWindowProcess
    command: ["hyprctl", "clients", "-j"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyMediaWindows(text)
    }
    onExited: function(exitCode) {
      if (root.mediaWindowRefreshPending) Qt.callLater(root.refreshMediaWindows)
    }
  }

  Process {
    id: focusWindowProcess
    running: false
  }
  Process {
    id: closeWindowProcess
    running: false
  }
  Process {
    id: toggleWorkspaceProcess
    running: false
  }
  Process {
    id: processTreeProcess
    command: ["ps", "-eo", "pid=,ppid="]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyProcessTree(text)
    }
    onExited: function(exitCode) {
      if (root.processTreeRefreshPending) Qt.callLater(root.refreshProcessTree)
    }
  }



  Timer {
    id: trackOsdTimer
    interval: 120
    repeat: false
    onTriggered: root.flushPendingTrackOsd(false)
  }

  PwObjectTracker { objects: root.playbackStreams }

  function statusJson() {
    var p = activePlayer
    return JSON.stringify({
      hasPlayer: p !== null,
      hasMedia: root.hasMedia,
      playing: p ? !!p.isPlaying : false,
      identity: p ? (p.identity || "") : "",
      desktopEntry: p ? (p.desktopEntry || "") : "",
      title: p ? (p.trackTitle || "") : "",
      artist: p ? (p.trackArtist || "") : "",
      album: p && p.trackAlbum ? p.trackAlbum : "",
      artUrl: p && p.trackArtUrl ? p.trackArtUrl : "",
      canGoNext: p ? !!p.canGoNext : false,
      canGoPrevious: p ? !!p.canGoPrevious : false,
      canTogglePlaying: p ? !!p.canTogglePlaying : false
    })
  }
  function playersJson() {
    var entries = []
    for (var i = 0; i < sourcePlayers.length; i++) {
      var p = sourcePlayers[i]
      entries.push({
        key: playerKey(p),
        group: playerGroup(p),
        playing: !!p.isPlaying,
        identity: p.identity || p.desktopEntry || "",
        title: p.trackTitle || "",
        artist: p.trackArtist || "",
        canPlay: !!p.canPlay,
        canPause: !!p.canPause,
        volume: playerAudioAvailable(p) ? Math.round(playerAudioVolume(p) * 100) : -1,
        volumeSupported: playerAudioAvailable(p),
        muted: playerAudioMuted(p),
        canClose: canClosePlayer(p),
        canGoNext: !!p.canGoNext,
        canGoPrevious: !!p.canGoPrevious
      })
    }
    return JSON.stringify(entries)
  }


  IpcHandler {
    target: "media"

    function status(): string {
      return root.statusJson()
    }

    function playPause(): string {
      return root.runAction("playPause", true) ? "ok" : "unhandled"
    }

    function next(): string {
      return root.runAction("next", true) ? "ok" : "unhandled"
    }

    function previous(): string {
      return root.runAction("previous", true) ? "ok" : "unhandled"
    }

    function play(): string {
      return root.runAction("play", true) ? "ok" : "unhandled"
    }

    function pause(): string {
      return root.runAction("pause", true) ? "ok" : "unhandled"
    }

    function sourceNext(): string {
      return root.switchSource(1, false, true) ? "ok" : "unhandled"
    }

    function sourcePrevious(): string {
      return root.switchSource(-1, false, true) ? "ok" : "unhandled"
    }

    function sourceSwitch(): string {
      return root.switchSource(1, true, true) ? "ok" : "unhandled"
    }

    function sourceSwitchPrevious(): string {
      return root.switchSource(-1, true, true) ? "ok" : "unhandled"
    }

    function sources(): string {
      return root.playersJson()
    }

    function control(key: string, action: string): string {
      return root.runAction(action, false, key) ? "ok" : "unhandled"
    }

    function handoff(key: string): string {
      return root.handoffToPlayer(root.playerForKey(key)) ? "ok" : "unhandled"
    }

    function show(key: string): string {
      return root.focusPlayerWindow(root.playerForKey(key)) ? "ok" : "unhandled"
    }

    function adjustVolume(key: string, delta: string): string {
      return root.adjustPlayerVolume(root.playerForKey(key), Number(delta))
        ? "ok" : "unhandled"
    }

    function toggleMute(key: string): string {
      return root.togglePlayerMute(root.playerForKey(key)) ? "ok" : "unhandled"
    }

    function close(key: string): string {
      return root.closePlayerWindow(root.playerForKey(key)) ? "ok" : "unhandled"
    }

    function ping(): string {
      return "ok"
    }
  }
}
