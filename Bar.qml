// Barra flutuante em pílula, no monitor principal (Theme.barScreenName).
//
// Comportamento (igual ao shell original):
// - Idle: só o relógio.
// - Hover: a pílula expande com animação e revela os elementos laterais.
// - Esquerda: dots de workspace + sino.
// - Direita: botões circulares coloridos (categorias de notificação).
// - A bandeja do sistema fica no rodapé do painel de notificações.
//
// Técnica: o PanelWindow ocupa a largura toda (com margens), mas a pílula
// interna tem só a largura do conteúdo. O `mask` faz os cliques fora da
// pílula passarem direto para as janelas de baixo.

import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.panels
import qs.services
import qs.widgets

PanelWindow {
    id: bar

    required property var modelData
    screen: modelData

    anchors {
        top: true
        left: true
        right: true
    }
    margins {
        // sem margem em cima: a pílula é que se posiciona (colada no topo no
        // formato quadrado, ou com a margem no formato arredondado)
        top: 0
        left: Theme.barMargin
        right: Theme.barMargin
    }
    implicitHeight: Theme.barHeight + Theme.barMargin
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    aboveWindows: true

    property bool expanded: false

    // Pequeno atraso ao sair, para não colapsar por tremor de borda
    Timer {
        id: collapseTimer
        // Mesmo atraso dos timers de fechamento: o recolhimento da ilha começa
        // junto com o fechamento do painel (tudo vira uma coisa só).
        interval: 350
        onTriggered: {
            bar.expanded = false;
            // fallback: se o mouse saiu de tudo, o painel do ar fecha junto
            if (Midea.panelOpen && !Midea.panelHovered)
                Midea.panelOpen = false;
        }
    }

    // Painel de música: fecha com atraso quando o mouse sai da ilha/painel
    Timer {
        id: musicCloseTimer
        interval: 350
        onTriggered: if (!Music.panelHovered && !Island.hovered) Music.panelOpen = false
    }

    // Control Center: fecha quando o mouse sai da ilha e do painel
    Timer {
        id: controlCenterCloseTimer

        interval: 350
        onTriggered: {
            if (ControlCenter.open && !ControlCenter.panelHovered
                    && !Island.hovered && !ControlCenter.deviceMenuOpen
                    && !ControlCenter.vpnMenuHovered)
                ControlCenter.close();
        }
    }

    // Recentes e Notificações: mesmo comportamento
    Timer {
        id: recentCloseTimer

        interval: 350
        onTriggered: if (RecentFiles.open && !RecentFiles.panelHovered && !Island.hovered)
                         RecentFiles.close()
    }

    Timer {
        id: notificationsCloseTimer

        interval: 350
        onTriggered: if (Notifications.centerOpen && !Notifications.panelHovered
                         && !Island.hovered && !Notifications.menuOpen)
                         Notifications.centerOpen = false
    }

    // Painel do ar-condicionado: fecha quando o mouse sai da ilha e do painel
    Timer {
        id: acCloseTimer

        interval: 350
        onTriggered: if (Midea.panelOpen && !Midea.panelHovered && !Island.hovered)
                         Midea.panelOpen = false
    }

    Connections {
        target: Music

        function onPanelHoveredChanged() {
            if (!Music.panelHovered && !barHover.hovered)
                musicCloseTimer.restart();
        }
    }

    Connections {
        target: ControlCenter

        function onPanelHoveredChanged() {
            if (!ControlCenter.panelHovered && !Island.hovered)
                controlCenterCloseTimer.restart();
        }

        // ao fechar o menu de dispositivos, reavalia (fecha se o mouse saiu)
        function onDeviceMenuOpenChanged() {
            if (!ControlCenter.deviceMenuOpen && !Island.hovered)
                controlCenterCloseTimer.restart();
        }

        // mesmo para o menu de VPNs
        function onVpnMenuOpenChanged() {
            if (!ControlCenter.vpnMenuOpen && !Island.hovered)
                controlCenterCloseTimer.restart();
        }

        // e quando o mouse sai do menu de VPNs, reavalia o fechamento
        function onVpnMenuHoveredChanged() {
            if (!ControlCenter.vpnMenuHovered && !ControlCenter.panelHovered && !Island.hovered)
                controlCenterCloseTimer.restart();
        }
    }

    Connections {
        target: RecentFiles

        function onPanelHoveredChanged() {
            if (!RecentFiles.panelHovered && !Island.hovered)
                recentCloseTimer.restart();
        }
    }

    Connections {
        target: Notifications

        function onPanelHoveredChanged() {
            if (!Notifications.panelHovered && !Island.hovered)
                notificationsCloseTimer.restart();
        }

        // ao fechar o menu da bandeja, reavalia (fecha se o mouse saiu)
        function onMenuOpenChanged() {
            if (!Notifications.menuOpen && !Island.hovered)
                notificationsCloseTimer.restart();
        }
    }

    Connections {
        target: Midea

        function onPanelHoveredChanged() {
            if (!Midea.panelHovered && !Island.hovered)
                acCloseTimer.restart();
        }
    }

    Rectangle {
        id: pill

        anchors.horizontalCenter: parent.horizontalCenter
        // no formato quadrado sobe 1px: a borda de cima fica fora da tela e o
        // preenchimento escuro encosta no topo de verdade (sem a linha clara)
        y: Island.square ? -1 : Theme.barMargin
        height: Theme.barHeight
        radius: Island.square ? 0 : Theme.barRadius
        // A ilha é 100% opaca (0% de transparência)
        color: Theme.backgroundTop
        border.width: 1
        border.color: Theme.border
        clip: true

        Behavior on y {
            NumberAnimation { duration: 260; easing.type: Easing.OutQuint }
        }
        Behavior on radius {
            NumberAnimation { duration: 260; easing.type: Easing.OutQuint }
        }

        // 0 = colapsado, 1 = expandido (animado)
        property real reveal: bar.expanded ? 1 : 0

        Behavior on reveal {
            // Mesmo tempo/curva do fechamento do painel: a ilha recolhe junto
            NumberAnimation {
                duration: 400
                easing.type: Easing.OutCubic
            }
        }

        // Largura simétrica: os dois lados usam a largura do cluster maior,
        // mantendo o relógio centralizado e sem encostar nos botões.
        readonly property real sideWidth: Math.max(leftRow.implicitWidth, rightRow.implicitWidth)

        // Largura base da pílula (relógio + padding; no quadrado, o mínimo fixo)
        readonly property real baseWidth: Island.square
            ? Math.max(Theme.pillIdleWidth, centerWidth + Theme.pillPadding * 2)
            : centerWidth + Theme.pillPadding * 2

        // Quando um painel está aberto, a ilha cresce até a largura dele
        // e encosta no painel (cantos de baixo retos).
        readonly property real panelTargetWidth: ControlCenter.open
            ? Theme.controlCenterPanelWidth
            : (Notifications.centerOpen ? Theme.notificationPanelWidth
            : (Music.panelOpen ? Theme.musicPanelWidth
            : (RecentFiles.open ? Theme.recentPanelWidth
            : (Midea.panelOpen ? Theme.acPanelWidth
            : (Webcam.open && bar.screen === Webcam.screen ? Theme.cameraPanelWidth : baseWidth)))))

        // Parte da largura visível atual (hover incluso): ao abrir um painel a
        // largura cresce JUNTO com a altura. Antes o max() segurava a largura
        // no tamanho da ilha e o crescimento lateral só aparecia no fim da
        // animação (parecia "desce e depois abre").
        property real animatedPanelWidth: Math.max(panelTargetWidth,
            baseWidth + reveal * (sideWidth * 2 + Theme.spacing * 2))

        Behavior on animatedPanelWidth {
            // Mesmo tempo/curva do morph dos painéis: a ilha encolhe junto com
            // o fechamento do painel (não antes).
            NumberAnimation {
                duration: 400
                easing.type: Easing.OutCubic
            }
        }

        // Item central: volume (OSD) > gravação > timer > clipboard > música > relógio
        readonly property string centerMode: Audio.osdVisible ? "volume"
            : Recorder.recording ? "rec"
            : TimerService.messageVisible ? "timer"
            : Clipboard.feedbackVisible ? "clipboard"
            : ((Music.playing || (Music.panelOpen && Music.active)) ? "music" : "clock")

        readonly property real centerWidth: centerMode === "volume" ? volumeOsd.implicitWidth
            : centerMode === "rec" ? recIndicator.implicitWidth
            : centerMode === "timer" ? timerNotice.implicitWidth
            : centerMode === "clipboard" ? clipNotice.implicitWidth
            : centerMode === "music" ? nowPlaying.implicitWidth
            : clockItem.implicitWidth

        // parada: a largura base; o hover soma os elementos laterais. Quando um
        // painel está aberto, a largura dele domina (e anima junto com ele).
        width: Math.max(baseWidth + reveal * (sideWidth * 2 + Theme.spacing * 2),
                        animatedPanelWidth)

        // Cantos de baixo: retos enquanto há painel na tela (aberto ou
        // colapsando junto — a moldura segue embaixo como peça única, sem
        // degrau quadrado); arredondam quando o painel termina de recolher.
        bottomLeftRadius: (panelTargetWidth > baseWidth || Island.panelsShown > 0 || Island.square)
            ? 0 : Theme.barRadius
        bottomRightRadius: (panelTargetWidth > baseWidth || Island.panelsShown > 0 || Island.square)
            ? 0 : Theme.barRadius

        Behavior on bottomLeftRadius {
            NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
        }
        Behavior on bottomRightRadius {
            NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
        }

        HoverHandler {
            id: barHover

            onHoveredChanged: {
                Island.hovered = barHover.hovered;
                if (barHover.hovered) {
                    collapseTimer.stop();
                    bar.expanded = true;
                    musicCloseTimer.stop();
                    controlCenterCloseTimer.stop();
                    recentCloseTimer.stop();
                    notificationsCloseTimer.stop();
                    acCloseTimer.stop();
                } else {
                    collapseTimer.start();
                    musicCloseTimer.start();
                    controlCenterCloseTimer.start();
                    recentCloseTimer.start();
                    notificationsCloseTimer.start();
                    acCloseTimer.start();
                }
            }
        }

        // ---- esquerda: dots de workspace + sino ----
        Item {
            id: leftWrap

            width: pill.sideWidth
            height: Theme.barHeight
            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
                leftMargin: Theme.pillPadding - (1 - pill.reveal) * width
            }
            opacity: pill.reveal

            Row {
                id: leftRow

                anchors {
                    horizontalCenter: parent.horizontalCenter
                    verticalCenter: parent.verticalCenter
                }
                spacing: 8

                WorkspacePills {}

                Bell {}
            }
        }

        // ---- centro: relógio, gravação, volume ou música ----
        Clock {
            id: clockItem
            anchors.centerIn: parent
            visible: pill.centerMode === "clock"
        }

        RecordingIndicator {
            id: recIndicator
            anchors.centerIn: parent
            visible: pill.centerMode === "rec"
        }

        VolumeOsd {
            id: volumeOsd
            anchors.centerIn: parent
            visible: pill.centerMode === "volume"
        }

        NowPlaying {
            id: nowPlaying
            anchors.centerIn: parent
            visible: pill.centerMode === "music"
        }

        // Zona de descanso sobre a música: o painel só abre se o mouse PARAR
        // aqui ~200ms. Passar reto por cima (ex.: indo clicar nas bolinhas de
        // workspace) não abre; as laterais também não abrem nada.
        Item {
            id: musicHoverZone

            anchors.centerIn: parent
            width: nowPlaying.width
            height: nowPlaying.height
            // Só reage com a ilha já totalmente expandida: durante a animação
            // tudo está deslizando e cliques nas bolinhas/áreas vizinhas
            // acabavam caindo aqui (o painel dava uma aparecida).
            enabled: pill.centerMode === "music" && pill.reveal >= 1

            MouseArea {
                id: dwellArea

                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton

                // Clicar na música volta pro modo de música: fecha o painel
                // que estiver aberto (ex.: Control Center) e abre o de música.
                onClicked: {
                    if (Music.playing && !Webcam.open) {
                        ControlCenter.close();
                        Notifications.centerOpen = false;
                        RecentFiles.close();
                        Midea.panelOpen = false;
                        Music.panelOpen = true;
                    }
                }

                Timer {
                    id: musicDwell
                    interval: 200
                    onTriggered: {
                        if (dwellArea.containsMouse && Music.playing && !ControlCenter.open
                                && !Notifications.centerOpen && !Webcam.open && !Midea.panelOpen)
                            Music.panelOpen = true;
                    }
                }

                onContainsMouseChanged: {
                    if (containsMouse)
                        musicDwell.restart();
                    else
                        musicDwell.stop();
                }
                onPositionChanged: musicDwell.restart()
            }
        }

        TimerNotice {
            id: timerNotice
            anchors.centerIn: parent
            visible: pill.centerMode === "timer"
        }

        ClipboardNotice {
            id: clipNotice
            anchors.centerIn: parent
            visible: pill.centerMode === "clipboard"
        }

        // ---- direita: botões de categoria ----
        Item {
            id: rightWrap

            width: pill.sideWidth
            height: Theme.barHeight
            anchors {
                right: parent.right
                verticalCenter: parent.verticalCenter
                rightMargin: Theme.pillPadding - (1 - pill.reveal) * width
            }
            opacity: pill.reveal

            Row {
                id: rightRow

                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                // espaço maior entre as bolinhas e o ar (equilibra o grupo)
                spacing: 14

                // Bolinhas centralizadas na altura da linha (o botão do ar
                // tem 26px; sem o wrapper elas ficariam no topo)
                Item {
                    width: dotsRow.implicitWidth
                    height: 26

                    CategoryButtons {
                        id: dotsRow

                        anchors.centerIn: parent
                    }
                }

                AcButton {
                    id: acButton

                    onActivated: {
                        if (Midea.panelOpen) {
                            Midea.panelOpen = false;
                        } else {
                            ControlCenter.close();
                            Notifications.centerOpen = false;
                            RecentFiles.close();
                            Music.panelOpen = false;
                            Webcam.open = false;
                            Midea.panelOpen = true;
                        }
                    }
                }
            }
        }
    }

    // Largura atual da pílula, compartilhada com os painéis: a moldura deles
    // acompanha a ilha (abre e fecha colapsando junto com ela).
    Binding {
        target: Island
        property: "pillWidth"
        value: pill.width
    }

    // Só a pílula recebe cliques; o resto da faixa é click-through
    mask: Region {
        item: pill
    }

    // Caffeine: associado à janela da barra, ativo enquanto ligado no
    // Control Center (ou via IPC).
    IdleInhibitor {
        window: bar
        enabled: ControlCenter.caffeineEnabled
    }

    NotificationPopups {
        panelWindow: bar
    }

    // Central de notificações: janela sob demanda. O hover no sino/bolinha
    // laranja pré-carrega — o clique já abre com a janela mapeada, sem blink.
    property var notificationCenterPanel: null

    Component {
        id: notificationCenterComp

        NotificationCenter {
            panelWindow: bar
            anchorItem: pill
        }
    }

    function ensureNotificationCenter() {
        if (bar.notificationCenterPanel === null)
            bar.notificationCenterPanel = notificationCenterComp.createObject(bar);
    }

    Connections {
        target: Notifications

        function onCenterOpenChanged() {
            if (Notifications.centerOpen) {
                notificationUnload.stop();
                bar.ensureNotificationCenter();
            } else if (bar.notificationCenterPanel !== null) {
                notificationUnload.restart();
            }
        }

        function onTriggerHoveredChanged() {
            if (Notifications.triggerHovered) {
                notificationUnload.stop();
                bar.ensureNotificationCenter();
            } else if (bar.notificationCenterPanel !== null && !Notifications.centerOpen) {
                notificationUnload.restart();
            }
        }
    }

    Timer {
        id: notificationUnload

        interval: 1000
        onTriggered: {
            if (bar.notificationCenterPanel !== null && !Notifications.centerOpen
                    && !Notifications.triggerHovered) {
                if (bar.notificationCenterPanel.shown) {
                    Island.panelsShown -= 1;
                    bar.notificationCenterPanel.shown = false;
                }
                bar.notificationCenterPanel.destroy();
                bar.notificationCenterPanel = null;
            }
        }
    }

    ControlCenterPanel {
        panelWindow: bar
        anchorItem: pill
    }

    MusicPanel {
        panelWindow: bar
        anchorItem: pill
    }

    // Câmera: janela criada só quando usada e destruída depois do morph de
    // fechamento — é o painel mais pesado (stack de mídia) e o menos usado.
    property var cameraPanel: null

    Component {
        id: cameraPanelComp

        CameraPanel {
            panelWindow: bar
            anchorItem: pill
        }
    }

    Connections {
        target: Webcam

        function onOpenChanged() {
            if (Webcam.open) {
                cameraUnload.stop();
                if (bar.cameraPanel === null && bar.screen === Webcam.screen)
                    bar.cameraPanel = cameraPanelComp.createObject(bar);
            } else if (bar.cameraPanel !== null) {
                cameraUnload.restart();
            }
        }
    }

    Timer {
        id: cameraUnload

        interval: 1000
        onTriggered: {
            if (bar.cameraPanel !== null && !Webcam.open) {
                // se o morph de fechamento não terminou, corrige a contagem
                // global antes de destruir a janela
                if (bar.cameraPanel.shown) {
                    Island.panelsShown -= 1;
                    bar.cameraPanel.shown = false;
                }
                bar.cameraPanel.destroy();
                bar.cameraPanel = null;
            }
        }
    }

    // Recentes: mesmo esquema (hover na bolinha ciano pré-carrega).
    property var recentPanel: null

    Component {
        id: recentPanelComp

        RecentFilesPanel {
            panelWindow: bar
            anchorItem: pill
        }
    }

    function ensureRecentPanel() {
        if (bar.recentPanel === null)
            bar.recentPanel = recentPanelComp.createObject(bar);
    }

    Connections {
        target: RecentFiles

        function onOpenChanged() {
            if (RecentFiles.open) {
                recentUnload.stop();
                bar.ensureRecentPanel();
            } else if (bar.recentPanel !== null) {
                recentUnload.restart();
            }
        }

        function onTriggerHoveredChanged() {
            if (RecentFiles.triggerHovered) {
                recentUnload.stop();
                bar.ensureRecentPanel();
            } else if (bar.recentPanel !== null && !RecentFiles.open) {
                recentUnload.restart();
            }
        }
    }

    Timer {
        id: recentUnload

        interval: 1000
        onTriggered: {
            if (bar.recentPanel !== null && !RecentFiles.open
                    && !RecentFiles.triggerHovered) {
                if (bar.recentPanel.shown) {
                    Island.panelsShown -= 1;
                    bar.recentPanel.shown = false;
                }
                bar.recentPanel.destroy();
                bar.recentPanel = null;
            }
        }
    }

    AcPanel {
        panelWindow: bar
        anchorItem: pill
    }
}
