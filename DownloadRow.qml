import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons

// One file in the download list, and the thing you actually drag.
//
// The drag is the point of this widget, so a note on how it is wired.
// Drag.dragType: Drag.Automatic is what makes this a real Wayland drag
// (wl_data_device.start_drag) rather than an in-scene one. text/uri-list is
// the format file managers, browsers and chat apps read; text/plain is there
// for fields that only take text. The URL comes from FolderListModel, which
// percent-encodes it, so names with spaces survive.
//
// The Drag attached property and the MouseArea's drag.target sit on the same
// item, `dragHandle`, and that pairing is deliberate:
//
//   - drag.target has to be *something*, and whatever it is gets moved. Point
//     it at this row and the row slides out from under the cursor, because a
//     ListView delegate's x/y belong to the view.
//   - splitting them - Drag on the row, drag.target on a proxy - makes QML
//     report a binding loop on `active` and the drag never becomes reliable.
//
// So a one-pixel handle carries both, and the drag image comes from
// grabToImage() on the row: you drag a picture of the row without the row
// itself going anywhere.
Item {
  id: row

  // The DownloadsStore, for formatting helpers and shared drag state.
  property var store: null
  // { name, url, path, size, modified, fresh }
  property var file: ({})

  readonly property bool dragging: !!(store && file && store.draggingUrl === file.url)
  readonly property bool fresh: !!(file && file.fresh === true)

  implicitHeight: Style.space(34)
  height: implicitHeight

  // Carries both the drag payload and the movement. One pixel, invisible;
  // moving it moves nothing anyone can see.
  // Note for anyone testing this on an empty workspace: the compositor does
  // not begin a drag when there is no other window that could receive it.
  // Measured on Hyprland - with a window present the drag starts every time,
  // on a bare workspace it never does. That is compositor behaviour, not a
  // bug here, but it will look like the drag is broken.
  //
  // Drag and drag.target both live on this row, deliberately. Splitting them
  // over a separate handle - even a sized, transparent one - makes the drag
  // start and finish in the same instant: dragStarted and dragFinished land
  // back to back in the log, the cursor picks up nothing, and no drop ever
  // happens. Qt carries the drag from the item that owns both.
  //
  // The row does get moved by the drag, but Drag.Automatic hands the pointer
  // to the compositor immediately, so it never travels far enough to see.
  Drag.active: mouse.drag.active
  Drag.dragType: Drag.Automatic
  Drag.supportedActions: Qt.CopyAction
  Drag.mimeData: ({
    "text/uri-list": String(row.file.url || "") + "\r\n",
    "text/plain": String(row.file.url || "")
  })
  Drag.onDragStarted: if (row.store) row.store.draggingUrl = String(row.file.url || "")
  Drag.onDragFinished: if (row.store) row.store.draggingUrl = ""

  Rectangle {
    anchors.fill: parent
    radius: Style.space(4)
    color: row.dragging
      ? Util.alpha(Color.accent, 0.22)
      : (mouse.containsMouse ? Util.alpha(Color.foreground, 0.10) : "transparent")
    border.width: row.dragging ? Style.spacing.hairline : 0
    border.color: Color.accent
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
      color: row.fresh ? Color.accent : "transparent"
    }

    Text {
      Layout.alignment: Qt.AlignVCenter
      text: (row.store && row.file) ? String(row.store.iconFor(row.file.name) || "") : ""
      textFormat: Text.PlainText
      font.family: (row.store && row.store.fontFamily) ? row.store.fontFamily : Style.font.family
      font.pixelSize: Style.font.icon
      renderType: Text.NativeRendering
      color: row.fresh ? Color.accent : Color.muted
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
      font.family: (row.store && row.store.fontFamily) ? row.store.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      renderType: Text.NativeRendering
      color: Color.foreground
    }

    Text {
      Layout.alignment: Qt.AlignVCenter
      text: (row.store && row.file)
        ? String(row.store.formatAge(row.file.modified) || "")
          + (row.file.size > 0 ? "  ·  " + String(row.store.formatSize(row.file.size) || "") : "")
        : ""
      textFormat: Text.PlainText
      font.family: (row.store && row.store.fontFamily) ? row.store.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
      color: Color.muted
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: mouse.drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    drag.target: row
    drag.threshold: Style.space(6)

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
