import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Downloads: what just landed in the download folder, one click from the bar.
//
// The button carries a badge with the number of files that arrived within the
// last few minutes, so a finished download is visible without opening
// anything. Clicking opens a window whose rows are drag handles, so a file
// goes straight into the upload field or chat window that needs it.
//
// Everything that has state - the folder, the list, the window - lives in
// DownloadsStore, a singleton. A bar widget is instantiated once per monitor,
// so a window declared here would exist twice on a two-monitor setup. This
// file is the view: a button, a badge, and a way to reach the store.
//
// Why the list is a FloatingWindow and not the usual KeyboardPanel: a drag
// has to start from a real toplevel window. Measured on Hyprland with
// Quickshell 0.3 - a drag begun on a layer-shell surface is accepted by the
// compositor, but the drag focus stays pinned to the source surface. The
// receiving window never gets `wl_data_device.enter`, so nothing is ever
// dropped, and the panel stops responding to the mouse afterwards. The same
// QML in a normal window drops correctly on the first try.
Panel {
  id: root

  moduleName: "jankeesvw.downloads"
  ipcTarget: "jankeesvw.downloads"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int freshCount: DownloadsStore.freshCount
  readonly property bool hasFresh: freshCount > 0

  // Width of the badge and of the whole icon+badge row. Computed here rather
  // than inside iconComponent: that Component has its own scope, and ids
  // declared in it are invisible out here.
  readonly property int badgeWidth: freshCount > 0
    ? Math.max(Style.space(12), String(freshCount).length * Style.space(6) + Style.space(8))
    : 0
  readonly property int barContentWidth:
    Style.bar.iconFont + badgeWidth + (badgeWidth > 0 ? Style.space(5) : 0)

  // Panel is a bare Item with no size of its own, so the bar would hand this
  // widget zero width. Set it from the computed content width, never from a
  // child that fills this item: that is a loop where nothing decides the size,
  // the content still paints, and the button quietly stops being clickable.
  readonly property int barSlot: barContentWidth + Style.space(10)
  readonly property real openPanelIndicatorWidth: barContentWidth
  readonly property real openPanelIndicatorHeight: barContentWidth
  implicitWidth: bar && bar.vertical ? (bar ? bar.barSize : Style.bar.sizeHorizontal) : barSlot
  implicitHeight: bar && bar.vertical ? barSlot : (bar ? bar.barSize : Style.bar.sizeHorizontal)

  // Settings live per bar entry in shell.json; the store is shared. Every
  // widget hands over the same values, so writing them more than once is
  // harmless.
  //
  // Applied on settingsChanged as well as on completion, and that is not
  // belt-and-braces: the host assigns `settings` after constructing the
  // widget, so a Component.onCompleted that reads them runs while the object
  // is still empty. Doing it only there meant `folder` and `freshMinutes`
  // were silently ignored.
  function applySettings() {
    var folder = String(root.setting("folder", ""))
    DownloadsStore.configure(root.setting("freshMinutes", 5),
                             folder !== "" ? Util.fileUrl(folder) : undefined)
    DownloadsStore.fontFamily = root.fontFamily
  }

  onSettingsChanged: root.applySettings()
  Component.onCompleted: root.applySettings()

  // The bar button and the window mirror each other, in both directions:
  // `opened` follows a summon over IPC, and the store follows a click or the
  // window's own close button. Both sides check before assigning, so the two
  // handlers cannot bounce a change back and forth.
  //
  // Only the widget that actually opened the store places the window. The
  // other monitors' copies also flip `opened` (via Connections below) so
  // their buttons highlight; they must not steal the screen afterwards.
  function barScreen() {
    var window = root.QsWindow ? root.QsWindow.window : null
    return window ? window.screen : null
  }

  onOpenedChanged: {
    if (root.opened) {
      if (!DownloadsStore.open)
        DownloadsStore.showOn(root.barScreen())
    } else if (DownloadsStore.open) {
      DownloadsStore.hide()
    }
  }

  Connections {
    target: DownloadsStore
    function onOpenChanged() {
      if (DownloadsStore.open && !root.opened) root.open()
      else if (!DownloadsStore.open && root.opened) root.close()
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: root.barSlot
    // The icon component is loaded into a square canvas of opticalSize, meant
    // for a single glyph. Widen it too, or the icon falls outside it and only
    // the badge survives.
    opticalSize: root.barContentWidth
    tooltipText: ""

    iconComponent: Component {
      Item {
        Row {
          anchors.centerIn: parent
          spacing: Style.space(5)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: DownloadsStore.iconDownload
            textFormat: Text.PlainText
            font.family: root.fontFamily
            font.pixelSize: Style.bar.iconFont
            renderType: Text.NativeRendering
            color: (root.opened || root.hasFresh) ? root.accent : root.foreground
          }

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.freshCount > 0
            height: Style.space(12)
            width: root.badgeWidth
            radius: height / 2
            color: root.accent

            Text {
              anchors.centerIn: parent
              text: root.freshCount
              textFormat: Text.PlainText
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              renderType: Text.NativeRendering
              color: Color.background
            }
          }
        }
      }
    }

    onPressed: function(b) {
      if (b === Qt.RightButton) DownloadsStore.openFolder()
      else root.toggle()
    }
  }
}
