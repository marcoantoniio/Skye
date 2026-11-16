// Lógica compartilhada do morph dos painéis: abertura, troca entre painéis e
// recolhimento. Cada painel só informa quando quer aparecer e o tamanho final;
// a moldura e o estado global da ilha ficam aqui.

import Quickshell
import QtQuick
import qs.services

QtObject {
    id: root

    property bool wanted: false
    property real fullW: 0
    property real fullH: 0

    property bool shown: false
    property real frameW: root.fullW
    property real frameH: 0
    property bool switchMorph: false

    property NumberAnimation morphW: NumberAnimation {
        target: root
        property: "frameW"
        duration: 400
        easing.type: Easing.OutCubic
    }

    property NumberAnimation morphH: NumberAnimation {
        target: root
        property: "frameH"
        duration: 400
        easing.type: Easing.OutCubic
    }

    property Timer hideDelay: Timer {
        interval: 440
        onTriggered: {
            if (!root.wanted && root.shown) {
                Island.panelsShown -= 1;
                root.shown = false;
            }
        }
    }

    property Connections switchConn: Connections {
        target: Island

        function onSwitchSeqChanged() {
            if (!root.shown || root.wanted)
                return;
            // Troca: este painel sai NA HORA — o que entra já nasce no mesmo
            // tamanho e se transforma. Nunca há duas janelas juntas.
            root.switchMorph = true;
            Island.panelsShown -= 1;
            root.shown = false;
        }
    }

    Component.onCompleted: if (root.wanted) root.openNow()

    onWantedChanged: {
        if (root.wanted) {
            root.openNow();
        } else if (root.shown) {
            // Guarda o tamanho atual para a próxima troca começar daqui
            Island.lastPanelWidth = root.frameW;
            Island.lastPanelHeight = root.frameH;
            Qt.callLater(function() {
                if (root.wanted || !root.shown)
                    return;
                if (root.switchMorph) {
                    // A troca já disparou o morph + o hide (switchConn)
                    root.switchMorph = false;
                } else {
                    // Fechou: recolhe para a ilha
                    root.morphW.stop();
                    root.morphH.stop();
                    root.morphH.from = root.frameH;
                    root.morphH.to = 0;
                    root.morphH.start();
                    root.hideDelay.restart();
                }
            });
        }
    }

    function openNow() {
        if (!root.shown) {
            const switching = Island.panelsShown > 0;
            Island.panelsShown += 1;
            root.switchMorph = false;
            root.morphW.stop();
            root.morphH.stop();
            if (switching) {
                // Troca: nasce no tamanho do painel antigo e morfa até o seu
                root.frameW = Island.lastPanelWidth > 0 ? Island.lastPanelWidth : root.fullW;
                root.frameH = Island.lastPanelHeight > 0 ? Island.lastPanelHeight : root.fullH;
                Island.switchTargetWidth = root.fullW;
                Island.switchTargetHeight = root.fullH;
                // Avisa quem está saindo para acompanhar o morph agora
                Island.switchSeq += 1;
            } else {
                // Abertura normal: cresce de 0 (saindo da ilha)
                root.frameW = root.fullW;
                root.frameH = 0;
            }
            root.shown = true;
            root.morphW.from = root.frameW;
            root.morphW.to = root.fullW;
            root.morphH.from = root.frameH;
            root.morphH.to = root.fullH;
            root.morphW.start();
            root.morphH.start();
        } else {
            // Reabriu durante a saída: volta ao tamanho final
            root.morphW.stop();
            root.morphH.stop();
            root.morphW.from = root.frameW;
            root.morphW.to = root.fullW;
            root.morphH.from = root.frameH;
            root.morphH.to = root.fullH;
            root.morphW.start();
            root.morphH.start();
        }
    }

    // Conteúdo mudou de altura com o painel aberto (ex.: seções da música).
    function remorphH() {
        if (!root.shown || !root.wanted)
            return;
        root.morphH.stop();
        root.morphH.from = root.frameH;
        root.morphH.to = root.fullH;
        root.morphH.start();
    }
}
