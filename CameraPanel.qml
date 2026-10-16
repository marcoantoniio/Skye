// Painel de teste da câmera: preview ao vivo (QtMultimedia) + escolha do
// dispositivo. Abre pelo botão "Câmera" do Control Center ou por IPC.
//
// A sessão de captura só é criada enquanto o painel está visível (Loader),
// para não segurar a câmera quando fechado.

import Quickshell
import Quickshell.Wayland
import QtMultimedia
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: panel

    property var panelWindow: null
    property var anchorItem: null

    readonly property int panelWidth: Theme.cameraPanelWidth
    readonly property var cameras: mediaDevices.videoInputs

    // Só na tela da câmera (Theme.cameraScreenName) — evita duas instâncias abrindo a câmera
    readonly property bool onCameraScreen: panelWindow !== null && Webcam.screen !== null
        && panelWindow.screen === Webcam.screen

    property var selectedDevice: null
    property string cameraError: ""

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
    readonly property bool wanted: Webcam.open && onCameraScreen
        && !ControlCenter.open && !Notifications.centerOpen && !Music.panelOpen
    property bool shown: false
    readonly property real fullW: panel.panelWidth
    readonly property real fullH: Math.min(Theme.panelMorphHeight, frame.implicitHeight)
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

    // Escolhe a câmera quando a lista assíncrona do MediaDevices chega (ou muda)
    function pickCamera(): void {
        if (!visible)
            return;
        if (selectedDevice === null || cameras.indexOf(selectedDevice) === -1)
            selectedDevice = cameras.length > 0 ? cameras[0] : null;
    }

    onShownChanged: {
        if (shown)
            pickCamera();
    }

    onCamerasChanged: pickCamera()

    MediaDevices {
        id: mediaDevices
    }

    Component {
        id: sessionComp

        CaptureSession {
            camera: Camera {
                cameraDevice: panel.selectedDevice
                active: panel.shown

                onErrorStringChanged: panel.cameraError = errorString
            }

            videoOutput: videoOutLoader.item
        }
    }

    Component {
        id: videoComp

        VideoOutput {
            anchors.fill: parent
            fillMode: VideoOutput.PreserveAspectCrop
        }
    }

    Loader {
        id: sessionLoader

        active: panel.shown
        sourceComponent: sessionComp
    }

    Rectangle {
        id: frame

        // Tamanho animado: cresce na abertura e "morfa" na troca de painel
        width: Island.pillWidth
        height: panel.shown ? panel.frameH : 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        implicitHeight: column.implicitHeight + 24
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

        // Junção com a ilha
        Rectangle {
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                leftMargin: 1
                rightMargin: 1
            }
            height: 1
            color: "#000000"
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
            height: panel.fullH - 24
            // Some antes da moldura virar um resto fino (sem sobra na ilha)
            opacity: panel.frameH < 120 ? 0 : 1

            Behavior on opacity {
                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
            }
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: I18n.tr("camera")
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.bold: true
                }

                Text {
                    visible: panel.cameraError !== ""
                    text: panel.cameraError
                    color: Theme.accentAlt
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.round(width * 9 / 16)
                radius: 10
                color: Theme.card
                clip: true

                Loader {
                    id: videoOutLoader

                    anchors.fill: parent
                    active: panel.shown
                    sourceComponent: videoComp
                }

                Text {
                    anchors.centerIn: parent
                    visible: panel.cameras.length === 0
                    text: I18n.tr("noCamera")
                    color: Theme.foregroundDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
            }

            Item {
                Layout.fillWidth: true
                implicitHeight: camFlow.implicitHeight

                Flow {
                    id: camFlow

                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: panel.cameras

                        delegate: Rectangle {
                            required property var modelData

                            readonly property bool current: panel.selectedDevice === modelData

                            implicitWidth: camLabel.implicitWidth + 22
                            implicitHeight: 24
                            radius: 12
                            color: current
                                   ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                                   : Theme.surfaceHover
                            border.width: 1
                            border.color: current ? Theme.accent : "transparent"

                            Text {
                                id: camLabel

                                anchors.centerIn: parent
                                text: modelData.description !== "" ? modelData.description : modelData.id
                                color: current ? Theme.accent : Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panel.selectedDevice = modelData
                            }
                        }
                    }
                }
            }
        }
    }
}
