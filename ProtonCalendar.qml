pragma Singleton

// Agenda do Proton pelo link ICS compartilhado (Full view). O vdirsyncer baixa
// o .ics para ~/.local/share/skye/proton/ e o khal lê os eventos em JSON, uma
// linha por dia. Sincroniza a cada 30 min; a Proton leva até 8 h para mostrar
// mudanças, então sincronizar com mais frequência não ajuda.
// Setup: ~/.config/vdirsyncer/config (link) e ~/.config/khal/config.

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // Janela lida: começa no 1º dia do mês anterior e cobre o mês atual inteiro
    readonly property int windowDays: 62
    property date readStart: new Date()
    property var eventsByDay: ({})

    function dayKey(d) {
        const p = (n) => String(n).padStart(2, "0");
        return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate());
    }

    function eventsOn(key) {
        return root.eventsByDay[key] || [];
    }

    function sync() {
        if (!syncProc.running)
            syncProc.running = true;
    }

    function read() {
        const now = new Date();
        root.readStart = new Date(now.getFullYear(), now.getMonth() - 1, 1);
        readProc.command = ["khal", "list",
            "--json", "title", "--json", "description", "--json", "location",
            "--json", "start-time", "--json", "end-time", "--json", "all-day",
            root.dayKey(root.readStart), root.windowDays + "d"];
        readProc.running = true;
    }

    function parse(text) {
        const lines = text.split("\n").filter(l => l.trim() !== "");
        if (lines.length !== root.windowDays) {
            console.warn("[skye] calendário: khal devolveu", lines.length, "dias, esperado", root.windowDays);
            return;
        }
        const map = {};
        for (let i = 0; i < lines.length; ++i) {
            const s = root.readStart;
            const day = new Date(s.getFullYear(), s.getMonth(), s.getDate() + i);
            map[root.dayKey(day)] = JSON.parse(lines[i]).map(e => ({
                title: e.title,
                description: e.description,
                location: e.location,
                start: e["start-time"],
                end: e["end-time"],
                allDay: e["all-day"] === "True"
            }));
        }
        root.eventsByDay = map;
    }

    Process {
        id: syncProc

        command: ["vdirsyncer", "sync", "proton"]

        onExited: (code) => {
            if (code === 0)
                root.read();
            else
                console.warn("[skye] calendário: vdirsyncer falhou, código", code);
        }
    }

    Process {
        id: readProc

        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }

        onExited: (code) => {
            if (code !== 0)
                console.warn("[skye] calendário: khal falhou, código", code);
        }
    }

    Timer {
        interval: 1800000
        running: true
        repeat: true
        onTriggered: root.sync()
    }

    Component.onCompleted: root.sync()
}
