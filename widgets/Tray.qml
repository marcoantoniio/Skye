// Ícones da bandeja do sistema (StatusNotifierItem).
// Esquerdo: ativar (ou abrir o menu, se o item só tiver menu). Meio: ativação
// secundária. Direito: menu do item (DBusMenu) ancorado ao ícone.

import Quickshell
import Quickshell.Services.SystemTray
import QtQuick

Row {
    id: root

    spacing: 6

    // Algum menu de item aberto? (segura o painel de notificações)
    property int openMenus: 0
    readonly property bool menuOpen: openMenus > 0

    Repeater {
        id: items

        model: SystemTray.items

        delegate: Item {
            id: entry

            required property var modelData

            implicitWidth: 20
            implicitHeight: 20
            visible: modelData.icon !== ""

            Image {
                anchors.fill: parent
                source: entry.modelData.icon
                sourceSize: Qt.size(20, 20)
                smooth: true
            }

            // Menu do item (DBusMenu), ancorado ao ícone
            QsMenuAnchor {
                id: menuAnchor

                menu: entry.modelData.menu
                anchor.item: entry

                onVisibleChanged: root.openMenus += visible ? 1 : -1
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: (mouse) => {
                    if (mouse.button === Qt.LeftButton) {
                        if (entry.modelData.onlyMenu && entry.modelData.hasMenu)
                            menuAnchor.open();
                        else
                            entry.modelData.activate();
                    } else if (mouse.button === Qt.MiddleButton) {
                        entry.modelData.secondaryActivate();
                    } else if (mouse.button === Qt.RightButton && entry.modelData.hasMenu) {
                        menuAnchor.open();
                    }
                }
            }
        }
    }
}
