// Botão de quick setting / ação (usado no Control Center).
// Ativo = fundo com tom da cor de acento; indisponível = apagado e sem clique.

import QtQuick

Rectangle {
    id: root

    property string glyph: ""
    property string label: ""
    property bool active: false
    property bool available: true
    // Mouse em cima do botão (usado p/ fechar o menu de VPN ao sair)
    property bool hovered: false

    signal activated()

    implicitHeight: 46
    radius: 12
    color: active
           ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
           : Theme.surfaceHover
    border.width: 1
    border.color: active ? Theme.accent : "transparent"
    opacity: available ? 1 : 0.5

    Behavior on color {
        ColorAnimation { duration: 140 }
    }
    Behavior on opacity {
        NumberAnimation { duration: 140 }
    }

    Column {
        anchors.centerIn: parent
        spacing: 3

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.glyph
            font.family: Theme.iconFont
            font.pixelSize: 16
            color: root.active ? Theme.accent : Theme.foreground
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            font.family: Theme.fontFamily
            font.pixelSize: 10
            color: root.active ? Theme.foreground : Theme.foregroundDim
        }
    }

    // MouseArea cuida do clique; o hover é acompanhado por HoverHandler
    // (o `hovered` do MouseArea não atualiza neste shell)
    MouseArea {
        id: rowArea

        anchors.fill: parent
        enabled: root.available
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }

    HoverHandler {
        id: btnHover

        onHoveredChanged: {
            console.log("DBGQT hovered=", hovered); // TEMP
            root.hovered = hovered;
        }
    }
}
