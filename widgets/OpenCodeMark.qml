// Marca do OpenCode: terminal na cor de destaque do tema do Skye.

import QtQuick
import qs.services

Item {
    id: root

    property real size: 15
    property bool working: true

    implicitWidth: size
    implicitHeight: Math.round(size * 0.93)

    SequentialAnimation on opacity {
        loops: Animation.Infinite
        running: root.working
        NumberAnimation { from: 1; to: 0.72; duration: 1100; easing.type: Easing.InOutSine }
        NumberAnimation { from: 0.72; to: 1; duration: 1100; easing.type: Easing.InOutSine }
    }

    Rectangle {
        anchors.fill: parent
        radius: size * 0.24
        color: Theme.withAlpha(Theme.accent, 0.12)
        border.width: 1
        border.color: Theme.accent
    }

    Text {
        x: size * 0.20
        anchors.verticalCenter: parent.verticalCenter
        text: ">"
        color: Theme.accent
        font.family: Theme.iconFont
        font.pixelSize: Math.max(7, size * 0.53)
        font.bold: true
    }

    Rectangle {
        x: size * 0.53
        width: Math.max(3, size * 0.27)
        height: Math.max(1, size * 0.10)
        radius: height / 2
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.accent

        SequentialAnimation on opacity {
            loops: Animation.Infinite
            running: root.working
            NumberAnimation { from: 1; to: 0.15; duration: 450 }
            NumberAnimation { from: 0.15; to: 1; duration: 450 }
        }
    }
}
