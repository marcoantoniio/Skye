// Aba/pílula colorida de filtro do painel de notificações.

import QtQuick
import qs.services

Rectangle {
    id: root

    property string label: ""
    property color tabColor: Theme.accent
    property bool selected: false

    signal activated()

    implicitWidth: labelText.implicitWidth + 16
    implicitHeight: 22
    radius: 11
    color: selected ? tabColor : Theme.surfaceHover
    opacity: selected ? 1 : (tabArea.containsMouse ? 0.9 : 0.7)

    Behavior on color {
        ColorAnimation { duration: 120 }
    }
    Behavior on opacity {
        NumberAnimation { duration: 120 }
    }

    Text {
        id: labelText
        anchors.centerIn: parent
        text: root.label
        color: root.selected ? Theme.background : Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: 11
        font.bold: root.selected
    }

    MouseArea {
        id: tabArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
