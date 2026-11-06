pragma Singleton

// Gravador de tela (gpu-screen-recorder).
//
// - start(): grava só a tela principal (Theme.recorderScreenName, DP-1) em
//   /mnt/hd/videos.
// - stop(): finaliza o arquivo; pause()/resume() pausam de verdade
//   (comandos nativos via socket IPC do gpu-screen-recorder).
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

    readonly property string bin: "gpu-screen-recorder"
    readonly property string videosDir: "/mnt/hd/videos"
    readonly property string socketPath: Quickshell.env("XDG_RUNTIME_DIR") + "/skye-recorder.sock"

    property int _nextId: 1

    function filePath(): string {
        const d = new Date();
        const p = (n) => String(n).padStart(2, "0");
        const stamp = d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate())
                    + "_" + p(d.getHours()) + "-" + p(d.getMinutes()) + "-" + p(d.getSeconds());
        return root.videosDir + "/recording_" + stamp + ".mp4";
    }

    // Envia um comando para o socket IPC do gravador. Retorna false se não
    // estiver conectado (aí o chamador usa sinais como fallback).
    function send(name, data) {
        if (!ipc.connected)
            return false;

        const message = { id: root._nextId++, name: name };
        if (data !== undefined)
            message.data = data;
        ipc.write(JSON.stringify(message) + "\n");
        return true;
    }

    function start(): void {
        if (root.recording)
            return;

        root.lastFile = root.filePath();
        root.elapsed = 0;
        root.paused = false;

        proc.command = [
            root.bin,
            "-w", Theme.recorderScreenName, // só a tela principal (DP-1)
            "-c", "mp4",            // container
            "-k", "h264",           // codec compatível (NVENC)
            "-f", "60",             // 60 fps
            "-a", "default_output|default_input", // áudio do sistema + microfone
            "-ac", "aac",           // áudio compatível com mp4
            "-ipc", root.socketPath,
            "-o", root.lastFile
        ];
        proc.running = true;
        root.recording = true;
    }

    function stop(): void {
        if (!root.recording)
            return;

        if (!root.send("stop")) {
            if (root.paused)
                proc.signal(18); // SIGCONT (fallback quando pausado por sinal)
            proc.signal(2); // SIGINT: finaliza o arquivo
        }
        killTimer.start();
    }

    function pause(): void {
        if (!root.recording || root.paused)
            return;

        if (!root.send("set-paused", true))
            proc.signal(19); // SIGSTOP (fallback)
        root.paused = true;
    }

    function resume(): void {
        if (!root.recording || !root.paused)
            return;

        if (!root.send("set-paused", false))
            proc.signal(18); // SIGCONT (fallback)
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
        id: proc

        onExited: {
            ipc.connected = false;
            root.recording = false;
            root.paused = false;
            killTimer.stop();
        }
    }

    Socket {
        id: ipc

        path: root.socketPath

        parser: SplitParser {
            onRead: (line) => {
                try {
                    const reply = JSON.parse(line);
                    if (reply.result && reply.result !== "ok")
                        console.warn("[skye] gravador:", reply.result);
                } catch (e) {
                    console.warn("[skye] gravador: resposta inválida:", line);
                }
            }
        }

        onError: ipc.connected = false
    }

    // O socket só existe depois que o gravador inicia: tenta conectar.
    Timer {
        interval: 500
        repeat: true
        running: root.recording && !ipc.connected
        onTriggered: if (!ipc.connected) ipc.connected = true
    }

    // Se o stop não encerrar em 4s, força o término (SIGTERM).
    Timer {
        id: killTimer
        interval: 4000

        onTriggered: {
            if (proc.running)
                proc.running = false;
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
