// Slider horizontal simples (sem QtQuick.Controls), no estilo do tema.
// `value` vai de 0 a 1; arrastar/clicar emite moved(v).

import QtQuick

Item {
    id: root

    property real value: 0
    property bool muted: false
    property color accent: Theme.accent

    signal moved(real value)
    signal released()

    implicitHeight: 22

    function clamp01(v) {
        return Math.max(0, Math.min(1, v));
    }

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 6
        radius: 3
        color: Theme.surfaceHover

        Rectangle {
            width: root.clamp01(root.value) * track.width
            height: parent.height
            radius: parent.radius
            color: root.muted ? Theme.foregroundDim : root.accent
        }
    }

    Rectangle {
        id: handle
        width: 14
        height: 14
        radius: 7
        x: root.clamp01(root.value) * (root.width - width)
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.foreground
        border.width: 2
        border.color: root.muted ? Theme.foregroundDim : root.accent

        Behavior on x {
            enabled: !sliderArea.pressed
            NumberAnimation { duration: 80 }
        }
    }

    MouseArea {
        id: sliderArea
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor

        function emitAt(mx) {
            root.moved(root.clamp01(mx / root.width));
        }

        onClicked: (mouse) => emitAt(mouse.x)
        onPositionChanged: (mouse) => {
            if (pressed)
                emitAt(mouse.x);
        }
        onReleased: root.released()
    }
}
