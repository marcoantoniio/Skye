// Rosto de robozinho da aba OpenCode: pisca de vez em quando.

import QtQuick

Item {
    id: root

    implicitWidth: 20
    implicitHeight: 20

    property bool blinking: false

    // pisca a cada ~3s (fecha rápido e reabre)
    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: {
            root.blinking = true;
            reopen.restart();
        }
    }

    Timer {
        id: reopen

        interval: 90
        onTriggered: root.blinking = false
    }

    // antena (haste + pontinha)
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 3.5
        width: 1.5
        height: 3.5
        color: Theme.border
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 0
        width: 3.5
        height: 3.5
        radius: 1.75
        color: Theme.accentAlt
    }

    // cabeça (telinha)
    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            bottom: parent.bottom
            topMargin: 6.5
        }
        radius: 4.5
        color: Theme.card
        border.width: 1
        border.color: Theme.border

        // olhos (piscam juntos, encolhendo pelo centro)
        Rectangle {
            id: leftEye

            anchors.verticalCenter: parent.verticalCenter
            x: 4
            width: 3
            height: root.blinking ? 0.8 : 3.6
            radius: 1.5
            color: Theme.accent

            Behavior on height {
                NumberAnimation { duration: 70 }
            }
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: parent.width - 4 - width
            width: 3
            height: leftEye.height
            radius: 1.5
            color: Theme.accent
        }

        // boca
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 2.5
            width: 5
            height: 1
            radius: 0.5
            color: Theme.foregroundDim
            opacity: 0.8
        }
    }
}
