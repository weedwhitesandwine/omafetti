import QtQuick
import qs.Commons
import qs.Ui as Ui
import "."

// Optional bar icon. It does one thing: open Omafetti's settings. Throwing
// confetti is the hotkey's job — an icon you might click by accident is the
// wrong place for it.
// (qs.Ui is imported under a namespace because this file is itself named
// BarWidget.qml — a bare `BarWidget` would resolve to the file itself.)
Ui.BarWidget {
  id: root
  moduleName: "io.github.weedwhitesandwine.omafetti"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Shape contract for shell summon/toggle routing — forward to the overlay.
  readonly property bool opened: OmafettiState.overlay ? OmafettiState.overlay.settingsOpen === true : false
  function open() { if (OmafettiState.overlay) OmafettiState.overlay.openSettings() }
  function close() { if (OmafettiState.overlay) OmafettiState.overlay.closeSettings() }

  Ui.BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // A font glyph, not the emoji: emoji render as colour bitmaps and ignore
    // the requested colour, so they sit in the bar in full colour while every
    // icon around them follows the theme. This one is drawn in the theme's
    // foreground like its neighbours.
    // U+F1056, written as a surrogate pair: a \u escape takes exactly four hex
    // digits, so "\uF1056" is the chevron U+F105 followed by a literal "6".
    text: "\uDB84\uDC56"
    tooltipText: "Omafetti settings"
    onPressed: function(b) {
      if (!OmafettiState.overlay) return
      if (OmafettiState.overlay.settingsOpen) OmafettiState.overlay.closeSettings()
      else OmafettiState.overlay.openSettings()
    }
  }
}
