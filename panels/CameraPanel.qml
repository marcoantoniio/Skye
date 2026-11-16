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
import qs.services
import qs.widgets

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
    // Sempre mapeada (pré-mapeada) — a moldura em 0 é que a esconde
    visible: true

    MorphPanel {
        id: morph
        wanted: Webcam.open && onCameraScreen
            && !ControlCenter.open && !Notifications.centerOpen && !Music.panelOpen
        fullW: panel.panelWidth
        fullH: Math.min(Theme.panelMorphHeight, frame.implicitHeight)
    }

    // Bar.qml consulta/zera o estado ao descarregar a janela sob demanda.
    property alias shown: morph.shown

    Connections {
        target: morph

        function onShownChanged() {
            if (morph.shown)
                panel.pickCamera();
        }
    }

    // Escolhe a câmera quando a lista assíncrona do MediaDevices chega (ou muda)
    function pickCamera(): void {
        if (!visible)
            return;
        if (selectedDevice === null || cameras.indexOf(selectedDevice) === -1)
            selectedDevice = cameras.length > 0 ? cameras[0] : null;
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
                active: morph.shown

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

        active: morph.shown
        sourceComponent: sessionComp
    }

    Rectangle {
        id: frame

        // Tamanho animado: cresce na abertura e "morfa" na troca de painel
        width: Island.pillWidth
        height: morph.shown ? morph.frameH : 0
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
            width: morph.fullW - 24
            height: morph.fullH - 24
            // Some antes da moldura virar um resto fino (sem sobra na ilha)
            opacity: morph.frameH < 120 ? 0 : 1

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
                    active: morph.shown
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
