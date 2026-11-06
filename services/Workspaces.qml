pragma Singleton

// Workspaces/desktops unificados:
// - KWin (KDE): via D-Bus (VirtualDesktopManager), com atualização a cada 2s.
// - Umbriel: espelha o serviço Umbriel.qml (socket IPC) como fallback.
//
// Itens: [{ id, name, active, occupied, raw }]
// IPC: qs -c skye ipc call workspaces refresh|switchToIndex <n>

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property var items: []
    property bool available: false

    // Fallback: espelha o serviço do Umbriel
    readonly property var umbrielItems: {
        const out = [];
        const list = Umbriel.workspaces;
        for (let i = 0; i < list.length; ++i) {
            const w = list[i];
            out.push({ id: String(w.id), name: w.name, active: w.focused, occupied: w.occupied, raw: w });
        }
        return out;
    }

    readonly property var displayItems: root.available ? root.items : umbrielItems

    function refresh() {
        if (!kwinQuery.running)
            kwinQuery.running = true;
    }

    function switchTo(item) {
        if (!item)
            return;

        // Fallback Umbriel
        if (!root.available) {
            if (item.raw)
                Umbriel.switchTo(item.raw);
            return;
        }

        // Atualização otimista
        const list = [];
        for (let i = 0; i < root.items.length; ++i) {
            const it = root.items[i];
            list.push({ id: it.id, name: it.name, active: it.id === item.id, occupied: it.occupied });
        }
        root.items = list;

        switchProc.command = ["dbus-send", "--session", "--print-reply", "--dest=org.kde.KWin",
            "/VirtualDesktopManager", "org.freedesktop.DBus.Properties.Set",
            "string:org.kde.KWin.VirtualDesktopManager", "string:current",
            "variant:string:" + item.id];
        switchProc.running = true;
    }

    Process {
        id: kwinQuery

        command: ["sh", "-c",
            "qdbus6 --literal org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager.desktops 2>/dev/null; " +
            "qdbus6 org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager.current 2>/dev/null"
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim();
                const idx = t.lastIndexOf("\n");
                if (idx <= 0) {
                    root.available = false;
                    return;
                }
                const data = t.slice(0, idx);
                const current = t.slice(idx + 1).trim();

                const re = /\(uss\)\s*(\d+),\s*"([^"]+)",\s*"([^"]*)"/g;
                const out = [];
                let m;
                while ((m = re.exec(data)) !== null)
                    out.push({ id: m[2], name: m[3], active: m[2] === current, occupied: false });

                if (out.length > 0) {
                    // Só atualiza se mudou (evita re-render desnecessário)
                    if (JSON.stringify(out) !== JSON.stringify(root.items))
                        root.items = out;
                    root.available = true;
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
        id: switchProc
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: refresh()

    IpcHandler {
        target: "workspaces"

        function refresh(): void { root.refresh(); }
        function switchToIndex(i: int): void {
            const list = root.displayItems;
            if (i >= 0 && i < list.length)
                root.switchTo(list[i]);
        }
        function getCurrent(): int {
            const list = root.displayItems;
            for (let i = 0; i < list.length; ++i) {
                if (list[i].active)
                    return i;
            }
            return -1;
        }
    }
}
