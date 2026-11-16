pragma Singleton

// Fonte única de preferências do Skye. Um JSON pequeno em
// ~/.config/skye/settings.json; cada serviço lê daqui em vez de manter
// arquivo próprio. Importa automaticamente o antigo agents.json na primeira
// execução.
//
// IPC: qs -c skye ipc call settings setReadout elapsed|tokens|cost
//      qs -c skye ipc call settings setFinishMin 10
//      qs -c skye ipc call settings setFinishNotice true
//      qs -c skye ipc call settings setFeature camera false

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property bool loaded: false

    // Ilha / agentes
    property string readout: "elapsed" // elapsed | tokens | cost
    property int finishMin: 10         // segundos; 0 mostra qualquer tarefa
    property bool finishNotice: true

    // Módulos que podem ser escondidos da interface. O padrão é tudo ligado.
    property var features: ({
        camera: true,
        recorder: true,
        midea: true,
        discord: true
    })

    readonly property string configFile: Quickshell.env("HOME") + "/.config/skye/settings.json"
    readonly property string legacyFile: Quickshell.env("HOME") + "/.config/skye/agents.json"

    Process {
        id: loadProc

        // settings.json é a fonte; agents.json só serve para a migração.
        command: ["sh", "-c",
            "if [ -f \"$1\" ]; then cat \"$1\"; elif [ -f \"$2\" ]; then cat \"$2\"; fi",
            "sh", root.configFile, root.legacyFile]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                let data = null;
                try {
                    data = JSON.parse(text);
                } catch (e) {
                    data = null;
                }
                if (data !== null && typeof data === "object" && !Array.isArray(data)) {
                    if (data.readout === "elapsed" || data.readout === "tokens" || data.readout === "cost")
                        root.readout = data.readout;
                    if (typeof data.finishMin === "number" && isFinite(data.finishMin))
                        root.finishMin = Math.max(0, Math.min(3600, Math.round(data.finishMin)));
                    if (typeof data.finishNotice === "boolean")
                        root.finishNotice = data.finishNotice;
                    if (data.features !== null && typeof data.features === "object") {
                        const next = {};
                        for (let key in root.features)
                            next[key] = root.features[key];
                        for (let key in next)
                            if (typeof data.features[key] === "boolean")
                                next[key] = data.features[key];
                        root.features = next;
                    }
                }
                root.loaded = true;
                root.save();
            }
        }
    }

    function save() {
        if (!root.loaded)
            return;
        const json = JSON.stringify({
            readout: root.readout,
            finishMin: root.finishMin,
            finishNotice: root.finishNotice,
            features: root.features
        });
        Quickshell.execDetached(["sh", "-c",
            "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1.tmp\" && mv \"$1.tmp\" \"$1\"",
            "sh", root.configFile, json]);
    }

    function setReadout(value) {
        if (value !== "elapsed" && value !== "tokens" && value !== "cost")
            return;
        if (root.readout === value)
            return;
        root.readout = value;
        root.save();
    }

    function cycleReadout() {
        root.setReadout(root.readout === "elapsed" ? "tokens"
            : root.readout === "tokens" ? "cost" : "elapsed");
    }

    function setFinishMin(value) {
        const next = Math.max(0, Math.min(3600, Math.round(Number(value) || 0)));
        if (root.finishMin === next)
            return;
        root.finishMin = next;
        root.save();
    }

    function setFinishNotice(value) {
        if (root.finishNotice === value)
            return;
        root.finishNotice = value;
        root.save();
    }

    function feature(id) {
        return root.features[id] !== false;
    }

    function setFeature(id, value) {
        if (!(id in root.features) || root.features[id] === value)
            return;
        const next = {};
        for (let key in root.features)
            next[key] = root.features[key];
        next[id] = value;
        root.features = next;
        root.save();
    }

    IpcHandler {
        target: "settings"

        function setReadout(value: string): void { root.setReadout(value); }
        function getReadout(): string { return root.readout; }
        function setFinishMin(value: int): void { root.setFinishMin(value); }
        function getFinishMin(): int { return root.finishMin; }
        function setFinishNotice(value: bool): void { root.setFinishNotice(value); }
        function getFinishNotice(): bool { return root.finishNotice; }
        function setFeature(id: string, value: bool): void { root.setFeature(id, value); }
        function getFeature(id: string): bool { return root.feature(id); }
    }
}
