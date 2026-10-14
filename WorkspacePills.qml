// Dots de desktop (KWin ou Umbriel, via serviço Workspaces).
// - Todos cinza (sem cor); o desktop atual fica aceso/maior.
// - Verticalmente centralizados na barra (alinhados com o sino).
// - Clique troca de desktop.

import QtQuick

Item {
    id: root

    implicitWidth: dots.implicitWidth
    implicitHeight: 18
    visible: Workspaces.displayItems.length > 0

    Row {
        id: dots

        anchors.verticalCenter: parent.verticalCenter
        spacing: 5

        Repeater {
            model: Workspaces.displayItems

            delegate: Item {
                required property var modelData

                width: modelData.active ? 9 : 6
                height: 9

                Behavior on width {
                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: parent.width
                    radius: width / 2
                    color: modelData.active ? Theme.foreground : Theme.foregroundDim
                    opacity: modelData.active ? 1 : (modelData.occupied ? 0.65 : 0.4)

                    Behavior on opacity {
                        NumberAnimation { duration: 150 }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Workspaces.switchTo(modelData)
                }
            }
        }
    }
}
