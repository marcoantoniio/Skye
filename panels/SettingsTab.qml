// Aba de Settings do Control Center: preferências da ilha e módulos ligados.
// A fonte de verdade é services/Settings.qml (settings.json).

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.widgets

RowLayout {
    id: root

    Layout.fillWidth: true
    spacing: 18

    property real shiftX: 0
    transform: Translate { x: root.shiftX }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        spacing: 8

        Text {
            text: I18n.tr("settingsIsland")
            color: Theme.foregroundDim
            font.family: Theme.fontFamily
            font.pixelSize: 11
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: readoutRow.implicitHeight + 16
            radius: 12
            color: Theme.surfaceHover
            border.width: 1
            border.color: Theme.border

            ColumnLayout {
                id: readoutRow

                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 12
                    rightMargin: 12
                }
                spacing: 8

                Text {
                    text: I18n.tr("settingsReadout")
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }

                RowLayout {
                    spacing: 6

                    Repeater {
                        model: ["elapsed", "tokens", "cost"]

                        delegate: Rectangle {
                            required property string modelData

                            readonly property bool selected: Settings.readout === modelData

                            Layout.fillWidth: true
                            implicitHeight: 28
                            radius: 8
                            color: selected
                                ? Theme.withAlpha(Theme.accent, 0.22)
                                : Theme.surface
                            border.width: 1
                            border.color: selected ? Theme.accent : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: modelData === "elapsed" ? I18n.tr("ocReadoutElapsed")
                                    : modelData === "tokens" ? I18n.tr("ocReadoutTokens")
                                    : I18n.tr("ocReadoutCost")
                                color: selected ? Theme.accent : Theme.foregroundDim
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Settings.setReadout(modelData)
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            QuickToggle {
                Layout.fillWidth: true
                glyph: "\u{F009B}" // nf-md-bell-off
                label: I18n.tr("settingsFinishNotice")
                active: Settings.finishNotice
                onActivated: Settings.setFinishNotice(!Settings.finishNotice)
            }

            Rectangle {
                Layout.preferredWidth: 132
                implicitHeight: 46
                radius: 12
                color: Theme.surfaceHover
                border.width: 1
                border.color: Theme.border

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 10

                    Text {
                        text: "−"
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: 16

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Settings.setFinishMin(Settings.finishMin - 5)
                        }
                    }

                    Text {
                        text: Settings.finishMin === 0
                            ? I18n.tr("settingsFinishAll")
                            : Settings.finishMin + "s"
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }

                    Text {
                        text: "+"
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: 16

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Settings.setFinishMin(Settings.finishMin + 5)
                        }
                    }
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        spacing: 8

        Text {
            text: I18n.tr("settingsFeatures")
            color: Theme.foregroundDim
            font.family: Theme.fontFamily
            font.pixelSize: 11
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 8
            rowSpacing: 8

            QuickToggle {
                Layout.fillWidth: true
                glyph: "\u{F05A0}" // nf-md-webcam
                label: I18n.tr("camera")
                active: Settings.feature("camera")
                onActivated: Settings.setFeature("camera", !Settings.feature("camera"))
            }

            QuickToggle {
                Layout.fillWidth: true
                glyph: "\u{F0100}" // nf-md-video
                label: I18n.tr("recorder")
                active: Settings.feature("recorder")
                onActivated: Settings.setFeature("recorder", !Settings.feature("recorder"))
            }

            QuickToggle {
                Layout.fillWidth: true
                glyph: "\u{F0717}" // nf-md-snowflake
                label: I18n.tr("ac")
                active: Settings.feature("midea")
                onActivated: Settings.setFeature("midea", !Settings.feature("midea"))
            }

            QuickToggle {
                Layout.fillWidth: true
                glyph: "\u{F066F}" // nf-md-discord
                label: I18n.tr("settingsDiscord")
                active: Settings.feature("discord")
                onActivated: Settings.setFeature("discord", !Settings.feature("discord"))
            }
        }

        Text {
            text: I18n.tr("settingsUsage")
            color: Theme.foregroundDim
            font.family: Theme.fontFamily
            font.pixelSize: 11
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: usageRow.implicitHeight + 16
            radius: 12
            color: Theme.surfaceHover
            border.width: 1
            border.color: Theme.border

            GridLayout {
                id: usageRow
                columns: 2
                columnSpacing: 18
                rowSpacing: 4

                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 12
                    rightMargin: 12
                }

                Column {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: Agents.usageToday()
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    Text {
                        text: I18n.tr("settingsToday")
                        color: Theme.foregroundDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 8
                    }
                }

                Column {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: Agents.usageWeek()
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    Text {
                        text: I18n.tr("settingsWeek")
                        color: Theme.foregroundDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 8
                    }
                }

                Column {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: Format.tokens(Agents.usageTokens())
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    Text {
                        text: I18n.tr("ocTokens")
                        color: Theme.foregroundDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 8
                    }
                }

                Column {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: Format.cost(Agents.usage !== null ? Agents.usage.cost : 0)
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    Text {
                        text: I18n.tr("ocReadoutCost")
                        color: Theme.foregroundDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 8
                    }
                }
            }
        }
    }
}
