// Card de clima do Dashboard: temperatura atual, bonequinho que troca de
// roupa conforme o tempo, linhas de máxima/mínima/chuva e sensação/umidade
// (com ícones) e 3 "quadradinhos" horários empilhados (com fundo próprio),
// cada um com hora, ícone, temperatura, sensação, umidade, vento e chuva.

import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    implicitHeight: 116
    radius: 12
    color: Theme.surfaceHover

    ColumnLayout {
        anchors {
            fill: parent
            margins: 10
        }
        spacing: 4

        // Título + ícone do tempo + temperatura
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: I18n.tr("weather")
                color: Theme.foregroundDim
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }

            Item { Layout.fillWidth: true }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: Weather.icon
                font.family: Theme.iconFont
                font.pixelSize: 16
                color: Theme.accent
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: Weather.available ? Weather.tempC + "°C" : "—"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: 20
                font.bold: true
            }
        }

        // Informações + bonequinho
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 4

                Text {
                    Layout.fillWidth: true
                    text: Weather.available ? Weather.desc : I18n.tr("loading")
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }

                // Maxima / minima / chuva do dia
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    visible: Weather.available

                    Text {
                        text: "\u{F005D}" // seta para cima (maxima)
                        font.family: Theme.iconFont
                        font.pixelSize: 9
                        color: Theme.accent
                    }

                    Text {
                        text: Weather.high + "°"
                        color: Theme.foregroundDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }

                    Text {
                        text: "\u{F0045}" // seta para baixo (minima)
                        font.family: Theme.iconFont
                        font.pixelSize: 9
                        color: Theme.accentCool
                    }

                    Text {
                        text: Weather.low + "°"
                        color: Theme.foregroundDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }

                    Text {
                        text: "\u{F0597}" // chuva
                        font.family: Theme.iconFont
                        font.pixelSize: 9
                        color: Theme.accentCool
                    }

                    Text {
                        text: Weather.rainChance + "%"
                        color: Theme.foregroundDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }

                    Item { Layout.fillWidth: true }
                }

                // Sensacao / umidade de agora
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    visible: Weather.available

                    Text {
                        text: "\u{F050F}" // termometro (sensacao)
                        font.family: Theme.iconFont
                        font.pixelSize: 9
                        color: Theme.accent
                    }

                    Text {
                        text: I18n.tr("feels") + Weather.feelsC + "°"
                        color: Theme.foregroundDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }

                    Text {
                        text: "\u{F058E}" // umidade
                        font.family: Theme.iconFont
                        font.pixelSize: 9
                        color: Theme.accentCool
                    }

                    Text {
                        text: Weather.humidity + "%"
                        color: Theme.foregroundDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }

                    Item { Layout.fillWidth: true }
                }
            }

            WeatherBuddy {
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // "Quadradinhos" horários (com fundo próprio), empilhados
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 6

            Repeater {
                model: Weather.hourly

                delegate: Rectangle {
                    required property var modelData

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 8
                    color: Theme.card

                    RowLayout {
                        anchors {
                            fill: parent
                            margins: 6
                        }
                        spacing: 10

                        // Hora acima do ícone do tempo
                        ColumnLayout {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 2

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData.label
                                color: Theme.foregroundDim
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData.icon
                                font.family: Theme.iconFont
                                font.pixelSize: 18
                                color: Theme.accent
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    text: modelData.temp + "°"
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 18
                                    font.bold: true
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: I18n.tr("feels") + modelData.feels + "°"
                                    color: Theme.foregroundDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 8
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 3

                                Text {
                                    text: "\u{F058E}" // umidade
                                    font.family: Theme.iconFont
                                    font.pixelSize: 9
                                    color: Theme.accentCool
                                }

                                Text {
                                    text: modelData.humidity + "%"
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 8
                                }

                                Text {
                                    text: "\u{F059D}" // vento
                                    font.family: Theme.iconFont
                                    font.pixelSize: 9
                                    color: Theme.accentCool
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.wind + "km"
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 8
                                    elide: Text.ElideRight
                                }

                                Text {
                                    text: "\u{F0597}" // chuva
                                    font.family: Theme.iconFont
                                    font.pixelSize: 9
                                    color: Theme.accentCool
                                }

                                Text {
                                    text: modelData.rain + "%"
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 8
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
