// Painel de música — abre ao passar o mouse na ilha quando há música tocando.
// Capa com brilho da cor do álbum, controles, progresso (seek), saída de áudio,
// mixer por aplicativo e letras (lrclib).

import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes

PanelWindow {
    id: panel

    property var panelWindow: null
    property var anchorItem: null

    readonly property int panelWidth: Theme.musicPanelWidth

    readonly property var sinks: {
        const out = [];
        const nodes = Pipewire.nodes.values;
        for (let i = 0; i < nodes.length; ++i) {
            const n = nodes[i];
            if (!n.isStream && n.audio !== null && n.isSink)
                out.push(n);
        }
        return out;
    }

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
    readonly property bool wanted: Music.panelOpen && !ControlCenter.open && !Notifications.centerOpen
    property bool shown: false
    readonly property real fullW: panel.panelWidth
    readonly property real fullH: column.height + 24
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

    // As seções (Saída/Letras) mudam a altura do conteúdo: re-morfa a moldura
    // depois do layout recalcular — senão a seção nova fica cortada até
    // fechar/reabrir o painel.
    Timer {
        id: sectionMorphTimer

        interval: 50
        onTriggered: {
            if (panel.shown && panel.wanted) {
                morphH.stop();
                morphH.from = panel.frameH;
                morphH.to = panel.fullH;
                morphH.start();
            }
        }
    }

    Connections {
        target: Music

        function onSectionChanged() {
            if (panel.shown && panel.wanted)
                sectionMorphTimer.restart();
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

    function formatTime(seconds) {
        const t = Math.max(0, Math.floor(seconds));
        return Math.floor(t / 60) + ":" + String(t % 60).padStart(2, "0");
    }

    // Cor dominante (mais viva) da capa, para o brilho
    ColorQuantizer {
        id: quant

        source: Music.artFile
        depth: 2
        rescaleSize: 64
    }

    readonly property color albumColor: {
        let best = Theme.accent;
        let bestScore = -1;
        for (let i = 0; i < quant.colors.length; ++i) {
            const c = quant.colors[i];
            const mx = Math.max(c.r, c.g, c.b);
            const mn = Math.min(c.r, c.g, c.b);
            const sat = mx <= 0 ? 0 : (mx - mn) / mx;
            const score = sat * (0.35 + 0.65 * mx);
            if (score > bestScore) {
                bestScore = score;
                best = c;
            }
        }
        return best;
    }

    component SectionButton: Rectangle {
        id: sectionButton

        property string glyph: ""
        property bool active: false

        signal activated()

        implicitWidth: 30
        implicitHeight: 30
        radius: 9
        color: sectionButton.active
               ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
               : (sectionArea.containsMouse ? Theme.surfaceHover : "transparent")
        border.width: 1
        border.color: sectionButton.active ? Theme.accent
                    : (sectionArea.containsMouse ? Theme.border : "transparent")

        Behavior on color {
            ColorAnimation { duration: 120 }
        }
        Behavior on border.color {
            ColorAnimation { duration: 120 }
        }

        Text {
            anchors.centerIn: parent
            text: sectionButton.glyph
            color: sectionButton.active ? Theme.accent : Theme.foreground
            font.family: Theme.iconFont
            font.pixelSize: 14
        }

        MouseArea {
            id: sectionArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: sectionButton.activated()
        }
    }

    component ControlButton: Rectangle {
        id: button

        property string glyph: ""
        property int buttonSize: 38
        property int glyphSize: 17

        signal activated()

        width: buttonSize
        height: buttonSize
        radius: buttonSize / 2
        color: buttonArea.containsMouse ? Theme.surfaceHover : "transparent"
        border.width: 1
        border.color: buttonArea.containsMouse ? Theme.border : "transparent"

        Text {
            anchors.centerIn: parent
            text: button.glyph
            color: Theme.foreground
            font.family: Theme.iconFont
            font.pixelSize: button.glyphSize
        }

        MouseArea {
            id: buttonArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.activated()
        }
    }

    Rectangle {
        id: frame

        // Hover do painel (precisa estar num Item; no PopupWindow não funciona)
        HoverHandler {
            onHoveredChanged: Music.panelHovered = hovered
        }

        // Tamanho animado: cresce na abertura e "morfa" na troca de painel
        width: Island.pillWidth
        height: panel.shown ? panel.frameH : 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        implicitHeight: column.height + 24
        clip: true
        radius: Theme.radius
        // Cantos de cima retos: a moldura é a continuação da ilha enquanto
        // está na tela (a ilha só volta a arredondar quando ela recolhe).
        topLeftRadius: 0
        topRightRadius: 0
        color: Theme.surface
        border.width: 1
        border.color: Theme.border

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
            id: column

            // Tamanho fixo no valor final (a moldura encolhe por cima, com clip)
            anchors {
                top: parent.top
                horizontalCenter: parent.horizontalCenter
                topMargin: 12
            }
            width: panel.fullW - 24
            height: implicitHeight
            // Some antes da moldura virar um resto fino (sem sobra na ilha)
            opacity: panel.frameH < 120 ? 0 : 1
            spacing: 8

            Behavior on opacity {
                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
            }

            // ---- cabeçalho: capa com brilho + infos ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Item {
                    implicitWidth: 80
                    implicitHeight: 80

                    // brilho na cor do álbum
                    Shape {
                        anchors.centerIn: parent
                        width: 210
                        height: 210
                        opacity: 0.9

                        ShapePath {
                            strokeColor: "transparent"

                            fillGradient: RadialGradient {
                                centerX: 105
                                centerY: 105
                                centerRadius: 105
                                focalX: 105
                                focalY: 105

                                GradientStop {
                                    position: 0.0
                                    color: Qt.rgba(panel.albumColor.r, panel.albumColor.g, panel.albumColor.b, 0.75)
                                }
                                GradientStop {
                                    position: 0.42
                                    color: Qt.rgba(panel.albumColor.r, panel.albumColor.g, panel.albumColor.b, 0.4)
                                }
                                GradientStop {
                                    position: 0.75
                                    color: Qt.rgba(panel.albumColor.r, panel.albumColor.g, panel.albumColor.b, 0.12)
                                }
                                GradientStop {
                                    position: 1.0
                                    color: Qt.rgba(panel.albumColor.r, panel.albumColor.g, panel.albumColor.b, 0.0)
                                }
                            }

                            PathAngleArc {
                                centerX: 105
                                centerY: 105
                                radiusX: 105
                                radiusY: 105
                                startAngle: 0
                                sweepAngle: 360
                            }
                        }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 80
                        height: 80
                        radius: 12
                        color: Theme.surfaceHover
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: Music.artUrl
                            sourceSize: Qt.size(192, 192)
                            smooth: true
                            fillMode: Image.PreserveAspectCrop
                            visible: status === Image.Ready
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    Text {
                        Layout.fillWidth: true
                        text: Music.title !== "" ? Music.title : "—"
                        color: Theme.foreground
                        font.family: Theme.musicFontFamily
                        font.pixelSize: 16
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: Music.artist
                        color: panel.albumColor
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: Music.album
                        color: Theme.foregroundDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }
            }

            // ---- progresso ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: panel.formatTime(Music.livePosition)
                    color: Theme.foregroundDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }

                LevelSlider {
                    Layout.fillWidth: true
                    value: Music.progress
                    accent: panel.albumColor
                    onMoved: (v) => Music.seekTo(v)
                }

                Text {
                    text: panel.formatTime(Music.length)
                    color: Theme.foregroundDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }
            }

            // ---- controles (ícones das seções em volta, na mesma linha) ----
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 46
                spacing: 6

                // mixer: ícone vira alto-falante e o slider aparece ao lado
                SectionButton {
                    Layout.alignment: Qt.AlignVCenter
                    glyph: Music.section === 1 ? "\u{F057E}" : "\u{F066A}" // volume-high / tune (mixer)
                    active: Music.section === 1
                    onActivated: Music.section = Music.section === 1 ? -1 : 1
                }

                LevelSlider {
                    id: mixSlider

                    Layout.alignment: Qt.AlignVCenter
                    // Uma única animação (0..1) guia largura, opacidade e visibilidade
                    property real openness: Music.section === 1 ? 1 : 0
                    // 100px: precisa caber nos 396px úteis da linha (com os demais
                    // itens e espaçamentos). Se estourar, o layout cresce e arrasta
                    // a barra de progresso junto.
                    Layout.preferredWidth: 100 * openness
                    visible: openness > 0.01
                    opacity: openness
                    value: Music.player && Music.player.volumeSupported ? Music.player.volume : 0
                    onMoved: (v) => {
                        if (Music.player && Music.player.volumeSupported)
                            Music.player.volume = v;
                    }

                    Behavior on openness {
                        NumberAnimation { duration: 260; easing.type: Easing.InOutCubic }
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 26 * mixSlider.openness
                    visible: mixSlider.openness > 0.01
                    opacity: mixSlider.openness
                    text: Music.player && Music.player.volumeSupported
                          ? Math.round(Music.player.volume * 100) + "%" : ""
                    color: Theme.foregroundDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }

                Item { Layout.fillWidth: true }

                ControlButton {
                    Layout.alignment: Qt.AlignVCenter
                    glyph: "\u{F04AE}" // nf-md-skip_previous
                    glyphSize: 19
                    onActivated: if (Music.canPrev) Music.player.previous()
                }

                ControlButton {
                    Layout.alignment: Qt.AlignVCenter
                    glyph: Music.playing ? "\u{F03E4}" : "\u{F040A}" // pause / play
                    buttonSize: 46
                    glyphSize: 21
                    onActivated: if (Music.canToggle) Music.player.togglePlaying()
                }

                ControlButton {
                    Layout.alignment: Qt.AlignVCenter
                    glyph: "\u{F04AD}" // nf-md-skip_next
                    glyphSize: 19
                    onActivated: if (Music.canNext) Music.player.next()
                }

                Item { Layout.fillWidth: true }

                // saída e letras à direita do player
                SectionButton {
                    Layout.alignment: Qt.AlignVCenter
                    glyph: "\u{F04C3}" // nf-md-speaker (saída)
                    active: Music.section === 0
                    onActivated: Music.section = Music.section === 0 ? -1 : 0
                }

                SectionButton {
                    Layout.alignment: Qt.AlignVCenter
                    glyph: "\u{F021A}" // nf-md-text_box (letras)
                    active: Music.section === 2
                    onActivated: Music.section = Music.section === 2 ? -1 : 2
                }
            }

            // ---- saída de áudio ----
            ColumnLayout {
                visible: Music.section === 0

                Layout.fillWidth: true
                Layout.preferredHeight: 114
                spacing: 4

                Text {
                    text: I18n.tr("output")
                    color: Theme.foregroundDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: 96

                    Flow {
                        id: deviceFlow

                        width: parent.width
                        spacing: 6

                        Repeater {
                            model: panel.sinks

                            delegate: Rectangle {
                                id: deviceChip

                                required property var modelData

                                readonly property bool current: Pipewire.defaultAudioSink === modelData

                                implicitWidth: deviceRow.implicitWidth + 24
                                implicitHeight: 26
                                radius: 13
                                color: deviceChip.current
                                       ? Theme.accent
                                       : (deviceArea.containsMouse
                                          ? Qt.lighter(Theme.surfaceHover, 1.35)
                                          : Theme.surfaceHover)
                                border.width: 1
                                border.color: deviceChip.current
                                              ? Theme.accent
                                              : (deviceArea.containsMouse ? Theme.border : "transparent")

                                Behavior on color {
                                    ColorAnimation { duration: 120 }
                                }
                                Behavior on border.color {
                                    ColorAnimation { duration: 120 }
                                }

                                Row {
                                    id: deviceRow

                                    anchors.centerIn: parent
                                    spacing: 6

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: deviceChip.current
                                        text: "\u{F012C}" // check
                                        color: Theme.accentInk
                                        font.family: Theme.iconFont
                                        font.pixelSize: 12
                                    }

                                    Text {
                                        id: deviceLabel

                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Math.min(implicitWidth, 300)
                                        text: modelData.description !== "" ? modelData.description : modelData.name
                                        color: deviceChip.current ? Theme.accentInk : Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        font.weight: deviceChip.current ? Font.Medium : Font.Normal
                                        elide: Text.ElideRight
                                    }
                                }

                                MouseArea {
                                    id: deviceArea

                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Pipewire.preferredDefaultAudioSink = modelData
                                }
                            }
                        }
                    }
                }
            }

            // ---- letras ----
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 127
                spacing: 4
                visible: Music.section === 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: I18n.tr("lyrics")
                        color: Theme.foregroundDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        visible: Music.lyricsLoading
                        text: I18n.tr("loading")
                        color: Theme.foregroundDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }

                    Text {
                        visible: !Music.lyricsLoading && Music.lyricsStatus === "notfound"
                        text: I18n.tr("notFound")
                        color: Theme.foregroundDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }
                }

                Flickable {
                    id: lyricsFlick

                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(105, lyricsCol.implicitHeight)
                    contentHeight: lyricsCol.implicitHeight
                    clip: true
                    interactive: contentHeight > height

                    Behavior on contentY {
                        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                    }

                    // rola para a linha atual (letras sincronizadas)
                    onContentYChanged: scrollTarget = -1
                    property real scrollTarget: -1

                    Column {
                        id: lyricsCol

                        width: lyricsFlick.width
                        spacing: 2

                        // sincronizada: linha atual destacada
                        Repeater {
                            model: Music.lyricsSynced ? Music.lyricsLines : []

                            delegate: Text {
                                required property var modelData
                                required property int index

                                width: lyricsCol.width
                                text: modelData.text
                                color: index === Music.currentLyricIndex ? Theme.accent : Theme.foregroundDim
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.bold: index === Music.currentLyricIndex
                                wrapMode: Text.WordWrap

                                Behavior on color {
                                    ColorAnimation { duration: 180 }
                                }
                            }
                        }

                        // simples
                        Text {
                            visible: !Music.lyricsSynced && Music.lyricsText !== ""
                            width: lyricsCol.width
                            text: Music.lyricsText
                            color: Theme.foregroundDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }
                    }

                    // acompanha a linha atual
                    Connections {
                        target: Music

                        function onCurrentLyricIndexChanged() {
                            if (!Music.lyricsSynced || Music.currentLyricIndex < 0)
                                return;
                            const item = lyricsCol.children[Music.currentLyricIndex];
                            if (item)
                                lyricsFlick.contentY = Math.max(0, Math.min(
                                    lyricsFlick.contentHeight - lyricsFlick.height,
                                    item.y - lyricsFlick.height / 2 + item.height / 2));
                        }
                    }
                }
            }
        }
    }
}
