// Ícone do rodapé do painel (só o símbolo, com hover).

import QtQuick
import qs.services

Item {
    id: root

    property string glyph: ""
    signal activated()

    implicitWidth: 22
    implicitHeight: 22

    Text {
        anchors.centerIn: parent
        text: root.glyph
        font.family: Theme.iconFont
        font.pixelSize: 16
        color: area.containsMouse ? Theme.foreground : Theme.foregroundDim

        Behavior on color {
            ColorAnimation { duration: 120 }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
