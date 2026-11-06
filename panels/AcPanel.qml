// Painel do ar-condicionado (aberto pelo ícone na ilha). Mesmo esquema dos
// painéis das bolinhas: a ilha cresce até a largura do painel, a moldura
// "morfa" e o conteúdo aparece com fade. O estado aberto/fechado fica em
// Midea.panelOpen (fechado pelo timer da Bar quando o mouse sai).
// Controle 100% local via Midea.qml (token/key em ~/.config/skye/midea.json).

import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.services

PanelWindow {
    id: panel

    property var panelWindow: null
    property var anchorItem: null

    readonly property int panelWidth: Theme.acPanelWidth

    // Layer surface sempre mapeada (pré-mapeada): a troca de painel não tem
    // "blink" — a moldura é que cresce/diminui (0 = fechado, invisível, e a
    // máscara deixa os cliques passarem).
    screen: panelWindow ? panelWindow.screen : null
    anchors {
        top: true
        left: true
        right: true
    }
    margins {
        // encosta na ilha (fundo da pílula - 1)
        top: Island.square ? 38 : 45
        // janela só com a largura útil, centrada (a moldura máx é
        // Theme.panelMorphWidth): superfície menor = menos VRAM/RAM
        left: panelWindow ? Math.max(0, (panelWindow.screen.width - (Theme.panelMorphWidth + 20)) / 2) : 0
        right: panelWindow ? Math.max(0, (panelWindow.screen.width - (Theme.panelMorphWidth + 20)) / 2) : 0
    }
    implicitHeight: Theme.panelMorphHeight
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    aboveWindows: true
    mask: Region { item: frame }

    // ---- geometria da moldura (animada) ----
    readonly property bool wanted: Midea.panelOpen && !ControlCenter.open && !Notifications.centerOpen
    property bool shown: false
    readonly property real fullW: panel.panelWidth
    readonly property real fullH: Theme.acPanelHeight
    property real frameW: fullW
    property real frameH: 0

    // Sempre mapeada (pré-mapeada) — a moldura em 0 é que a esconde
    visible: true

    NumberAnimation {
        id: morphW

        target: panel
        property: "frameW"
        duration: 400
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: morphH

        target: panel
        property: "frameH"
        duration: 400
        easing.type: Easing.OutCubic
    }

    property bool switchMorph: false

    Connections {
        target: Island

        function onSwitchSeqChanged() {
            if (!panel.shown || panel.wanted)
                return;
            // Troca: este painel sai NA HORA — o que entra já nasce no mesmo
            // tamanho e se transforma. Nunca há duas janelas juntas.
            panel.switchMorph = true;
            Island.panelsShown -= 1;
            panel.shown = false;
        }
    }

    onWantedChanged: {
        if (wanted) {
            if (!shown) {
                const switching = Island.panelsShown > 0;
                Island.panelsShown += 1;
                panel.switchMorph = false;
                morphW.stop();
                morphH.stop();
                if (switching) {
                    panel.frameW = Island.lastPanelWidth > 0 ? Island.lastPanelWidth : panel.fullW;
                    panel.frameH = Island.lastPanelHeight > 0 ? Island.lastPanelHeight : panel.fullH;
                    Island.switchTargetWidth = panel.fullW;
                    Island.switchTargetHeight = panel.fullH;
                    Island.switchSeq += 1;
                } else {
                    panel.frameW = panel.fullW;
                    panel.frameH = 0;
                }
                shown = true;
                morphW.from = panel.frameW;
                morphW.to = panel.fullW;
                morphH.from = panel.frameH;
                morphH.to = panel.fullH;
                morphW.start();
                morphH.start();
            } else {
                morphW.stop();
                morphH.stop();
                morphW.from = panel.frameW;
                morphW.to = panel.fullW;
                morphH.from = panel.frameH;
                morphH.to = panel.fullH;
                morphW.start();
                morphH.start();
            }
        } else if (shown) {
            Island.lastPanelWidth = panel.frameW;
            Island.lastPanelHeight = panel.frameH;
            Qt.callLater(function() {
                if (panel.wanted || !panel.shown)
                    return;
                if (panel.switchMorph) {
                    panel.switchMorph = false;
                } else {
                    morphW.stop();
                    morphH.stop();
                    morphH.from = panel.frameH;
                    morphH.to = 0;
                    morphH.start();
                    hideDelay.restart();
                }
            });
        }
    }

    Timer {
        id: hideDelay

        interval: 440
        onTriggered: {
            if (!panel.wanted && panel.shown) {
                Island.panelsShown -= 1;
                panel.shown = false;
            }
        }
    }

    // Chip (modo/vento/swing/toggle): preenchido quando selecionado.
    // Textos têm altura fixa + alinhamento vertical: sem isso, a métrica
    // diferente da fonte de ícones desalinhava o conteúdo do centro.
    component Chip: Rectangle {
        id: chip

        property string glyph: ""
        property string text: ""
        property bool selected: false
        property bool usable: true

        signal clicked()

        implicitWidth: contentRow.implicitWidth + 20
        implicitHeight: 28
        radius: 8
        color: selected
            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
            : (rowArea.containsMouse && usable ? Theme.surfaceHover : "transparent")
        border.width: 1
        border.color: selected ? Theme.accent : Theme.border
        opacity: usable ? 1 : 0.35

        Behavior on color {
            ColorAnimation { duration: 120 }
        }

        Row {
            id: contentRow

            anchors.centerIn: parent
            spacing: 5

            Text {
                height: 14
                verticalAlignment: Text.AlignVCenter
                visible: chip.glyph !== ""
                text: chip.glyph
                font.family: Theme.iconFont
                font.pixelSize: 13
                color: chip.selected ? Theme.accent : Theme.foregroundDim
            }

            Text {
                height: 14
                verticalAlignment: Text.AlignVCenter
                visible: chip.text !== ""
                text: chip.text
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: chip.selected ? Theme.foreground : Theme.foregroundDim
            }
        }

        MouseArea {
            id: rowArea

            anchors.fill: parent
            enabled: chip.usable
            hoverEnabled: true
            cursorShape: chip.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: chip.clicked()
        }
    }

    // Rótulo de linha com ícone (Temperatura/Modo/Vento/Swing)
    component RowLabel: Row {
        id: label

        property string glyph: ""
        property string text: ""

        width: 96
        spacing: 5

        Text {
            height: 16
            verticalAlignment: Text.AlignVCenter
            text: label.glyph
            font.family: Theme.iconFont
            font.pixelSize: 12
            color: Theme.foregroundDim
        }

        Text {
            height: 16
            verticalAlignment: Text.AlignVCenter
            text: label.text
            font.family: Theme.fontFamily
            font.pixelSize: 11
            color: Theme.foregroundDim
            elide: Text.ElideRight
        }
    }

    Rectangle {
        id: frame

        width: Island.pillWidth
        height: panel.shown ? panel.frameH : 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        clip: true
        radius: Theme.radius
        topLeftRadius: 0
        topRightRadius: 0
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: Theme.backgroundTop }
            GradientStop { position: 0.6; color: Theme.backgroundTop }
            GradientStop { position: 1.0; color: Theme.backgroundBottom }
        }
        border.width: 1
        border.color: Theme.border

        HoverHandler {
            onHoveredChanged: Midea.panelHovered = hovered
        }

        // Junção com a ilha: esconde a borda de cima
        Rectangle {
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                leftMargin: 1
                rightMargin: 1
            }
            height: 1
            color: Theme.edgeLine
        }

        ColumnLayout {
            id: content

            anchors {
                fill: parent
                margins: 16
            }
            spacing: 10
            opacity: panel.frameH < 120 ? 0 : 1

            // ---- cabeçalho: unidade + título + estado + power ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                // Split horizontal (mesmo desenho do botão da ilha)
                Item {
                    implicitWidth: 40
                    implicitHeight: 16

                    Rectangle {
                        anchors.fill: parent
                        radius: 3
                        color: "transparent"
                        border.width: 1.5
                        border.color: (Midea.online && Midea.power) ? Theme.accent : Theme.foregroundDim

                        Rectangle {
                            anchors {
                                horizontalCenter: parent.horizontalCenter
                                bottom: parent.bottom
                                bottomMargin: 2.4
                            }
                            width: parent.width - 10
                            height: 1.4
                            radius: 0.7
                            color: (Midea.online && Midea.power) ? Theme.accent : Theme.foregroundDim
                        }
                    }
                }

                Text {
                    text: I18n.tr("ac")
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                    font.bold: true
                }

                Text {
                    Layout.topMargin: 2
                    text: Midea.online
                        ? (Midea.power ? I18n.tr("acOn") : I18n.tr("acOff"))
                        : I18n.tr("acOffline")
                    color: Midea.online ? Theme.foregroundDim : Theme.urgent
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }

                Item { Layout.fillWidth: true }

                // power
                Rectangle {
                    implicitWidth: 38
                    implicitHeight: 38
                    radius: 11
                    color: Midea.power
                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                        : Theme.surfaceHover
                    border.width: 1
                    border.color: Midea.power ? Theme.accent : "transparent"
                    opacity: Midea.online ? 1 : 0.4

                    Text {
                        anchors.centerIn: parent
                        text: "\u{F0425}" // nf-md-power
                        font.family: Theme.iconFont
                        font.pixelSize: 18
                        color: Midea.power ? Theme.accent : Theme.foregroundDim
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: Midea.online
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Midea.setPower(!Midea.power)
                    }
                }
            }

            // ---- temperaturas ambiente/externa ----
            Row {
                spacing: 6

                Text {
                    text: "\u{F050F}" // nf-md-thermometer
                    font.family: Theme.iconFont
                    font.pixelSize: 11
                    color: Theme.foregroundDim
                }

                Text {
                    text: Midea.online
                        ? Midea.indoor.toFixed(1) + "° " + I18n.tr("acInside")
                          + "  ·  " + Midea.outdoor.toFixed(1) + "° " + I18n.tr("acOutside")
                        : I18n.tr("acOffline")
                    color: Midea.online ? Theme.foregroundDim : Theme.urgent
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }
            }

            // ---- energia (consumo e potência) ----
            Row {
                spacing: 6

                Text {
                    text: "\u{F140B}" // nf-md-lightning_bolt
                    font.family: Theme.iconFont
                    font.pixelSize: 11
                    color: Theme.foregroundDim
                }

                Text {
                    text: Midea.online
                        ? I18n.tr("acNow") + " " + Math.round(Midea.powerW) + " W"
                        : ""
                    color: Theme.foregroundDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.border
            }

            // ---- temperatura alvo (termostato) ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                RowLabel {
                    glyph: "\u{F050F}" // thermometer
                    text: I18n.tr("acTemperature")
                }

                Item { Layout.fillWidth: true }

                Chip {
                    implicitWidth: 30
                    glyph: "\u{F0374}" // minus
                    usable: Midea.online
                    onClicked: Midea.setTarget(Midea.target - 1)
                }

                Text {
                    Layout.preferredWidth: 74
                    horizontalAlignment: Text.AlignHCenter
                    text: Math.round(Midea.target) + "°C"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 22
                    font.bold: true
                }

                Chip {
                    implicitWidth: 30
                    glyph: "\u{F0415}" // plus
                    usable: Midea.online
                    onClicked: Midea.setTarget(Midea.target + 1)
                }
            }

            // ---- modo ----
            Row {
                height: 28
                spacing: 5

                RowLabel {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "\u{F006A}" // autorenew
                    text: I18n.tr("acMode")
                }

                Chip {
                    glyph: "\u{F006A}" // autorenew
                    text: I18n.tr("acAuto")
                    visible: Midea.modes.indexOf("AUTO") >= 0
                    selected: Midea.mode === "AUTO"
                    usable: Midea.online
                    onClicked: Midea.setMode("AUTO")
                }

                Chip {
                    glyph: "\u{F0717}" // snowflake
                    text: I18n.tr("acCool")
                    visible: Midea.modes.indexOf("COOL") >= 0
                    selected: Midea.mode === "COOL"
                    usable: Midea.online
                    onClicked: Midea.setMode("COOL")
                }

                Chip {
                    glyph: "\u{F058C}" // water
                    text: I18n.tr("acDry")
                    visible: Midea.modes.indexOf("DRY") >= 0
                    selected: Midea.mode === "DRY"
                    usable: Midea.online
                    onClicked: Midea.setMode("DRY")
                }

                Chip {
                    glyph: "\u{F0210}" // fan
                    text: I18n.tr("acFanOnly")
                    visible: Midea.modes.indexOf("FAN_ONLY") >= 0
                    selected: Midea.mode === "FAN_ONLY"
                    usable: Midea.online
                    onClicked: Midea.setMode("FAN_ONLY")
                }
            }

            // ---- vento ----
            Row {
                height: 28
                spacing: 5

                RowLabel {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "\u{F0210}" // fan
                    text: I18n.tr("acFan")
                }

                Chip {
                    text: I18n.tr("acAuto")
                    selected: Midea.fan === "AUTO"
                    usable: Midea.online
                    onClicked: Midea.setFan("AUTO")
                }

                Chip {
                    text: I18n.tr("acSilent")
                    selected: Midea.fan === "SILENT"
                    usable: Midea.online
                    onClicked: Midea.setFan("SILENT")
                }

                Chip {
                    text: I18n.tr("acLow")
                    selected: Midea.fan === "LOW"
                    usable: Midea.online
                    onClicked: Midea.setFan("LOW")
                }

                Chip {
                    text: I18n.tr("acMedium")
                    selected: Midea.fan === "MEDIUM"
                    usable: Midea.online
                    onClicked: Midea.setFan("MEDIUM")
                }

                Chip {
                    text: I18n.tr("acHigh")
                    selected: Midea.fan === "HIGH"
                    usable: Midea.online
                    onClicked: Midea.setFan("HIGH")
                }

                Chip {
                    text: I18n.tr("acMax")
                    selected: Midea.fan === "MAX"
                    usable: Midea.online
                    onClicked: Midea.setFan("MAX")
                }
            }

            // ---- swing ----
            Row {
                height: 28
                spacing: 5

                RowLabel {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "\u{F0E79}" // arrow_up_down
                    text: I18n.tr("acSwing")
                }

                Chip {
                    text: I18n.tr("acOff")
                    selected: Midea.swing === "OFF"
                    usable: Midea.online
                    onClicked: Midea.setSwing("OFF")
                }

                Chip {
                    glyph: "\u{F0E79}" // arrow_up_down
                    selected: Midea.swing === "VERTICAL"
                    usable: Midea.online
                    onClicked: Midea.setSwing("VERTICAL")
                }

                Chip {
                    glyph: "\u{F0E73}" // arrow_left_right
                    selected: Midea.swing === "HORIZONTAL"
                    usable: Midea.online
                    onClicked: Midea.setSwing("HORIZONTAL")
                }

                Chip {
                    glyph: "\u{F0041}" // arrow_all
                    selected: Midea.swing === "BOTH"
                    usable: Midea.online
                    onClicked: Midea.setSwing("BOTH")
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.border
            }

            // ---- modos extras (só os suportados pelo aparelho) ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 5

                Chip {
                    glyph: "\u{F032A}" // leaf
                    text: I18n.tr("acIeco")
                    visible: Midea.capIeco
                    selected: Midea.ieco
                    usable: Midea.online
                    onClicked: Midea.setIeco(!Midea.ieco)
                }

                Chip {
                    glyph: "\u{F14DE}" // rocket_launch
                    text: I18n.tr("acTurbo")
                    visible: Midea.capTurbo
                    selected: Midea.turbo
                    usable: Midea.online
                    onClicked: Midea.setTurbo(!Midea.turbo)
                }

                Chip {
                    glyph: "\u{F04B2}" // sleep (lua)
                    text: I18n.tr("acSleep")
                    selected: Midea.sleep
                    usable: Midea.online
                    onClicked: Midea.setSleep(!Midea.sleep)
                }

                Chip {
                    glyph: "\u{F07F4}" // television_classic
                    text: I18n.tr("acDisplay")
                    visible: Midea.capDisplay
                    selected: Midea.display
                    usable: Midea.online
                    onClicked: Midea.setDisplay(!Midea.display)
                }

                Chip {
                    glyph: "\u{F0D44}" // air_purifier
                    text: I18n.tr("acIon")
                    visible: Midea.capPurifier
                    selected: Midea.purifier
                    usable: Midea.online
                    onClicked: Midea.setPurifier(!Midea.purifier)
                }

                Item { Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 5

                Chip {
                    glyph: "\u{F0241}" // flash
                    text: I18n.tr("acFlash")
                    visible: Midea.capFlash
                    selected: Midea.flash
                    usable: Midea.online
                    onClicked: Midea.setFlash(!Midea.flash)
                }

                Chip {
                    glyph: "\u{F00E2}" // broom
                    text: I18n.tr("acClean")
                    visible: Midea.capSelfClean
                    selected: Midea.selfClean
                    usable: Midea.online
                    onClicked: Midea.startSelfClean()
                }

                Chip {
                    glyph: "\u{F059D}" // weather_windy
                    text: I18n.tr("acBreeze")
                    visible: Midea.capBreeze
                    selected: Midea.breezeAway
                    usable: Midea.online
                    onClicked: Midea.setBreezeAway(!Midea.breezeAway)
                }

                Item { Layout.fillWidth: true }
            }
        }
    }
}
