// Aba do topo do Control Center (Control Center / Dashboard / Clipboard & Notes).

import QtQuick
import qs.services

Rectangle {
    id: root

    property string label: ""
    property bool selected: false

    signal activated()

    implicitWidth: labelText.implicitWidth + 24
    implicitHeight: 28
    radius: 14
    color: selected
           ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
           : Theme.surfaceHover
    border.width: 1
    border.color: selected ? Theme.accent : "transparent"

    Behavior on color {
        ColorAnimation { duration: 120 }
    }

    Text {
        id: labelText
        anchors.centerIn: parent
        text: root.label
        color: root.selected ? Theme.accent : Theme.foregroundDim
        font.family: Theme.fontFamily
        font.pixelSize: 11
        font.bold: root.selected
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
