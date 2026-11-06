// Menu de seleção de dispositivo de áudio (saída/entrada), ancorado na setinha
// da linha de nível.

import Quickshell
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts

PopupWindow {
    id: menu

    property var anchorTarget: null
    property string kind: "sink"
    property var panelRef: null

    // Mouse em cima do menu (o painel usa para segurar o fechamento)
    readonly property bool hovered: menuHover.hovered

    signal dismissed()

    readonly property var devices: {
        const out = [];
        const nodes = Pipewire.nodes.values;
        for (let i = 0; i < nodes.length; ++i) {
            const n = nodes[i];
            if (n.isStream || n.audio === null)
                continue;
            if (menu.kind === "sink" ? n.isSink : !n.isSink)
                out.push(n);
        }
        return out;
    }

    function choose(node) {
        if (menu.kind === "sink")
            Pipewire.preferredDefaultAudioSink = node;
        else
            Pipewire.preferredDefaultAudioSource = node;
        menu.dismissed();
    }

    anchor.item: anchorTarget
    implicitWidth: 280
    implicitHeight: content.implicitHeight + 16
    color: "transparent"
    grabFocus: false

    onVisibleChanged: {
        if (!visible && menu.panelRef !== null && menu.panelRef.deviceMenuOpen)
            menu.dismissed();
    }

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: Theme.surface
        border.width: 1
        border.color: Theme.border

        // entrada suave, igual ao menu de VPN
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

            Repeater {
                model: menu.devices

                delegate: Rectangle {
                    id: row

                    required property var modelData

                    readonly property bool current: menu.kind === "sink"
                        ? Pipewire.defaultAudioSink === modelData
                        : Pipewire.defaultAudioSource === modelData

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
                            Layout.fillWidth: true
                            text: row.modelData.description !== "" ? row.modelData.description : row.modelData.name
                            color: row.current ? Theme.accent : Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }

                        Text {
                            visible: row.current
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
                        onClicked: menu.choose(row.modelData)
                    }
                }
            }
        }
    }
}
