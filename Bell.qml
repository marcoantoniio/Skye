// Sino de notificações (estilo do original: ícone cinza + dot laranja quando
// há notificações). Clique abre/fecha o painel central (categoria "todas").

import QtQuick

Item {
    id: root

    implicitWidth: 18
    implicitHeight: 18

    scale: bellArea.containsMouse ? 1.12 : 1
    Behavior on scale {
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
    }

    Text {
        anchors.centerIn: parent
        text: "\u{F009A}" // nf-md-bell
        font.family: Theme.iconFont
        font.pixelSize: 15
        color: Notifications.count > 0 ? Theme.foreground : Theme.foregroundDim
        Behavior on color {
            ColorAnimation { duration: 150 }
        }
    }

    // Dot de "tem notificação"
    Rectangle {
        visible: Notifications.count > 0
        width: 8
        height: 8
        radius: 4
        color: Theme.accent
        anchors {
            right: parent.right
            top: parent.top
            rightMargin: -2
            topMargin: -2
        }
    }

    MouseArea {
        id: bellArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Notifications.toggleAll()
        onContainsMouseChanged: Notifications.triggerHovered = containsMouse
    }
}
