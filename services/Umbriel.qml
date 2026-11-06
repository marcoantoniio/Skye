pragma Singleton

// Serviço do compositor Umbriel via IPC (socket UNIX, JSON por linha).
//
// - Lista workspaces e mantém atualizada via subscribe.
// - Degrada em silêncio quando o Umbriel não está rodando (ex.: sessão KDE).
// - Troca de workspace com clique: workspace-switch:<seletor>
//
// Docs: https://docs.noctalia.dev/umbriel/ipc/

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property var workspaces: []
    property bool available: false

    readonly property string socketPath: {
        const fromEnv = Quickshell.env("UMBRIEL_SOCKET");
        if (fromEnv)
            return fromEnv;
        const runtime = Quickshell.env("XDG_RUNTIME_DIR");
        const display = Quickshell.env("WAYLAND_DISPLAY");
        return (runtime && display) ? `${runtime}/umbriel-${display}.sock` : "";
    }

    function send(obj) {
        if (!socket.connected)
            return false;
        socket.write(JSON.stringify(obj) + "\n");
        socket.flush();
        return true;
    }

    function switchTo(workspace) {
        // Nomes nomeados são sempre citados para não serem confundidos
        // com posição numérica (1-based).
        const target = workspace.named ? `"${workspace.name}"` : String(workspace.index);
        send({ cmd: "msg", arg: `workspace-switch:${target}` });
    }

    function applyWorkspaces(list) {
        if (!Array.isArray(list))
            return;
        workspaces = list;
        available = true;
    }

    function handleLine(line) {
        if (!line || line.length === 0)
            return;
        let message;
        try {
            message = JSON.parse(line);
        } catch (e) {
            return;
        }
        // Evento de subscribe: {"event":"workspaces","data":[...]}
        if (message.event === "workspaces") {
            applyWorkspaces(message.data);
            return;
        }
        // Resposta de {"cmd":"workspaces"}: {"ok":[...]}
        if (Array.isArray(message.ok)) {
            applyWorkspaces(message.ok);
            return;
        }
        if (message.err)
            console.warn("[skye] umbriel:", message.err);
    }

    Socket {
        id: socket
        path: root.socketPath

        parser: SplitParser {
            onRead: (line) => root.handleLine(line)
        }

        // O Socket só expõe o sinal `error`; o estado da conexão é observado
        // pela propriedade `connected`.
        onConnectedChanged: {
            if (connected) {
                root.available = true;
                root.send({ cmd: "subscribe", events: ["workspaces"] });
            } else {
                root.available = false;
            }
        }

        onError: {
            socket.connected = false;
            retry.restart();
        }
    }

    Component.onCompleted: {
        if (root.socketPath !== "")
            socket.connected = true;
    }

    Timer {
        id: retry
        interval: 15000
        repeat: false
        onTriggered: {
            if (root.socketPath !== "" && !socket.connected)
                socket.connected = true;
        }
    }
}
