pragma Singleton

// Agenda do Proton pelo link ICS compartilhado (Full view). O vdirsyncer baixa
// o .ics para ~/.local/share/skye/proton/ e o khal lê os eventos em JSON, uma
// linha por dia. Sincroniza a cada 30 min; a Proton leva até 8 h para mostrar
// mudanças, então sincronizar com mais frequência não ajuda.
// A leitura cobre o mês visível, o anterior e o seguinte (navegação no card).
// Setup: ~/.config/vdirsyncer/config (link) e ~/.config/khal/config.

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // Mês exibido (1º dia), controlado pelo CalendarCard
    property date viewMonth: new Date(new Date().getFullYear(), new Date().getMonth(), 1)
    property date readStart: new Date()
    property int readDays: 0
    property bool readPending: false
    property var eventsByDay: ({})

    function dayKey(d) {
        const p = (n) => String(n).padStart(2, "0");
        return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate());
    }

    function eventsOn(key) {
        return root.eventsByDay[key] || [];
    }

    function shiftMonth(n) {
        root.viewMonth = new Date(root.viewMonth.getFullYear(), root.viewMonth.getMonth() + n, 1);
        root.read();
    }

    function goToday() {
        const now = new Date();
        root.viewMonth = new Date(now.getFullYear(), now.getMonth(), 1);
        root.read();
    }

    function sync() {
        if (!syncProc.running)
            syncProc.running = true;
    }

    function read() {
        if (readProc.running) {
            root.readPending = true;
            return;
        }
        const y = root.viewMonth.getFullYear();
        const m = root.viewMonth.getMonth();
        root.readStart = new Date(y, m - 1, 1);
        root.readDays = Math.round((new Date(y, m + 2, 0) - root.readStart) / 86400000) + 1;
        readProc.command = ["khal", "list",
            "--json", "title", "--json", "description", "--json", "location",
            "--json", "start-time", "--json", "end-time", "--json", "all-day",
            root.dayKey(root.readStart), root.readDays + "d"];
        readProc.running = true;
    }

    function parse(text) {
        const lines = text.split("\n").filter(l => l.trim() !== "");
        if (lines.length !== root.readDays) {
            console.warn("[skye] calendário: khal devolveu", lines.length, "dias, esperado", root.readDays);
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
            if (code !== 0)
                console.warn("[skye] calendário: vdirsyncer falhou, código", code);
            root.read();
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
            if (root.readPending) {
                root.readPending = false;
                root.read();
            }
        }
    }

    Timer {
        interval: 1800000
        running: true
        repeat: true
        onTriggered: root.sync()
    }

    Component.onCompleted: {
        root.read();
        root.sync();
    }
}
