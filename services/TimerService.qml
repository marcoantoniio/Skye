pragma Singleton

// Pomodoro + cronômetro + timer (contagem regressiva). O estado vive aqui
// (fora do painel), então continua contando com o painel fechado. Ao concluir,
// toca um som e mostra um aviso na ilha.
//
// IPC:
//   qs -c skye ipc call timer pomodoro|stopwatch|countdown|setMinutes|reset|status

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // ---------- pomodoro (tempos configuráveis) ----------
    property int focusMinutes: 25
    property int shortBreakMinutes: 5
    property int longBreakMinutes: 15

    readonly property var focusPresets: [15, 20, 25, 30, 45, 60, 90]
    readonly property var shortPresets: [3, 5, 10, 15]
    readonly property var longPresets: [10, 15, 20, 30]

    property int pomoPhase: 0 // 0 = ocioso, 1 = foco, 2 = pausa, 3 = pausa longa
    property int pomoRemaining: focusMinutes * 60
    property bool pomoRunning: false
    property int pomoCompleted: 0

    readonly property int pomoTotal: pomoPhase === 2 ? shortBreakMinutes * 60
        : pomoPhase === 3 ? longBreakMinutes * 60
        : focusMinutes * 60

    readonly property real pomoProgress: pomoTotal > 0 ? 1 - pomoRemaining / pomoTotal : 0

    readonly property string pomoLabel: pomoPhase === 1 ? I18n.tr("focus")
        : pomoPhase === 2 ? I18n.tr("break")
        : pomoPhase === 3 ? I18n.tr("longBreak")
        : I18n.tr("ready")

    // Ajusta a duração da fase atual (ocioso = foco)
    function pomoAdjust(delta) {
        if (root.pomoPhase === 2)
            root.shortBreakMinutes = Math.max(1, Math.min(60, root.shortBreakMinutes + delta));
        else if (root.pomoPhase === 3)
            root.longBreakMinutes = Math.max(5, Math.min(90, root.longBreakMinutes + delta));
        else
            root.focusMinutes = Math.max(5, Math.min(120, root.focusMinutes + delta));

        if (root.pomoPhase === 0)
            root.pomoRemaining = root.focusMinutes * 60;
    }

    // Alterna entre os presets de duração
    function cyclePomodoro(kind) {
        function next(list, value) {
            for (let i = 0; i < list.length; ++i) {
                if (list[i] > value)
                    return list[i];
            }
            return list[0];
        }

        if (kind === "focus")
            root.focusMinutes = next(root.focusPresets, root.focusMinutes);
        else if (kind === "short")
            root.shortBreakMinutes = next(root.shortPresets, root.shortBreakMinutes);
        else
            root.longBreakMinutes = next(root.longPresets, root.longBreakMinutes);

        if (root.pomoPhase === 0)
            root.pomoRemaining = root.focusMinutes * 60;
    }

    function pomoToggle(): void {
        if (root.pomoPhase === 0) {
            root.pomoPhase = 1;
            root.pomoRemaining = root.focusMinutes * 60;
            root.pomoRunning = true;
            return;
        }
        root.pomoRunning = !root.pomoRunning;
    }

    function pomoReset(): void {
        root.pomoRunning = false;
        root.pomoPhase = 0;
        root.pomoRemaining = root.focusMinutes * 60;
    }

    function pomoSkip(): void {
        root.advancePhase();
    }

    function advancePhase() {
        let message = "";
        if (root.pomoPhase === 1) {
            root.pomoCompleted += 1;
            root.pomoPhase = root.pomoCompleted % 4 === 0 ? 3 : 2;
            message = root.pomoPhase === 3 ? I18n.tr("longBreakBang") : I18n.tr("breakBang");
        } else {
            root.pomoPhase = 1;
            message = I18n.tr("focusBang");
        }

        root.pomoRemaining = root.pomoTotal;
        root.pomoRunning = true;
        root.showMessage(message);
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.pomoRunning
        onTriggered: {
            if (root.pomoRemaining > 0)
                root.pomoRemaining -= 1;
            if (root.pomoRemaining <= 0)
                root.advancePhase();
        }
    }

    // ---------- timer (contagem regressiva) ----------
    property int timerMinutes: 10
    property int timerRemaining: timerMinutes * 60
    property bool timerRunning: false

    readonly property real timerProgress: timerMinutes > 0 ? 1 - timerRemaining / (timerMinutes * 60) : 0

    function timerSet(minutes) {
        root.timerRunning = false;
        root.timerMinutes = Math.max(1, Math.min(180, minutes));
        root.timerRemaining = root.timerMinutes * 60;
    }

    function timerAdjust(delta) {
        root.timerSet(root.timerMinutes + delta);
    }

    function timerToggle() {
        if (root.timerRemaining <= 0)
            root.timerRemaining = root.timerMinutes * 60;
        root.timerRunning = !root.timerRunning;
    }

    function timerReset() {
        root.timerRunning = false;
        root.timerRemaining = root.timerMinutes * 60;
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.timerRunning
        onTriggered: {
            if (root.timerRemaining > 0)
                root.timerRemaining -= 1;
            if (root.timerRemaining <= 0) {
                root.timerRunning = false;
                root.showMessage(I18n.tr("timeUp"));
            }
        }
    }

    // ---------- cronômetro ----------
    property bool swRunning: false
    property int swElapsed: 0
    property var laps: []

    function swToggle(): void {
        root.swRunning = !root.swRunning;
    }

    function swReset(): void {
        root.swRunning = false;
        root.swElapsed = 0;
        root.laps = [];
    }

    function swLap(): void {
        if (root.swElapsed <= 0)
            return;
        root.laps = [root.swElapsed, ...root.laps].slice(0, 20);
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.swRunning
        onTriggered: root.swElapsed += 1
    }

    // ---------- aviso na ilha ----------
    property string message: ""
    property bool messageVisible: false

    function showMessage(text) {
        root.message = text;
        root.messageVisible = true;
        messageTimer.restart();
    }

    Timer {
        id: messageTimer
        interval: 4000
        onTriggered: root.messageVisible = false
    }

    function format(seconds) {
        const t = Math.max(0, Math.floor(seconds));
        const p = (n) => String(n).padStart(2, "0");
        const h = Math.floor(t / 3600);
        const m = Math.floor((t % 3600) / 60);
        const s = t % 60;
        return h > 0 ? h + ":" + p(m) + ":" + p(s) : p(m) + ":" + p(s);
    }

    IpcHandler {
        target: "timer"

        function pomodoro(): void { root.pomoToggle(); }
        function stopwatch(): void { root.swToggle(); }
        function countdown(): void { root.timerToggle(); }
        function setMinutes(m: int): void { root.timerSet(m); }
        function reset(): void { root.pomoReset(); root.swReset(); root.timerReset(); }
        function status(): string {
            return "pomodoro: " + root.pomoLabel + " " + root.format(root.pomoRemaining)
                 + (root.pomoRunning ? I18n.tr("stRunning") : I18n.tr("stStopped"))
                 + " | timer: " + root.format(root.timerRemaining)
                 + (root.timerRunning ? I18n.tr("stRunning") : I18n.tr("stStopped"))
                 + " | " + I18n.tr("stopwatch") + ": " + root.format(root.swElapsed);
        }
    }
}
