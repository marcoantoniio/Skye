// Painel "Recentes": arquivos mais novos de Downloads/Pictures/Documents/Videos
// para abrir com um clique (hub do botão ciano da ilha).

import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.services
import qs.widgets

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
    // Sempre mapeada (pré-mapeada) — a moldura em 0 é que a esconde
    visible: true

    MorphPanel {
        id: morph
        wanted: RecentFiles.open && !ControlCenter.open && !Notifications.centerOpen
        fullW: panel.panelWidth
        fullH: Theme.recentPanelHeight
    }

    // Bar.qml consulta/zera o estado ao descarregar a janela sob demanda.
    property alias shown: morph.shown

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
        height: morph.shown ? morph.frameH : 0
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
            opacity: morph.frameH < 120 ? 0 : 1
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
            opacity: morph.frameH < 120 ? 0 : 1
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
            opacity: morph.frameH < 120 ? 0 : 1
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
