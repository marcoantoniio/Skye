// Painel central de notificações (histórico), ancorado logo abaixo da pílula
// (a "ilha dinâmica"), centralizado com ela.
// - Abas coloridas por categoria (mesmas cores dos botões da barra).
// - Filtra a lista pela categoria ativa.
// Abre/fecha via clique no sino ou:
//   qs -c skye ipc call notifications toggle

import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: center

    property var panelWindow: null

    // Item (a pílula) embaixo do qual o painel deve abrir.
    // Como a pílula é sempre centralizada, o painel fica centralizado na tela.
    property var anchorItem: null

    readonly property int panelWidth: Theme.notificationPanelWidth

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

    // Altura congelada ao abrir: fechar uma notificação (ou chegar nova) não
    // pode mudar a altura da moldura enquanto aberto (glicha e o painel pula).
    property real frozenHeight: 0
    // ---- geometria da moldura (animada) ----
    // Abertura: cresce de 0 até a altura final (saindo da ilha).
    // Troca: a moldura "morfa" do tamanho do painel antigo até o tamanho
    // deste — a janela se transforma, sem fade nem piscar.
    readonly property bool wanted: Notifications.centerOpen
    property bool shown: false
    readonly property real fullW: center.panelWidth
    readonly property real fullH: frozenHeight > 0 ? frozenHeight
        : Math.min(Theme.panelMorphHeight, frame.implicitHeight)
    property real frameW: fullW
    property real frameH: 0

    // Sempre mapeada (pré-mapeada) — a moldura em 0 é que a esconde
    visible: true

    NumberAnimation {
        id: morphW

        target: center
        property: "frameW"
        duration: 400
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: morphH

        target: center
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
            if (!center.shown || center.wanted)
                return;
            // Troca: este painel sai NA HORA — o que entra já nasce no mesmo
            // tamanho e se transforma. Nunca há duas janelas juntas.
            center.switchMorph = true;
            Island.panelsShown -= 1;
            center.shown = false;
        }
    }

    onWantedChanged: {
        if (wanted) {
            if (!shown) {
                const switching = Island.panelsShown > 0;
                Island.panelsShown += 1;
                center.switchMorph = false;
                morphW.stop();
                morphH.stop();
                if (switching) {
                    // Troca: nasce no tamanho do painel antigo e morfa até o seu
                    center.frameW = Island.lastPanelWidth > 0 ? Island.lastPanelWidth : center.fullW;
                    center.frameH = Island.lastPanelHeight > 0 ? Island.lastPanelHeight : center.fullH;
                    Island.switchTargetWidth = center.fullW;
                    Island.switchTargetHeight = center.fullH;
                    // Avisa quem está saindo para acompanhar o morph agora
                    Island.switchSeq += 1;
                } else {
                    // Abertura normal: cresce de 0 (saindo da ilha)
                    center.frameW = center.fullW;
                    center.frameH = 0;
                }
                shown = true;
                morphW.from = center.frameW;
                morphW.to = center.fullW;
                morphH.from = center.frameH;
                morphH.to = center.fullH;
                morphW.start();
                morphH.start();
            } else {
                // Reabriu durante a saída: volta ao tamanho final
                morphW.stop();
                morphH.stop();
                morphW.from = center.frameW;
                morphW.to = center.fullW;
                morphH.from = center.frameH;
                morphH.to = center.fullH;
                morphW.start();
                morphH.start();
            }
        } else if (shown) {
            // Guarda o tamanho atual para a próxima troca começar daqui
            Island.lastPanelWidth = center.frameW;
            Island.lastPanelHeight = center.frameH;
            Qt.callLater(function() {
                if (center.wanted || !center.shown)
                    return;
                if (center.switchMorph) {
                    // A troca já disparou o morph + o hide (Connections)
                    center.switchMorph = false;
                } else {
                    // Fechou: recolhe para a ilha
                    morphW.stop();
                    morphH.stop();
                    morphH.from = center.frameH;
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
            if (!center.wanted && center.shown) {
                Island.panelsShown -= 1;
                center.shown = false;
            }
        }
    }

    onShownChanged: {
        // congela a altura do conteúdo atual (sem mudar a altura enquanto aberto)
        if (shown) {
            frozenHeight = 0;
            Qt.callLater(() => frozenHeight = Math.min(540, frame.implicitHeight));
        }
    }

    Rectangle {
        id: frame

        // Tamanho animado: cresce na abertura e "morfa" na troca de painel
        width: Island.pillWidth
        height: center.shown ? center.frameH : 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        implicitHeight: column.implicitHeight + 24
        clip: true
        radius: Theme.radius
        // Cantos de cima retos: a moldura é a continuação da ilha enquanto
        // está na tela (a ilha só volta a arredondar quando ela recolhe).
        topLeftRadius: 0
        topRightRadius: 0
        color: Theme.surface
        border.width: 1
        border.color: Theme.border

        HoverHandler {
            onHoveredChanged: Notifications.panelHovered = hovered
        }

        // Junção com a ilha: esconde a borda de cima (sem linha divisória)
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
            width: center.fullW - 24
            height: center.fullH - 24
            // Some antes da moldura virar um resto fino (sem sobra na ilha)
            opacity: center.frameH < 120 ? 0 : 1

            Behavior on opacity {
                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
            }
            spacing: 10

            // ---- cabeçalho ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: I18n.tr("notifications")
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    font.bold: true
                }

                Text {
                    visible: Notifications.count > 0
                    text: String(Notifications.count)
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }

                Item { Layout.fillWidth: true }

                Text {
                    visible: Notifications.count > 0
                    text: I18n.tr("clearAll")
                    color: clearArea.containsMouse ? Theme.foreground : Theme.foregroundDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 11

                    MouseArea {
                        id: clearArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Notifications.clearAll()
                    }
                }

                Text {
                    text: "✕"
                    color: closeArea.containsMouse ? Theme.foreground : Theme.foregroundDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 13

                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Notifications.centerOpen = false
                    }
                }
            }

            // ---- abas de categoria ----
            Flickable {
                Layout.fillWidth: true
                implicitHeight: 24
                contentWidth: tabs.implicitWidth
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Row {
                    id: tabs
                    spacing: 6

                    FilterTab {
                        label: I18n.tr("all")
                        tabColor: Theme.accent
                        selected: Notifications.activeCategory === ""
                        onActivated: Notifications.activeCategory = ""
                    }

                    Repeater {
                        model: Notifications.categories

                        delegate: FilterTab {
                            required property var modelData

                            label: modelData.name + " " + modelData.count
                            tabColor: modelData.color
                            selected: Notifications.activeCategory === modelData.name
                            onActivated: Notifications.activeCategory = modelData.name
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.border
            }

            // ---- estado vazio ----
            Text {
                Layout.fillWidth: true
                Layout.fillHeight: true
                verticalAlignment: Text.AlignVCenter
                visible: Notifications.filtered.length === 0
                text: Notifications.activeCategory === ""
                      ? I18n.tr("noNotifications")
                      : I18n.tr("nothingIn") + " \"" + Notifications.activeCategory + "\""
                color: Theme.foregroundDim
                font.family: Theme.fontFamily
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                topPadding: 24
                bottomPadding: 24
            }

            // ---- lista ----
            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: Math.min(400, list.implicitHeight)
                visible: Notifications.filtered.length > 0
                contentHeight: list.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: list
                    width: parent.width
                    spacing: 8

                    Repeater {
                        model: Notifications.filtered

                        delegate: Rectangle {
                            required property var modelData

                            width: list.width
                            implicitHeight: itemColumn.implicitHeight + 20
                            radius: 10
                            color: Theme.card

                            ColumnLayout {
                                id: itemColumn
                                anchors {
                                    fill: parent
                                    margins: 10
                                }
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Rectangle {
                                        width: 6
                                        height: 6
                                        radius: 3
                                        color: Notifications.colorFor(modelData.appName)
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.appName
                                        color: Theme.foregroundDim
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        text: "✕"
                                        color: dismissArea.containsMouse ? Theme.urgent : Theme.foregroundDim
                                        font.pixelSize: 11

                                        MouseArea {
                                            id: dismissArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Notifications.dismiss(modelData)
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.summary
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: modelData.body !== ""
                                    text: modelData.body
                                    textFormat: Text.PlainText
                                    color: Theme.foregroundDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }

            // ---- rodapé: bandeja do sistema (como no original) ----
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.border
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: I18n.tr("systemTray")
                    color: Theme.foregroundDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }

                Item { Layout.fillWidth: true }

                Tray {
                    id: tray

                    onMenuOpenChanged: Notifications.menuOpen = tray.menuOpen
                }
            }
        }
    }
}
