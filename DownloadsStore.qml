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
  // Files past the scan cap, counted from the model but never read.
  property int uncountedCount: 0
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

  // Entries a single rebuild is allowed to touch. The row cap alone does not
  // bound the work: it stops the list from growing, but the loop still ran to
  // the end of the folder, and every entry costs several reads across the
  // QML/C++ boundary. A folder with a hundred thousand files in it - unpacked
  // by accident, or filled on purpose - then put that whole walk on the UI
  // thread of a shell that never restarts. This is the ceiling on that walk.
  //
  // Cutting the tail is safe because the model hands back newest first: the
  // entries that fall outside the cap are the oldest ones, never a fresh
  // download and never a row that would have made the list.
  readonly property int maxScan: 2000

  // Watching a folder is not free, and the price is set by the folder rather
  // than by the change: Qt re-reads the whole directory every time anything
  // in it moves. On a download folder with a few hundred files in it that is
  // nothing. Measured on a folder of 41k files, a batch of 300 arrivals cost
  // the shell 7 seconds of CPU - one full re-read per file - and a shell that
  // never restarts cannot afford that.
  //
  // So the watcher is something the folder has to earn. Under maxScan it
  // stays live and a download shows up the moment it lands. Past that the
  // model is detached after each scan and the folder is polled instead, which
  // turns the cost of a folder that keeps changing into one scan per interval
  // instead of one per file. Nothing blinks while it is detached: every
  // property the window reads is a snapshot taken by rebuild(), not the model.
  property bool polling: false
  // The folder the model is watching right now. Empty means detached.
  property url scanFolder: root.folderUrl

  function configure(minutes, folder) {
    var n = Number(minutes)
    if (isFinite(n) && n >= 1 && n <= 1440) root.freshMinutes = Math.round(n)
    if (folder) root.folderUrl = folder
  }

  function show() { root.rescan(); root.open = true }
  function hide() { root.open = false }
  function toggle() { root.open ? root.hide() : root.show() }

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

  // Rebuild the visible list and recount what is fresh. The cost of one run
  // is bounded by maxScan rather than by the size of the folder, so a folder
  // nobody has ever cleaned out costs the same as an empty one.
  function rebuild() {
    var out = []
    var fresh = 0
    var total = 0
    var skipped = 0
    var cutoff = root.now - root.freshMinutes * 60000

    var count = folderModel.count
    var scan = Math.min(count, root.maxScan)

    for (var i = 0; i < scan; i++) {
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
    root.uncountedCount = count - scan
  }

  function tick() {
    root.now = Date.now()
    // Detached, or still reading: the model holds nothing to rebuild from,
    // and doing it anyway would blank the window. The snapshot from the last
    // scan stands until the next one lands. Note the clock above is set
    // either way, so the ages on screen keep moving.
    if (String(root.scanFolder) === "" || folderModel.status !== FolderListModel.Ready) return

    root.rebuild()

    if (folderModel.count > root.maxScan) {
      root.polling = true
      root.scanFolder = ""
    } else {
      root.polling = false
    }
  }

  // Read the folder again. Reattaching the model is itself the read, so it is
  // one or the other, never both.
  function rescan() {
    if (String(root.scanFolder) === "") root.scanFolder = root.folderUrl
    else root.tick()
  }

  // Every refresh that is not a direct answer to a click goes through here.
  // The folder reports one change per file, so a batch download or an
  // unpacking archive would otherwise ask for a rebuild dozens of times a
  // second. Restarting the timer collapses that burst into one.
  function scheduleTick() { coalesce.restart() }

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

  onShowAllChanged: root.rescan()
  onFolderUrlChanged: {
    root.polling = false
    root.scanFolder = root.folderUrl
    root.tick()
  }

  Timer {
    id: coalesce
    interval: 250
    repeat: false
    onTriggered: root.tick()
  }

  FolderListModel {
    id: folderModel
    folder: root.scanFolder
    showDirs: false
    showHidden: false
    showDotAndDotDot: false
    // Time sorting comes back newest first, which is the order the window
    // wants: the file you just downloaded is the one you came for.
    sortField: FolderListModel.Time
    sortReversed: false
    onCountChanged: root.scheduleTick()
    onStatusChanged: if (status === FolderListModel.Ready) root.scheduleTick()
  }

  // Ages drift and a download can finish while the window sits open, so the
  // list refreshes on its own. Fast enough that "just now" means something,
  // slow enough to stay invisible.
  //
  // With the window closed this mostly drives the badge going quiet once
  // nothing is fresh any more, and that can wait - on a watched folder the
  // arrival itself wakes the store, so a new download is never waiting on
  // this timer. It backs off rather than reading the folder every 20 seconds
  // for the rest of the session. On a polled folder this is the read, and the
  // same reasoning holds: the window is closed, nobody is looking.
  Timer {
    interval: root.open ? 20000 : 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.rescan()
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
              + (root.uncountedCount > 0 ? "More than " : "")
              + root.totalCount + " files in the folder."
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          renderType: Text.NativeRendering
          color: Color.muted
        }

        Text {
          Layout.fillWidth: true
          visible: root.hiddenCount > 0 || root.uncountedCount > 0
          textFormat: Text.PlainText
          text: root.uncountedCount > 0
            ? "Newest " + root.files.length + " of more than " + root.maxScan + " files"
            : "+ " + root.hiddenCount + " more not shown"
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
