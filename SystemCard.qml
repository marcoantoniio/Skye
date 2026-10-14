// Card "Sistema" do Dashboard (linhas com rótulo, valor e barra de progresso).

import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    property var metrics: [] // [{ label, value, progress }]

    implicitHeight: column.implicitHeight + 24
    radius: 12
    color: Theme.surfaceHover

    ColumnLayout {
        id: column

        anchors {
            fill: parent
            margins: 10
        }
        spacing: 6

        Text {
            text: I18n.tr("system")
            color: Theme.foregroundDim
            font.family: Theme.fontFamily
            font.pixelSize: 11
        }

        Repeater {
            model: root.metrics

            delegate: ColumnLayout {
                required property var modelData

                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 3

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        Layout.fillWidth: true
                        text: modelData.label
                        color: Theme.foregroundDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }

                    Text {
                        text: modelData.value
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.bold: true
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 4
                    radius: 2
                    color: Theme.surfaceHover
                    visible: modelData.progress >= 0

                    Rectangle {
                        width: Math.max(0, Math.min(1, modelData.progress)) * parent.width
                        height: parent.height
                        radius: parent.radius
                        color: Theme.accent
                    }
                }
            }
        }
    }
}
