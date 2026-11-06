pragma Singleton

// Estado do painel "Recentes" (hub do botão ciano da ilha).
//
// IPC:
//   qs -c skye ipc call recent toggle|open|close|refresh

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property bool open: false
    // mouse sobre a bolinha ciano: pré-aquece o painel (Bar.qml)
    property bool triggerHovered: false
    // Mouse em cima do painel (fecha quando sai da ilha e do painel)
    property bool panelHovered: false
    property var files: []

    // Arquivos mais recentes das pastas do dia a dia (mais novo primeiro)
    Process {
        id: scan

        command: ["sh", "-c",
            "find ~/Downloads ~/Pictures ~/Documents ~/Videos -maxdepth 1 -type f " +
            "-printf '%T@\\t%p\\n' 2>/dev/null | sort -rn | head -14"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                const lines = text.split("\n");
                for (let i = 0; i < lines.length; ++i) {
                    const line = lines[i];
                    const tab = line.indexOf("\t");
                    if (tab <= 0)
                        continue;
                    const path = line.substring(tab + 1);
                    const parts = path.split("/");
                    out.push({
                        ts: parseFloat(line.substring(0, tab)),
                        path: path,
                        name: parts[parts.length - 1],
                        dir: parts.length >= 2 ? parts[parts.length - 2] : ""
                    });
                }
                root.files = out;
            }
        }
    }

    function refresh(): void {
        if (!scan.running)
            scan.running = true;
    }

    onOpenChanged: {
        if (open)
            refresh();
    }

    // Mantém a lista fresca enquanto o painel está aberto
    Timer {
        interval: 15000
        running: root.open
        repeat: true
        onTriggered: root.refresh()
    }

    function toggle(): void {
        if (!open) {
            ControlCenter.open = false;
            Notifications.centerOpen = false;
            Webcam.open = false;
            Music.panelOpen = false;
            Midea.panelOpen = false;
        }
        open = !open;
    }

    function show(): void {
        ControlCenter.open = false;
        Notifications.centerOpen = false;
        Webcam.open = false;
        Music.panelOpen = false;
        Midea.panelOpen = false;
        open = true;
    }

    function close(): void {
        open = false;
    }

    IpcHandler {
        target: "recent"

        function toggle(): void { root.toggle(); }
        function open(): void { root.show(); }
        function close(): void { root.close(); }
        function refresh(): void { root.refresh(); }
    }
}
