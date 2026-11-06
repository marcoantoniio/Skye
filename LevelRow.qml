// Linha de nível do Control Center (ícone circular + título + subtítulo + slider + seta).
// A seta abre o seletor de dispositivos (emitindo arrowClicked()).

import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root

    property string glyph: ""
    property string title: ""
    property string subtitle: ""
    property real value: 0
    property bool muted: false
    property bool available: true
    property bool showArrow: true

    // mouse sobre a setinha (o painel usa para fechar o menu ao sair)
    readonly property alias arrowHovered: arrowArea.containsMouse

    readonly property alias arrowItem: arrowBox

    signal moved(real value)
    signal iconClicked()
    signal arrowClicked()

    spacing: 10
    opacity: available ? 1 : 0.4

    Behavior on opacity {
        NumberAnimation { duration: 140 }
    }

    Rectangle {
        width: 30
        height: 30
        radius: 15
        color: Theme.accent

        Text {
            anchors.centerIn: parent
            text: root.glyph
            font.family: Theme.iconFont
            font.pixelSize: 15
            color: Theme.accentInk
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.available
            cursorShape: Qt.PointingHandCursor
            onClicked: root.iconClicked()
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        Text {
            Layout.fillWidth: true
            text: root.title
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: 12
            elide: Text.ElideRight
        }

        Text {
            Layout.fillWidth: true
            visible: root.subtitle !== ""
            text: root.subtitle
            color: Theme.foregroundDim
            font.family: Theme.fontFamily
            font.pixelSize: 10
            elide: Text.ElideRight
        }

        LevelSlider {
            Layout.fillWidth: true
            value: root.value
            muted: root.muted
            enabled: root.available
            onMoved: (v) => root.moved(v)
        }
    }

    Item {
        id: arrowBox

        visible: root.showArrow
        implicitWidth: 18
        implicitHeight: 24

        Text {
            anchors.centerIn: parent
            text: "›"
            rotation: 90
            color: arrowArea.containsMouse ? Theme.foreground : Theme.foregroundDim
            font.family: Theme.fontFamily
            font.pixelSize: 16
        }

        MouseArea {
            id: arrowArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.arrowClicked()
        }
    }
}
