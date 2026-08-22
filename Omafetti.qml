import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

import qs.Commons
import qs.Ui
import "."

// Omafetti — a useless plugin that blows confetti on your screen.
//
// Two surfaces, deliberately different. The confetti itself is a click-through
// layer with no keyboard focus, one per monitor, so a burst never interrupts
// what you were doing: you can keep typing straight through it. The settings
// card is an ordinary focused panel, opened from the bar icon, where the
// hotkey, the colours and the style of throw are chosen.
Item {
  id: root

  property string home: Quickshell.env("HOME")

  readonly property string pluginDir: {
    var u = String(Qt.resolvedUrl("."))
    return decodeURIComponent(u.replace(/^file:\/\//, "")).replace(/\/$/, "")
  }

  // ------------------------------------------------------------------ theme
  property color foreground: Color.menu.text
  property color background: Color.menu.background
  property color border: Color.menu.border
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  readonly property int cornerRadius: Style.cornerRadius
  readonly property int labelWidth: Style.space(170)
  property string fontFamily: Style.font.menuFamily

  // --------------------------------------------------------------- settings
  // Every choice below is the user's, made in the settings card. Applying is
  // the ONLY time Omafetti writes anything outside its own state directory —
  // its marked hotkey block in bindings.lua, and its own bar entry — both via
  // omafetti-ctl.sh, and never on its own initiative.
  readonly property string settingsFile: root.home + "/.local/state/omafetti/settings.json"
  property var osettings: ({
    configured: false, palette: "classic", style: "corners",
    density: "normal", shortcut: "", barIcon: true, barSection: "right"
  })

  property string draftPalette: "classic"
  property string draftStyle: "corners"
  property string draftDensity: "normal"
  property string draftShortcut: ""
  property bool draftBarIcon: true
  property string draftBarSection: "right"
  property bool capturing: false
  property string captureNote: ""

  // "greeter" on first run, "settings" thereafter.
  property string view: "settings"
  property bool settingsOpen: false

  // ---------------------------------------------------------------- palettes
  // Classic party confetti: the colours a paper cannon actually comes loaded
  // with, independent of whatever the desktop happens to look like.
  readonly property var classicPalette: [
    "#ff3b30", "#ff2d55", "#ff9500", "#ffcc00", "#34c759",
    "#00c7be", "#0a84ff", "#5856d6", "#af52de", "#ffffff"
  ]

  // Theme colours: the named hues of the active Omarchy theme, read from the
  // theme's own colors.toml so a theme swap restyles the confetti with it.
  property var themePalette: []

  function paletteFor(mode) {
    if (mode === "theme" && root.themePalette.length >= 3) return root.themePalette
    return root.classicPalette
  }

  function densityCount(d) {
    if (d === "light") return 110
    if (d === "heavy") return 420
    return 220
  }

  // Live values used by the next burst — the drafts while the settings card is
  // open, so the preview button shows the choice being made, not the saved one.
  readonly property var activePalette: root.paletteFor(root.settingsOpen ? root.draftPalette : root.osettings.palette)
  readonly property string activeStyle: root.settingsOpen ? root.draftStyle : (root.osettings.style || "corners")
  readonly property int activeCount: root.densityCount(root.settingsOpen ? root.draftDensity : root.osettings.density)

  // --------------------------------------------------------------- lifecycle
  property bool flying: false
  property int busyLayers: 0

  // The shell reads this to decide whether a summon should open or hide us.
  readonly property bool opened: root.settingsOpen || root.flying

  signal throwNow()

  function throwConfetti() {
    root.flying = true
    // The panels need one layout pass before their layers know how big the
    // screen is; firing into a zero-sized layer would throw nothing.
    launchDelay.restart()
  }

  function openSettings() {
    root.syncDrafts()
    root.view = root.osettings.configured === true ? "settings" : "greeter"
    root.settingsOpen = true
  }

  function closeSettings() {
    root.settingsOpen = false
    root.capturing = false
  }

  function open(payloadJson) {
    var payload = {}
    try { if (payloadJson) payload = JSON.parse(payloadJson) || {} } catch (e) {}

    if (payload.view === "settings" || root.osettings.configured !== true) {
      root.openSettings()
      return
    }
    root.throwConfetti()
  }

  function close() {
    root.closeSettings()
    root.flying = false
  }

  Timer {
    id: launchDelay
    interval: 32
    onTriggered: root.throwNow()
  }

  Component.onCompleted: OmafettiState.overlay = root

  // ------------------------------------------------------------ persistence
  function saveSettings() {
    Quickshell.execDetached(["bash", "-c",
      'mkdir -p "$(dirname "$2")" && printf "%s\\n" "$1" > "$2"', "--",
      JSON.stringify(root.osettings), root.settingsFile])
  }

  function syncDrafts() {
    root.draftPalette = root.osettings.palette || "classic"
    root.draftStyle = root.osettings.style || "corners"
    root.draftDensity = root.osettings.density || "normal"
    root.draftShortcut = root.osettings.shortcut || ""
    root.draftBarIcon = root.osettings.barIcon !== false
    root.draftBarSection = root.osettings.barSection || "right"
    root.capturing = false
    root.captureNote = ""
  }

  function applyDrafts() {
    var s = {
      configured: true,
      palette: root.draftPalette,
      style: root.draftStyle,
      density: root.draftDensity,
      shortcut: root.draftShortcut,
      barIcon: root.draftBarIcon,
      barSection: root.draftBarSection
    }
    root.osettings = s
    root.saveSettings()
    Quickshell.execDetached(["bash", root.pluginDir + "/omafetti-ctl.sh", "bar",
                             s.barIcon ? "on" : "off", s.barSection])
    if (s.shortcut) Quickshell.execDetached(["bash", root.pluginDir + "/omafetti-ctl.sh", "bind", s.shortcut])
    else Quickshell.execDetached(["bash", root.pluginDir + "/omafetti-ctl.sh", "unbind"])
    root.closeSettings()
  }

  function captureKey(event) {
    if (event.key === Qt.Key_Escape) { root.capturing = false; root.captureNote = ""; return }
    var mods = []
    if (event.modifiers & Qt.MetaModifier) mods.push("SUPER")
    if (event.modifiers & Qt.ControlModifier) mods.push("CTRL")
    if (event.modifiers & Qt.AltModifier) mods.push("ALT")
    if (event.modifiers & Qt.ShiftModifier) mods.push("SHIFT")
    var name = ""
    if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z) name = String.fromCharCode(65 + (event.key - Qt.Key_A))
    else if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) name = String.fromCharCode(48 + (event.key - Qt.Key_0))
    else if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F12) name = "F" + (event.key - Qt.Key_F1 + 1)
    if (name === "") return
    if (mods.length === 0) { root.captureNote = "Add a modifier — SUPER, CTRL or ALT"; return }
    root.draftShortcut = mods.join(" + ") + " + " + name
    root.captureNote = ""
    root.capturing = false
  }

  FileView {
    path: root.settingsFile
    printErrors: false
    watchChanges: true
    onLoaded: {
      try {
        var s = JSON.parse(text())
        if (s && typeof s === "object") root.osettings = s
      } catch (e) {}
    }
    onFileChanged: reload()
  }

  // The active theme's palette. Read-only, and re-read when the theme changes.
  FileView {
    path: root.home + "/.local/state/omarchy/current/theme/colors.toml"
    printErrors: false
    watchChanges: true
    onLoaded: {
      var wanted = ["red", "orange", "yellow", "green", "cyan", "blue", "magenta",
                    "bright_red", "bright_yellow", "bright_green", "bright_cyan",
                    "bright_blue", "bright_magenta", "accent"]
      var found = []
      var lines = String(text()).split("\n")
      for (var i = 0; i < lines.length; i++) {
        var m = lines[i].match(/^\s*([a-z_]+)\s*=\s*"(#[0-9a-fA-F]{6})"/)
        if (!m) continue
        if (wanted.indexOf(m[1]) < 0) continue
        if (found.indexOf(m[2]) < 0) found.push(m[2])
      }
      root.themePalette = found
    }
    onFileChanged: reload()
  }

  // ------------------------------------------------------------- components
  component SettingLabel: Text {
    width: root.labelWidth
    anchors.verticalCenter: parent.verticalCenter
    color: root.foreground
    opacity: 0.75
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
  }

  component SettingPill: Rectangle {
    id: pill
    property string label
    property bool active: false
    signal picked()
    width: pillLabel.width + Style.spacing.lg * 2
    height: Style.space(32)
    radius: root.cornerRadius
    color: pill.active ? root.selectedBackground : "transparent"
    border.color: pill.active ? root.foreground : root.border
    border.width: pill.active ? 1 : 0

    Text {
      id: pillLabel
      anchors.centerIn: parent
      text: pill.label
      color: pill.active ? root.selectedText : root.foreground
      opacity: pill.active ? 1 : 0.55
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: pill.picked()
    }
  }

  // ------------------------------------------------------ the confetti layer
  // One per monitor. No keyboard focus and an empty input region, so the paper
  // falls in front of everything without catching a single click.
  Variants {
    model: root.flying ? Quickshell.screens : []

    delegate: Component {
      PanelWindow {
        id: confettiPanel
        required property var modelData

        screen: modelData
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        WlrLayershell.namespace: "omafetti"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}

        ConfettiLayer {
          id: layer
          anchors.fill: parent
          palette: root.activePalette
          style: root.activeStyle
          pieceCount: root.activeCount

          onFinished: {
            root.busyLayers = Math.max(0, root.busyLayers - 1)
            if (root.busyLayers === 0) root.flying = false
          }
        }

        Connections {
          target: root
          function onThrowNow() {
            root.busyLayers++
            layer.fire()
          }
        }
      }
    }
  }

  // A burst that somehow never lands must not leave a surface up forever.
  Timer {
    interval: 12000
    running: root.flying
    onTriggered: { root.busyLayers = 0; root.flying = false }
  }

  // ------------------------------------------------------- the settings card
  PanelWindow {
    id: settingsPanel
    visible: root.settingsOpen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omafetti-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: root.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.closeSettings() }

    BorderSurface {
      id: card
      width: Math.min(Style.space(660), settingsPanel.width - Style.gapsOut * 2)
      height: Math.min(form.implicitHeight + card.contentTopInset + card.contentBottomInset,
                       settingsPanel.height - Style.gapsOut * 2)
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      radius: root.cornerRadius
      padding: Style.space(24)

      MouseArea { anchors.fill: parent; onClicked: {} }

      // BorderSurface exposes its insets but does not apply them — content
      // has to inset itself or it renders under the border.
      Item {
        id: keyCatcher
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.capturing) {
            root.captureKey(event)
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Escape) root.closeSettings()
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.applyDrafts()
          else if (event.key === Qt.Key_Space) root.throwConfetti()
          event.accepted = true
        }

        Column {
          id: form
          width: parent.width
          spacing: Style.spacing.xl

          Text {
            width: parent.width
            text: root.view === "greeter" ? "🎉 welcome to Omafetti" : "Omafetti settings"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            visible: root.view === "greeter"
            text: "A useless plugin that blows confetti on your screen. Give it a hotkey and it throws paper at nothing in particular. Everything here can be changed later from the bar icon."
            color: root.foreground
            opacity: 0.75
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Row {
            width: parent.width
            spacing: Style.spacing.md

            SettingLabel { text: "Hotkey" }

            Rectangle {
              width: Style.space(210)
              height: Style.space(32)
              radius: root.cornerRadius
              color: "transparent"
              border.color: root.border
              border.width: 1

              Text {
                anchors.centerIn: parent
                text: root.capturing ? "press your keys…"
                  : (root.draftShortcut !== "" ? root.draftShortcut : "none set")
                color: root.foreground
                opacity: root.capturing || root.draftShortcut === "" ? 0.6 : 1
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }

            SettingPill {
              label: root.capturing ? "cancel" : "record"
              active: true
              onPicked: { root.capturing = !root.capturing; root.captureNote = "" }
            }
          }

          Text {
            width: parent.width
            visible: root.captureNote !== "" || root.capturing
            text: root.captureNote !== "" ? root.captureNote
              : "Pick a combination nothing else uses — already-taken keys will trigger their old action instead."
            wrapMode: Text.WordWrap
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Row {
            spacing: Style.spacing.md
            SettingLabel { text: "Colours" }
            Row {
              spacing: Style.space(4)
              SettingPill {
                label: "classic confetti"
                active: root.draftPalette === "classic"
                onPicked: root.draftPalette = "classic"
              }
              SettingPill {
                label: "theme colours"
                active: root.draftPalette === "theme"
                onPicked: root.draftPalette = "theme"
              }
            }
          }

          // The palette being chosen, shown as the colours it will actually use.
          Row {
            x: root.labelWidth + Style.spacing.md
            spacing: Style.space(4)
            Repeater {
              model: root.paletteFor(root.draftPalette)
              Rectangle {
                required property var modelData
                width: Style.space(18); height: Style.space(18)
                radius: width / 2
                color: modelData
              }
            }
          }

          Row {
            spacing: Style.spacing.md
            SettingLabel { text: "Throw" }
            Row {
              spacing: Style.space(4)
              SettingPill {
                label: "from the corners"
                active: root.draftStyle === "corners"
                onPicked: root.draftStyle = "corners"
              }
              SettingPill {
                label: "cannon"
                active: root.draftStyle === "cannon"
                onPicked: root.draftStyle = "cannon"
              }
              SettingPill {
                label: "rain"
                active: root.draftStyle === "rain"
                onPicked: root.draftStyle = "rain"
              }
            }
          }

          Row {
            spacing: Style.spacing.md
            SettingLabel { text: "How much" }
            Row {
              spacing: Style.space(4)
              SettingPill {
                label: "a handful"
                active: root.draftDensity === "light"
                onPicked: root.draftDensity = "light"
              }
              SettingPill {
                label: "normal"
                active: root.draftDensity === "normal"
                onPicked: root.draftDensity = "normal"
              }
              SettingPill {
                label: "silly"
                active: root.draftDensity === "heavy"
                onPicked: root.draftDensity = "heavy"
              }
            }
          }

          Row {
            spacing: Style.spacing.md
            SettingLabel { text: "Bar icon" }
            Row {
              spacing: Style.space(4)
              SettingPill {
                label: "show"
                active: root.draftBarIcon
                onPicked: root.draftBarIcon = true
              }
              SettingPill {
                label: "hide"
                active: !root.draftBarIcon
                onPicked: root.draftBarIcon = false
              }
            }
          }

          Row {
            spacing: Style.spacing.md
            visible: root.draftBarIcon
            SettingLabel { text: "Bar position" }
            Row {
              spacing: Style.space(4)
              SettingPill {
                label: "left"
                active: root.draftBarSection === "left"
                onPicked: root.draftBarSection = "left"
              }
              SettingPill {
                label: "center"
                active: root.draftBarSection === "center"
                onPicked: root.draftBarSection = "center"
              }
              SettingPill {
                label: "right"
                active: root.draftBarSection === "right"
                onPicked: root.draftBarSection = "right"
              }
            }
          }

          Text {
            width: parent.width
            visible: !root.draftBarIcon && root.draftShortcut === ""
            wrapMode: Text.WordWrap
            text: "⚠ With no hotkey and no bar icon there is no way left to reach these settings except from a terminal: omarchy-shell shell summon io.github.weedwhitesandwine.omafetti '{\"view\":\"settings\"}'"
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Applying saves these choices, updates Omafetti's own marked hotkey block in bindings.lua, and adds or removes its bar icon. Nothing else is touched."
            color: root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Row {
            spacing: Style.spacing.md

            SettingPill {
              label: "🎉 throw some now"
              active: true
              onPicked: root.throwConfetti()
            }

            SettingPill {
              label: root.view === "greeter" ? "Start Omafetti" : "Apply"
              active: true
              onPicked: root.applyDrafts()
            }

            SettingPill {
              label: "Cancel"
              onPicked: root.closeSettings()
            }
          }
        }
      }
    }
  }
}
