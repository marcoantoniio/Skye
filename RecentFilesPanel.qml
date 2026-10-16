// Painel "Recentes": arquivos mais novos de Downloads/Pictures/Documents/Videos
// para abrir com um clique (hub do botão ciano da ilha).

import Quickshell
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: panel

    property var panelWindow: null
    property var anchorItem: null

    readonly property int panelWidth: Theme.recentPanelWidth

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
    // Abertura: cresce de 0 até a altura final (saindo da ilha).
    // Troca: a moldura "morfa" do tamanho do painel antigo até o tamanho
    // deste — a janela se transforma, sem fade nem piscar.
    readonly property bool wanted: RecentFiles.open && !ControlCenter.open && !Notifications.centerOpen
    property bool shown: false
    readonly property real fullW: panel.panelWidth
    readonly property real fullH: Theme.recentPanelHeight
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

    // Troca: o painel que entra incrementa a sequência e define o alvo do
    // morph; quem está saindo acompanha NA MESMA hora (sem atraso de frame —
    // senão a janela antiga deixa um "rasto" aparecendo em volta da nova).
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
                    // Troca: nasce no tamanho do painel antigo e morfa até o seu
                    panel.frameW = Island.lastPanelWidth > 0 ? Island.lastPanelWidth : panel.fullW;
                    panel.frameH = Island.lastPanelHeight > 0 ? Island.lastPanelHeight : panel.fullH;
                    Island.switchTargetWidth = panel.fullW;
                    Island.switchTargetHeight = panel.fullH;
                    // Avisa quem está saindo para acompanhar o morph agora
                    Island.switchSeq += 1;
                } else {
                    // Abertura normal: cresce de 0 (saindo da ilha)
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
                // Reabriu durante a saída: volta ao tamanho final
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
            // Guarda o tamanho atual para a próxima troca começar daqui
            Island.lastPanelWidth = panel.frameW;
            Island.lastPanelHeight = panel.frameH;
            Qt.callLater(function() {
                if (panel.wanted || !panel.shown)
                    return;
                if (panel.switchMorph) {
                    // A troca já disparou o morph + o hide (Connections)
                    panel.switchMorph = false;
                } else {
                    // Fechou: recolhe para a ilha
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

    // Ícone por tipo de arquivo (glifos conferidos na Nerd Font)
    function iconFor(name) {
        const ext = name.substring(name.lastIndexOf(".") + 1).toLowerCase();
        if (["png", "jpg", "jpeg", "webp", "gif", "bmp", "svg", "avif"].includes(ext))
            return "\u{F02E9}"; // imagem
        if (["mp4", "mkv", "webm", "mov", "avi", "m4v"].includes(ext))
            return "\u{F0100}"; // vídeo
        if (["mp3", "flac", "ogg", "wav", "m4a", "opus", "aac"].includes(ext))
            return "\u{F075A}"; // áudio
        if (["zip", "tar", "gz", "xz", "7z", "rar", "zst"].includes(ext))
            return "\u{F01A7}"; // pacote
        if (["qml", "js", "ts", "py", "sh", "json", "html", "css", "c", "cpp", "h",
             "rs", "go", "toml", "yaml", "yml", "conf", "ini"].includes(ext))
            return "\u{F0A0A}"; // código
        if (["pdf", "txt", "md", "doc", "docx", "odt", "rtf", "csv", "xls", "xlsx",
             "ods", "ppt", "pptx"].includes(ext))
            return "\u{F0219}"; // documento
        return "\u{F0214}"; // genérico
    }

    function relTime(ts) {
        const diff = Date.now() / 1000 - ts;
        if (diff < 60)
            return I18n.tr("now");
        if (diff < 3600)
            return I18n.tr("agoMin", [Math.floor(diff / 60)]);
        if (diff < 86400)
            return I18n.tr("agoHour", [Math.floor(diff / 3600)]);
        return Qt.formatDateTime(new Date(ts * 1000), "dd/MM HH:mm");
    }

    Rectangle {
        id: frame

        // Tamanho animado: cresce na abertura e "morfa" na troca de painel
        width: Island.pillWidth
        height: panel.shown ? panel.frameH : 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        clip: true
        radius: Theme.radius
        // Cantos de cima retos: a moldura é a continuação da ilha enquanto
        // está na tela (a ilha só volta a arredondar quando ela recolhe).
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
            onHoveredChanged: RecentFiles.panelHovered = hovered
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

        Text {
            id: title

            anchors {
                top: parent.top
                left: parent.left
                topMargin: 12
                leftMargin: 14
            }
            opacity: panel.frameH < 120 ? 0 : 1
            text: I18n.tr("recent")
            color: Theme.foregroundDim
            font.family: Theme.fontFamily
            font.pixelSize: 10
        }

        Text {
            id: closeBtn

            anchors {
                top: parent.top
                right: parent.right
                topMargin: 8
                rightMargin: 14
            }
            opacity: panel.frameH < 120 ? 0 : 1
            text: "✕"
            color: closeArea.containsMouse ? Theme.foreground : Theme.foregroundDim
            font.family: Theme.fontFamily
            font.pixelSize: 13

            MouseArea {
                id: closeArea

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: RecentFiles.open = false
            }
        }

        ListView {
            id: list

            anchors {
                top: title.bottom
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                topMargin: 10
                leftMargin: 12
                rightMargin: 12
                bottomMargin: 12
            }
            opacity: panel.frameH < 120 ? 0 : 1
            clip: true
            spacing: 2
            model: RecentFiles.files

            delegate: Rectangle {
                id: fileRow

                required property var modelData

                width: ListView.view.width
                height: 32
                radius: 8
                color: rowArea.containsMouse ? Theme.surfaceHover : "transparent"

                Behavior on color {
                    ColorAnimation { duration: 100 }
                }

                Text {
                    id: fileIcon

                    anchors {
                        left: parent.left
                        leftMargin: 8
                        verticalCenter: parent.verticalCenter
                    }
                    text: panel.iconFor(fileRow.modelData.name)
                    color: Theme.foregroundDim
                    font.family: Theme.iconFont
                    font.pixelSize: 14
                }

                Column {
                    anchors {
                        left: fileIcon.right
                        leftMargin: 10
                        right: parent.right
                        rightMargin: 8
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 1

                    Text {
                        width: parent.width
                        text: fileRow.modelData.name
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        elide: Text.ElideMiddle
                    }

                    Text {
                        width: parent.width
                        text: fileRow.modelData.dir + " · " + panel.relTime(fileRow.modelData.ts)
                        color: Theme.foregroundDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: rowArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Quickshell.execDetached(["xdg-open", fileRow.modelData.path]);
                        RecentFiles.open = false;
                    }
                }
            }
        }

        Text {
            anchors.centerIn: list
            visible: RecentFiles.files.length === 0
            text: I18n.tr("nothingHere")
            color: Theme.foregroundDim
            font.family: Theme.fontFamily
            font.pixelSize: 11
        }
    }
}
