pragma Singleton

// Estado do Control Center (painel aberto pela bolinha do meio).
// - Controlável por IPC: qs -c skye ipc call controlcenter toggle|open|close|toggleCaffeine|getCaffeine|toggleNightLight|getNightLight

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property bool open: false
    // Mouse em cima do painel (o CC fecha quando sai da ilha e do painel)
    property bool panelHovered: false
    // Menu de dispositivos de áudio aberto (segura o painel durante a escolha)
    property bool deviceMenuOpen: false
    // Mixer de aplicativos aberto no lugar dos Levels (botão no CC)
    property bool mixerOpen: false
    property int tab: 0
    property bool caffeineEnabled: false
    property bool nightLightAvailable: false
    property bool nightLightEnabled: false

    // Night Light depende do gammastep (não instalado por padrão no CachyOS)
    Process {
        id: checkNightLight

        command: ["sh", "-c", "command -v gammastep >/dev/null && echo yes || echo no"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: root.nightLightAvailable = text.trim() === "yes"
        }
    }

    function toggleNightLight() {
        if (!nightLightAvailable)
            return;
        if (nightLightEnabled) {
            Quickshell.execDetached(["pkill", "-f", "gammastep"]);
            nightLightEnabled = false;
        } else {
            Quickshell.execDetached(["gammastep", "-O", "4000"]);
            nightLightEnabled = true;
        }
    }

    function toggle() {
        if (!open) {
            Notifications.centerOpen = false;
            Webcam.open = false;
            RecentFiles.open = false;
            Music.panelOpen = false;
        } else {
            mixerOpen = false;
        }
        open = !open;
    }

    function close() {
        mixerOpen = false;
        open = false;
    }

    IpcHandler {
        target: "controlcenter"

        function toggle(): void { root.toggle(); }
        function open(): void { Webcam.open = false; RecentFiles.open = false; Notifications.centerOpen = false; Music.panelOpen = false; root.open = true; }
        function close(): void { root.close(); }
        function setTab(n: int): void { root.tab = n; }
        function getTab(): int { return root.tab; }
        function toggleMixer(): void { root.mixerOpen = !root.mixerOpen; }
        function getMixer(): bool { return root.mixerOpen; }
        function toggleCaffeine(): void { root.caffeineEnabled = !root.caffeineEnabled; }
        function getCaffeine(): bool { return root.caffeineEnabled; }
        function toggleNightLight(): void { root.toggleNightLight(); }
        function getNightLight(): bool { return root.nightLightEnabled; }
    }
}
