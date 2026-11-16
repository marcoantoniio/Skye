pragma Singleton

// Fachada de compatibilidade para as preferências dos agentes. A fonte de
// verdade agora é Settings.qml; este singleton mantém a API antiga (e o IPC
// `agent`) funcionando.
//
// IPC: qs -c skye ipc call agent setReadout elapsed|tokens|cost
//      qs -c skye ipc call agent cycleReadout
//      qs -c skye ipc call agent setFinishMin 10

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property string readout: Settings.readout
    readonly property int finishMin: Settings.finishMin
    readonly property bool finishNotice: Settings.finishNotice
    readonly property bool loaded: Settings.loaded

    function setReadout(value) {
        Settings.setReadout(value);
    }

    function cycleReadout() {
        Settings.cycleReadout();
    }

    function readoutLabel() {
        if (Settings.readout === "tokens")
            return I18n.tr("ocReadoutTokens");
        if (Settings.readout === "cost")
            return I18n.tr("ocReadoutCost");
        return I18n.tr("ocReadoutElapsed");
    }

    function setFinishMin(value) {
        Settings.setFinishMin(value);
    }

    function setFinishNotice(value) {
        Settings.setFinishNotice(value);
    }

    IpcHandler {
        target: "agent"

        function setReadout(value: string): void { root.setReadout(value); }
        function getReadout(): string { return root.readout; }
        function cycleReadout(): void { root.cycleReadout(); }
        function setFinishMin(value: int): void { root.setFinishMin(value); }
        function getFinishMin(): int { return root.finishMin; }
        function setFinishNotice(value: bool): void { root.setFinishNotice(value); }
        function getFinishNotice(): bool { return root.finishNotice; }
    }
}
