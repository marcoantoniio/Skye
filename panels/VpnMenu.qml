// Menu de VPNs (conectar/desconectar), ancorado no botão de rede do
// Control Center (mesmo padrão do DeviceMenu).

import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.services

PopupWindow {
    id: menu

    property var anchorTarget: null
    property var panelRef: null
    // Mouse em cima do menu (o painel usa para segurar o fechamento)
    readonly property bool hovered: menuHover.hovered

    signal dismissed()

    anchor.item: anchorTarget
    // Abre logo abaixo do item, alinhado à esquerda dele
    anchor.edges: Edges.Bottom | Edges.Left
    implicitWidth: 260
    implicitHeight: content.implicitHeight + 16
    color: "transparent"
    grabFocus: false

    onVisibleChanged: {
        if (!visible && menu.panelRef !== null && menu.panelRef.vpnMenuOpen)
            menu.dismissed();
    }

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: Theme.surface
        border.width: 1
        border.color: Theme.border

        // entrada suave, igual ao menu de dispositivos
        opacity: menu.visible ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }

        HoverHandler {
            id: menuHover
        }

        ColumnLayout {
            id: content

            anchors {
                fill: parent
                margins: 8
            }
            spacing: 3

            Text {
                Layout.leftMargin: 8
                text: I18n.tr("vpn")
                color: Theme.foregroundDim
                font.family: Theme.fontFamily
                font.pixelSize: 10
            }

            Text {
                Layout.leftMargin: 8
                visible: Vpn.profiles.length === 0
                text: I18n.tr("noVpnProfiles")
                color: Theme.foregroundDim
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.italic: true
            }

            Repeater {
                model: Vpn.profiles

                delegate: Rectangle {
                    id: row

                    required property var modelData

                    readonly property bool on: modelData.state === "activated"
                        || modelData.state === "activating"
                    readonly property bool busyRow: Vpn.busy !== "" && Vpn.busy === modelData.name

                    Layout.fillWidth: true
                    implicitHeight: 26
                    radius: 6
                    color: rowArea.containsMouse ? Theme.surfaceHover : "transparent"

                    RowLayout {
                        anchors {
                            fill: parent
                            leftMargin: 8
                            rightMargin: 8
                        }
                        spacing: 6

                        Text {
                            text: "\u{F0582}" // nf-md-vpn
                            font.family: Theme.iconFont
                            font.pixelSize: 12
                            color: row.on ? Theme.accent : Theme.foregroundDim
                        }

                        Text {
                            Layout.fillWidth: true
                            text: row.modelData.name
                            color: row.on ? Theme.accent : Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }

                        Text {
                            visible: row.modelData.state === "activating"
                            text: I18n.tr("connecting")
                            color: Theme.foregroundDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                        }

                        Text {
                            visible: row.modelData.state === "deactivating"
                            text: I18n.tr("disconnecting")
                            color: Theme.foregroundDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                        }

                        Text {
                            // ação em andamento antes do estado do NM mudar
                            visible: row.busyRow && row.modelData.state !== "activating"
                                && row.modelData.state !== "deactivating"
                            text: "…"
                            color: Theme.foregroundDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                        }

                        Text {
                            visible: row.modelData.state === "activated" && !row.busyRow
                            text: "\u{F012C}" // nf-md-check
                            font.family: Theme.iconFont
                            font.pixelSize: 11
                            color: Theme.accent
                        }
                    }

                    MouseArea {
                        id: rowArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor

                        onClicked: {
                            if (row.busyRow)
                                return;
                            Vpn.setConnected(row.modelData.name, !row.on);
                        }
                    }
                }
            }
        }
    }
}
