pragma Singleton

// Gravador de tela (gpu-screen-recorder).
//
// - start(): grava só a tela principal (Theme.recorderScreenName, DP-1) em
//   /mnt/hd/videos.
// - stop(): finaliza o arquivo; pause()/resume() pausam de verdade (comandos
//   nativos via socket IPC do gpu-screen-recorder).
// - O socket IPC fica no scripts/recorder_bridge.py: o Quickshell 0.3.2
//   crasha no QLocalSocket quando o gravador fecha o socket (PeerClosedError).
// - Enquanto grava, a ilha mostra o indicador REC (RecordingIndicator).
// - Controle por IPC:
//   qs -c skye ipc call recorder toggle|start|stop|pause|resume|isRecording|isPaused|getTime|getFile

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property bool recording: false
    property bool paused: false
    property int elapsed: 0
    property string lastFile: ""

    readonly property string videosDir: "/mnt/hd/videos"
    readonly property string socketPath: Quickshell.env("XDG_RUNTIME_DIR") + "/skye-recorder.sock"

    property bool _bridgeReady: false
    property var _pendingStart: null

    function filePath(): string {
        const d = new Date();
        const p = (n) => String(n).padStart(2, "0");
        const stamp = d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate())
                    + "_" + p(d.getHours()) + "-" + p(d.getMinutes()) + "-" + p(d.getSeconds());
        return root.videosDir + "/recording_" + stamp + ".mp4";
    }

    function _send(message) {
        if (!bridge.running)
            return false;
        bridge.write(JSON.stringify(message) + "\n");
        return true;
    }

    function _flushStart() {
        if (root._pendingStart === null || !root._bridgeReady)
            return;
        const message = root._pendingStart;
        root._pendingStart = null;
        root._send(message);
    }

    function _onBridge(raw) {
        let event = null;
        try {
            event = JSON.parse(raw);
        } catch (e) {
            return;
        }
        if (event === null || typeof event !== "object")
            return;

        if (event.kind === "ready") {
            root._bridgeReady = true;
            root._flushStart();
        } else if (event.kind === "started") {
            root.recording = true;
            root.paused = false;
        } else if (event.kind === "paused") {
            root.paused = event.paused === true;
        } else if (event.kind === "stopped") {
            root.recording = false;
            root.paused = false;
            root._pendingStart = null;
            killTimer.stop();
        } else if (event.kind === "error") {
            console.warn("[skye] gravador: " + (event.message || "erro"));
            root.recording = false;
            root.paused = false;
            killTimer.stop();
        }
    }

    function _abort() {
        root._pendingStart = null;
        root.recording = false;
        root.paused = false;
        killTimer.stop();
    }

    function start(): void {
        if (root.recording)
            return;

        root.lastFile = root.filePath();
        root.elapsed = 0;
        root.paused = false;
        root.recording = true;
        root._pendingStart = {
            cmd: "start",
            screen: Theme.recorderScreenName,
            file: root.lastFile,
            socket: root.socketPath
        };

        if (bridge.running && root._bridgeReady)
            root._flushStart();
        else
            bridge.running = true;
    }

    function stop(): void {
        if (!root.recording)
            return;

        if (!root._bridgeReady || !root._send({ cmd: "stop" })) {
            root._abort();
            return;
        }
        killTimer.start();
    }

    function pause(): void {
        if (!root.recording || root.paused)
            return;

        if (!root._send({ cmd: "pause", paused: true })) {
            root._abort();
            return;
        }
        root.paused = true;
    }

    function resume(): void {
        if (!root.recording || !root.paused)
            return;

        if (!root._send({ cmd: "pause", paused: false })) {
            root._abort();
            return;
        }
        root.paused = false;
    }

    function togglePause(): void {
        if (root.paused)
            root.resume();
        else
            root.pause();
    }

    function toggle(): void {
        if (root.recording)
            root.stop();
        else
            root.start();
    }

    Process {
        id: bridge

        command: ["python3", Quickshell.shellDir + "/scripts/recorder_bridge.py"]
        stdinEnabled: true
        running: false

        stdout: SplitParser {
            onRead: (line) => root._onBridge(line)
        }

        stderr: SplitParser {
            onRead: (line) => console.warn("[skye] gravador: " + line)
        }

        onExited: (code) => {
            root._bridgeReady = false;
            root._pendingStart = null;
            killTimer.stop();
            if (root.recording) {
                root.recording = false;
                root.paused = false;
            }
            if (code !== 0)
                console.warn("[skye] gravador: bridge saiu com código " + code);
        }
    }

    // Se o stop não encerrar em 6s, força o término da ponte (que encerra o
    // gpu-screen-recorder no finally).
    Timer {
        id: killTimer
        interval: 6000

        onTriggered: {
            if (root.recording) {
                root.recording = false;
                root.paused = false;
                bridge.running = false;
            }
        }
    }

    // Cronômetro (não conta enquanto pausado).
    Timer {
        interval: 1000
        repeat: true
        running: root.recording && !root.paused
        onTriggered: root.elapsed += 1
    }

    IpcHandler {
        target: "recorder"

        function toggle(): void { root.toggle(); }
        function start(): void { root.start(); }
        function stop(): void { root.stop(); }
        function pause(): void { root.pause(); }
        function resume(): void { root.resume(); }
        function isRecording(): bool { return root.recording; }
        function isPaused(): bool { return root.paused; }
        function getTime(): int { return root.elapsed; }
        function getFile(): string { return root.lastFile; }
    }
}
