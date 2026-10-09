import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons

import qs.Commons as Commons
// One file in the download list, and the thing you actually drag.
//
// The drag is the point of this widget, so a note on how it is wired.
// Drag.dragType: Drag.Automatic is what makes this a real Wayland drag
// (wl_data_device.start_drag) rather than an in-scene one. text/uri-list is
// the format file managers, browsers and chat apps read; text/plain is there
// for fields that only take text. The URL comes from FolderListModel, which
// percent-encodes it, so names with spaces survive.
//
// Detect the gesture without moving a target. ListView exclusively owns the
// delegate coordinates; the compositor moves only the captured drag image.
Item {
  id: row

  // The DownloadsStore, for formatting helpers and shared drag state.
  property var store: null
  // { name, url, path, size, isDir, modified, fresh }
  property var file: ({})

  readonly property bool dragging: store !== null && !!file && store.draggingUrl === file.url
  readonly property bool fresh: !!(file && file.fresh === true)

  implicitHeight: Style.space(34)
  height: implicitHeight

  Drag.active: fileDrag.active
  Drag.dragType: Drag.Automatic
  Drag.supportedActions: Qt.CopyAction
  Drag.mimeData: ({
    "text/uri-list": String(row.file.url || "") + "\r\n",
    "text/plain": String(row.file.url || "")
  })
  Drag.onDragStarted: if (row.store) row.store.draggingUrl = String(row.file.url || "")
  // A drag is the end of the errand, so the panel goes with it. Left open,
  // it keeps its full-screen click catcher, and the next click in the app
  // you just dropped into (Send, say) only dismisses the panel and never
  // reaches the app. This closes on every finished drag rather than only on
  // a drop that landed: on Wayland the action handed back here is
  // IgnoreAction even for a drop that foot accepted and pasted, so it says
  // nothing about where the file went. A drag let go over nothing costs one
  // click to reopen, which is cheaper than a swallowed click every time.
  Drag.onDragFinished: {
    if (!row.store) return
    row.store.draggingUrl = ""
    row.store.open = false
  }

  Rectangle {
    anchors.fill: parent
    radius: Style.space(4)
    color: row.dragging
      ? Util.alpha(Commons.Color.accent, 0.22)
      : (mouse.containsMouse ? Util.alpha(Commons.Color.foreground, 0.10) : "transparent")
    border.width: row.dragging ? Style.spacing.hairline : 0
    border.color: Commons.Color.accent
  }

  // A RowLayout rather than a Row: the name has to take whatever is left
  // after the icons and the age, and only a layout knows that width. With a
  // plain Row the name and the age both sized themselves from the full width
  // and printed straight over each other.
  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: Style.space(8)
    spacing: Style.space(8)

    // Marks a file that arrived within the fresh window: the same signal the
    // bar badge counts, so the row you came for is the one that stands out.
    Rectangle {
      Layout.alignment: Qt.AlignVCenter
      implicitWidth: Style.space(5)
      implicitHeight: Style.space(5)
      radius: implicitWidth / 2
      color: row.fresh ? Commons.Color.accent : "transparent"
    }

    Text {
      Layout.alignment: Qt.AlignVCenter
      text: (row.store && row.store.iconFor && row.file) ? String(row.store.iconFor(row.file.name, row.file.isDir) || "") : ""
      textFormat: Text.PlainText
      font.family: String((row.store && row.store.fontFamily) || Style.font.family || "")
      font.pixelSize: Style.font.icon
      renderType: Text.NativeRendering
      color: row.fresh ? Commons.Color.accent : Commons.Color.muted
    }

    // The filename is chosen by whoever made the file, so PlainText, always.
    // preferredWidth 0 alongside fillWidth: otherwise a long filename sets
    // the row's minimum width and pushes the age and size out of the window.
    Text {
      Layout.fillWidth: true
      Layout.preferredWidth: 0
      Layout.alignment: Qt.AlignVCenter
      text: row.file ? String(row.file.name || "") : ""
      textFormat: Text.PlainText
      elide: Text.ElideMiddle
      font.family: String((row.store && row.store.fontFamily) || Style.font.family || "")
      font.pixelSize: Style.font.body
      renderType: Text.NativeRendering
      color: Commons.Color.foreground
    }

    Text {
      Layout.alignment: Qt.AlignVCenter
      text: (row.store && row.store.formatAge && row.file)
        ? String(row.store.formatAge(row.file.modified) || "")
          + (!row.file.isDir && row.file.size > 0 ? "  ·  " + String(row.store.formatSize(row.file.size) || "") : "")
        : ""
      textFormat: Text.PlainText
      font.family: String((row.store && row.store.fontFamily) || Style.font.family || "")
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
      color: Commons.Color.muted
    }
  }

  DragHandler {
    id: fileDrag
    target: null
    acceptedButtons: Qt.LeftButton
    dragThreshold: Style.space(6)
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: fileDrag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    // Grab a picture of the row on press, so the drag carries something you
    // can recognise. Asynchronous, but press comes well before the drag
    // threshold; if it is not ready the drag simply has no image.
    onPressed: {
      row.grabToImage(function(result) {
        if (result) row.Drag.imageSource = result.url
      })
    }

    // Opening the file is the other thing you might want from a row, and a
    // double click cannot be confused with the start of a drag.
    //
    // Quickshell.execDetached with an argument array, never
    // Util.execDetached: that helper takes a string and runs it through
    // `bash -lc`, and a filename is picked by whoever made the file. One
    // named `; rm -rf ~` would then be a command. The array form execs
    // directly, and the leading-slash check keeps a name that starts with a
    // dash from being read as an option.
    onDoubleClicked: {
      var target = String(row.file.path || "")
      if (target.length > 1 && target.charAt(0) === "/")
        Quickshell.execDetached(["xdg-open", target])
    }
  }
}
