pragma Singleton

import QtCore
import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import qs.Commons
import qs.Ui

// The download folder, and the one window that shows it.
//
// This is a singleton because a bar widget is instantiated once per monitor.
// With the window declared in the widget, a two-monitor setup gets two
// windows: clicking opens one, `shell summon` opens both, and closing one
// leaves the other behind. Measured, not guessed. Keeping the model and the
// window here means every bar button is a view onto the same thing.
//
// The list comes from FolderListModel rather than a helper script: no shell,
// no quoting, and no path from a filename into an exec. Filenames are chosen
// by whoever made the file, so every Text is PlainText - on the default
// AutoText, Qt decides for itself that a name looks like markup and renders
// it as rich text, and rich text really does fetch `<img src="http://...">`.
//
// Glyphs are \u escapes rather than literal characters, so the source
// survives editors and patches that mangle private-use codepoints.
Singleton {
  id: root

  // Set from the widget's shell.json entry; see Panel.qml. Defaults hold
  // until the first widget configures them, so the window is never empty
  // just because a setting is missing.
  property int freshMinutes: 5
  property url folderUrl: StandardPaths.writableLocation(StandardPaths.DownloadLocation)

  readonly property string folderPath: String(root.folderUrl).replace(/^file:\/\//, "")

  // The header names the folder it is showing, shortened the way a shell
  // prompt would. Note this is not the window title: that stays "Downloads",
  // because the Hyprland rule that floats this window matches on it.
  readonly property string homePath:
    String(StandardPaths.writableLocation(StandardPaths.HomeLocation)).replace(/^file:\/\//, "")
  // The Button tooltip is drawn by the shell's component, so textFormat there
  // is not ours to set. Strip the characters that could make it rich text.
  function plain(s) { return String(s || "").replace(/[<>]/g, "") }

  readonly property string displayPath: {
    var home = root.homePath
    var path = root.folderPath
    if (home !== "" && path.indexOf(home) === 0) return "~" + path.slice(home.length)
    return path
  }

  readonly property string iconDownload: "\uF019"
  readonly property string iconFolder: "\uF07C"
  readonly property string iconFile: "\uF15B"
  readonly property string iconImage: "\uF1C5"
  readonly property string iconPdf: "\uF1C1"
  readonly property string iconArchive: "\uF1C6"
  readonly property string iconAudio: "\uF1C7"
  readonly property string iconVideo: "\uF1C8"
  readonly property string iconCode: "\uF1C9"
  readonly property string iconText: "\uF0F6"

  property string fontFamily: Style.font.family

  // Rows currently shown, already filtered and capped.
  property var files: []
  // Files newer than freshMinutes, counted over the whole folder rather than
  // over the filtered view, so the badge means the same thing either way.
  property int freshCount: 0
  property int totalCount: 0
  // Files left out because the list is capped.
  property int hiddenCount: 0
  // Show everything, or only what arrived within freshMinutes.
  property bool showAll: true
  // Ages are read off this rather than off a fresh clock per row, so the
  // whole list ticks over together.
  property double now: Date.now()
  // The row being dragged, so it can dim while the drag is in flight.
  property string draggingUrl: ""
  // Whether the window is up. The widgets mirror this, they do not own it.
  property bool open: false

  readonly property int maxRows: 200

  function configure(minutes, folder) {
    var n = Number(minutes)
    if (isFinite(n) && n >= 1 && n <= 1440) root.freshMinutes = Math.round(n)
    if (folder) root.folderUrl = folder
  }

  function show() { root.showOn(null) }
  function hide() { root.open = false }
  function toggle() { root.open ? root.hide() : root.show() }

  // One window, many bar copies. The widget that opened it passes that
  // bar's screen so the list maps on the same output instead of Hyprland's
  // last-used monitor. Null keeps the current screen (IPC with no opener).
  function showOn(screen) {
    root.tick()
    if (screen)
      win.screen = screen
    root.open = true
  }

  // Partial downloads: the browser is still writing these and the final name
  // is not known yet, so they are noise in the list and useless to drag.
  function isPartial(name) {
    return /\.(crdownload|part|partial|download|tmp|opdownload)$/i.test(String(name))
  }

  function suffixOf(name) {
    var m = /\.([A-Za-z0-9]+)$/.exec(String(name))
    return m ? m[1].toLowerCase() : ""
  }

  function iconFor(name) {
    var s = root.suffixOf(name)
    if (/^(png|jpg|jpeg|gif|webp|bmp|svg|avif|heic|ico|tiff?)$/.test(s)) return root.iconImage
    if (s === "pdf") return root.iconPdf
    if (/^(zip|tar|gz|tgz|bz2|xz|7z|rar|zst|deb|rpm|pkg|iso|img|dmg|appimage)$/.test(s)) return root.iconArchive
    if (/^(mp3|wav|flac|ogg|m4a|aac|opus|wma)$/.test(s)) return root.iconAudio
    if (/^(mp4|mkv|mov|avi|webm|m4v|mpg|mpeg|wmv)$/.test(s)) return root.iconVideo
    if (/^(js|ts|json|py|rb|sh|c|h|cpp|rs|go|java|qml|html|css|xml|yml|yaml|toml)$/.test(s)) return root.iconCode
    if (/^(txt|md|csv|log|rtf|doc|docx|odt|xls|xlsx|ods|ppt|pptx|odp|epub)$/.test(s)) return root.iconText
    return root.iconFile
  }

  function formatSize(bytes) {
    var n = Number(bytes)
    if (!isFinite(n) || n < 0) return ""
    if (n < 1024) return n + " B"
    if (n < 1024 * 1024) return (n / 1024).toFixed(n < 10240 ? 1 : 0) + " KB"
    if (n < 1024 * 1024 * 1024) return (n / (1024 * 1024)).toFixed(n < 10 * 1024 * 1024 ? 1 : 0) + " MB"
    return (n / (1024 * 1024 * 1024)).toFixed(1) + " GB"
  }

  function formatAge(ms) {
    var secs = Math.max(0, Math.round((root.now - ms) / 1000))
    if (secs < 45) return "just now"
    var mins = Math.round(secs / 60)
    if (mins < 60) return mins + " min"
    var hours = Math.floor(mins / 60)
    if (hours < 24) return hours + " h"
    var days = Math.floor(hours / 24)
    if (days < 7) return days + " d"
    var weeks = Math.floor(days / 7)
    if (weeks < 5) return weeks + " w"
    return Math.floor(days / 30) + " mo"
  }

  // Rebuild the visible list and recount what is fresh. Cheap enough to run
  // on every folder change and on the tick; the model is already in memory.
  function rebuild() {
    var out = []
    var fresh = 0
    var total = 0
    var skipped = 0
    var cutoff = root.now - root.freshMinutes * 60000

    for (var i = 0; i < folderModel.count; i++) {
      var name = String(folderModel.get(i, "fileName") || "")
      if (name === "" || root.isPartial(name)) continue

      var mod = folderModel.get(i, "fileModified")
      var ms = mod ? mod.getTime() : 0
      var isFresh = ms >= cutoff

      total++
      if (isFresh) fresh++

      if (!root.showAll && !isFresh) continue
      if (out.length >= root.maxRows) { skipped++; continue }

      out.push({
        name: name,
        url: String(folderModel.get(i, "fileUrl") || ""),
        path: String(folderModel.get(i, "filePath") || ""),
        size: Number(folderModel.get(i, "fileSize")) || 0,
        modified: ms,
        fresh: isFresh
      })
    }

    root.files = out
    root.freshCount = fresh
    root.totalCount = total
    root.hiddenCount = skipped
  }

  function tick() {
    root.now = Date.now()
    root.rebuild()
  }

  // Quickshell.execDetached with an argument array, not Util.execDetached:
  // that helper takes a string and runs it through `bash -lc`, so anything
  // in the path would be shell input. The array form execs directly - no
  // shell, nothing to quote, nothing to inject.
  function openFolder() {
    var target = root.folderPath
    // An absolute path only. A `folder` setting like "-foo" would otherwise
    // arrive at xdg-open as an option rather than as a path.
    if (target.length > 1 && target.charAt(0) === "/")
      Quickshell.execDetached(["xdg-open", target])
  }

  onShowAllChanged: root.rebuild()
  onFolderUrlChanged: root.tick()

  FolderListModel {
    id: folderModel
    folder: root.folderUrl
    showDirs: false
    showHidden: false
    showDotAndDotDot: false
    // Time sorting comes back newest first, which is the order the window
    // wants: the file you just downloaded is the one you came for.
    sortField: FolderListModel.Time
    sortReversed: false
    onCountChanged: root.tick()
    onStatusChanged: if (status === FolderListModel.Ready) root.tick()
  }

  // Ages drift and a download can finish while the window sits open, so the
  // list refreshes on its own. Fast enough that "just now" means something,
  // slow enough to stay invisible.
  Timer {
    interval: 20000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.tick()
  }

  FloatingWindow {
    id: win

    visible: root.open
    title: "Downloads"
    color: Color.popups.background
    implicitWidth: Style.space(520)

    // The height follows the list instead of being a fixed box: with two
    // downloads in it, a 560px window is mostly empty, which reads as a
    // window rather than as a popout. Computed from the row count rather
    // than from the ListView's contentHeight, so nothing depends on a child
    // that in turn depends on this.
    readonly property int rowStride: Style.space(34) + Style.space(2)
    readonly property int chromeHeight: Style.space(104)
    readonly property int listHeight: Math.min(Style.space(420),
      Math.max(Style.space(64), root.files.length * rowStride))
    implicitHeight: chromeHeight + listHeight

    minimumSize: Qt.size(Style.space(360), Style.space(160))

    // Closing from the window's own titlebar has to reach the store, or the
    // bar buttons keep thinking the window is up and the next click does
    // nothing. Guarded, so the assignment made while opening does not come
    // straight back in here.
    onVisibleChanged: if (!visible && root.open) root.open = false

    FocusScope {
      anchors.fill: parent
      focus: true

      Keys.onEscapePressed: root.hide()

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.space(12)
        spacing: Style.space(10)

        // Header: what this is, what is being shown, and a way into the folder.
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Text {
            text: root.iconDownload
            textFormat: Text.PlainText
            font.family: root.fontFamily
            font.pixelSize: Style.font.icon
            renderType: Text.NativeRendering
            color: root.freshCount > 0 ? Color.accent : Color.foreground
          }

          // fillWidth plus preferredWidth 0 plus elide, all three. Without
          // them a long folder path sets the layout's minimum width, the
          // window is pushed wider than it draws, and the filter buttons and
          // the age column end up outside the frame - the path wins and
          // everything else silently leaves.
          Text {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            text: root.displayPath
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            renderType: Text.NativeRendering
            color: Color.foreground
          }

          // The shell's own segmented control rather than hand-drawn chips:
          // one rounded group, themed fills, and the same shape the rest of
          // Omarchy uses for "pick one of N".
          ButtonGroup {
            Layout.alignment: Qt.AlignVCenter
            options: [
              { value: "fresh", label: "Last " + root.freshMinutes + " min" },
              { value: "all", label: "All" }
            ]
            value: root.showAll ? "all" : "fresh"
            foreground: Color.foreground
            accent: Color.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            // The window has no panel cursor to hand around, so the group is
            // mouse-only and stays out of the Tab order.
            focusable: false
            onChanged: function(v) { root.showAll = (v === "all") }
          }

          Button {
            Layout.alignment: Qt.AlignVCenter
            iconText: root.iconFolder
            tooltipText: root.plain("Open " + root.displayPath)
            foreground: Color.muted
            accent: Color.accent
            fontFamily: root.fontFamily
            iconSize: Style.font.iconSmall
            onClicked: root.openFolder()
          }
        }

        Rectangle {
          Layout.fillWidth: true
          height: Style.spacing.hairline
          color: Color.popups.border
        }

        // The list. Each row is a drag handle; see DownloadRow.qml.
        ListView {
          id: list
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.minimumHeight: 0
          visible: root.files.length > 0
          clip: true
          spacing: Style.space(2)
          model: root.files
          boundsBehavior: Flickable.StopAtBounds

          delegate: DownloadRow {
            required property var modelData
            width: list.width
            store: root
            file: modelData
          }
        }

        // Empty state, which is the normal state for the "last N min" filter.
        Text {
          Layout.fillWidth: true
          Layout.fillHeight: true
          visible: root.files.length === 0
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: root.showAll
            ? "Nothing in " + root.displayPath
            : "Nothing in the last " + root.freshMinutes + " minutes.\n"
              + root.totalCount + " files in the folder."
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          renderType: Text.NativeRendering
          color: Color.muted
        }

        Text {
          Layout.fillWidth: true
          visible: root.hiddenCount > 0
          textFormat: Text.PlainText
          text: "+ " + root.hiddenCount + " more not shown"
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          renderType: Text.NativeRendering
          color: Color.muted
        }

        Text {
          Layout.fillWidth: true
          visible: root.files.length > 0
          textFormat: Text.PlainText
          text: "Drag a row into any window to hand over the file."
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          renderType: Text.NativeRendering
          color: Color.muted
        }
      }
    }
  }
}
