pragma Singleton

// Brilho de monitor externo via DDC/CI (ddcutil).
// - Detecta o primeiro display com DDC/CI e o seu barramento i2c.
// - Lê o brilho (VCP 10) e permite ajustar (com debounce, pois setvcp é lento).
// - Em monitores sem DDC/CI, `available` fica false.
//
// IPC: qs -c skye ipc call brightness get|set <0-100>|refresh

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property bool available: false
    property int bus: -1
    property string displayName: ""
    property int value: 0
    property int maxValue: 100

    property int pendingValue: -1

    function refresh() {
        if (!detect.running)
            detect.running = true;
    }

    function read() {
        if (bus < 0)
            return;
        readProc.command = ["ddcutil", "-b", String(bus), "getvcp", "10"];
        readProc.running = true;
    }

    function setValue(v) {
        pendingValue = Math.max(0, Math.min(maxValue, Math.round(v)));
        value = pendingValue;
        applyTimer.restart();
    }

    // Descobre o barramento i2c e o nome do primeiro display com DDC/CI
    Process {
        id: detect

        command: ["sh", "-c", "ddcutil detect 2>/dev/null | awk '/^Display/{found=1} found && /I2C bus/{print $3} found && /Model:/{sub(/^ *Model: */, \"\"); print} found && /VCP version/{exit}'"]

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                const m = lines.length > 0 ? lines[0].match(/i2c-(\d+)/) : null;
                if (m) {
                    root.bus = Number(m[1]);
                    root.displayName = lines.length > 1 ? lines[1].trim() : "";
                    root.available = true;
                    root.read();
                } else {
                    root.available = false;
                }
            }
        }

        onExited: (code) => {
            if (code !== 0)
                root.available = false;
        }
    }

    Process {
        id: readProc

        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/current value =\s*(\d+),\s*max value =\s*(\d+)/);
                if (m) {
                    root.value = Number(m[1]);
                    root.maxValue = Number(m[2]);
                }
            }
        }
    }

    Process {
        id: setProc
    }

    Timer {
        id: applyTimer

        interval: 450
        onTriggered: {
            if (root.bus >= 0 && root.pendingValue >= 0) {
                setProc.command = ["ddcutil", "-b", String(root.bus), "--noverify", "setvcp", "10", String(root.pendingValue)];
                setProc.running = true;
            }
        }
    }

    Component.onCompleted: refresh()

    IpcHandler {
        target: "brightness"

        function get(): int { return root.value; }
        function set(v: int): void { root.setValue(v); }
        function refresh(): void { root.refresh(); }
    }
}
