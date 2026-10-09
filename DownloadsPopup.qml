import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// A layer-shell card with outside-click dismissal. During a native drag,
// only the card accepts input: a full-screen input region would cover every
// drop target beneath it, even though the rest of the surface is transparent.
PanelWindow {
  id: popup

  property Item anchorItem: null
  property QtObject bar: null
  property QtObject owner: null
  property bool open: false
  property bool dragging: false
  property real contentWidth: Style.space(520)
  property real contentHeight: Style.space(300)
  property bool focusPrimed: false
  default property alias content: body.data
  signal dismissed()

  function close() { popup.dismissed() }

  readonly property QtObject coordinatorKey: owner || popup

  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property string barPosition: bar ? bar.position : "top"
  readonly property real gap: Style.gapsOut
  readonly property real cardWidth: Math.min(contentWidth, Math.max(1, width - gap * 2
    - (barPosition === "left" || barPosition === "right" ? (anchorWindow ? anchorWindow.width : 0) : 0)))
  readonly property real cardHeight: Math.min(contentHeight, Math.max(1, height - gap * 2
    - (barPosition === "top" || barPosition === "bottom" ? (anchorWindow ? anchorWindow.height : 0) : 0)))
  readonly property point cardPosition: {
    anchorTracker.transform
    var p = anchorItem && anchorWindow ? anchorItem.mapToItem(anchorWindow.contentItem, 0, 0) : Qt.point(width - cardWidth, 0)
    var aw = anchorItem ? anchorItem.width : 0
    var ah = anchorItem ? anchorItem.height : 0
    var bw = anchorWindow ? anchorWindow.width : 0
    var bh = anchorWindow ? anchorWindow.height : 0
    var x = p.x + aw / 2 - cardWidth / 2
    var y = bh + gap
    if (barPosition === "bottom") y = height - bh - cardHeight - gap
    else if (barPosition === "left") { x = bw + gap; y = p.y + ah / 2 - cardHeight / 2 }
    else if (barPosition === "right") { x = width - bw - cardWidth - gap; y = p.y + ah / 2 - cardHeight / 2 }
    return Qt.point(Math.round(Math.max(gap, Math.min(x, width - cardWidth - gap))),
                    Math.round(Math.max(gap, Math.min(y, height - cardHeight - gap))))
  }

  TransformWatcher {
    id: anchorTracker
    a: popup.anchorItem
    b: popup.anchorWindow ? popup.anchorWindow.contentItem : null
  }

  screen: anchorWindow ? anchorWindow.screen : null
  visible: open
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  anchors { top: true; bottom: true; left: true; right: true }
  WlrLayershell.namespace: "jankeesvw.downloads"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: !open || dragging ? WlrKeyboardFocus.None
    : (focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
  mask: Region {
    x: popup.dragging ? card.x : 0
    y: popup.dragging ? card.y : 0
    width: popup.dragging ? card.width : popup.width
    height: popup.dragging ? card.height : popup.height
  }

  onOpenChanged: {
    if (open) {
      focusPrimed = false
      prime.restart()
      body.forceActiveFocus()
      if (bar) bar.requestPopout(coordinatorKey)
    } else {
      prime.stop()
      if (bar && bar.activePopout === coordinatorKey) bar.releasePopout(coordinatorKey)
    }
  }
  Timer { id: prime; interval: 75; onTriggered: popup.focusPrimed = true }

  // Any click outside the card closes the panel, a click on the bar
  // included. KeyboardPanel forwards bar clicks so another widget can open
  // in the same click, but a plugin only ever sees its own click targets
  // (PluginBarApi hands each plugin its own list), so from here the only
  // button that could be found is ours, and that one toggles closed anyway.
  MouseArea {
    anchors.fill: parent
    enabled: popup.open && !popup.dragging
    acceptedButtons: Qt.AllButtons
    onClicked: popup.close()
  }

  // Dismiss clicks on other monitors too, but let drags reach their windows.
  Variants {
    model: popup.open && !popup.dragging ? Quickshell.screens : []
    delegate: Component {
      PanelWindow {
        required property var modelData
        screen: modelData
        visible: !!popup.screen && modelData.name !== popup.screen.name
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.namespace: "jankeesvw.downloads-dismiss"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: popup.close() }
      }
    }
  }

  BorderSurface {
    id: card
    x: popup.cardPosition.x; y: popup.cardPosition.y
    width: popup.cardWidth; height: popup.cardHeight
    color: Commons.Color.popups.background
    borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
    padding: 0
    radius: Style.cornerRadius
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
    FocusScope {
      id: body
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.rightMargin: card.contentRightInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
      focus: true
      Keys.onEscapePressed: popup.close()
    }
  }
}
