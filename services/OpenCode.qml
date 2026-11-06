pragma Singleton

// Serviço da aba OpenCode: manda prompts para `opencode run --auto` numa
// sessão dedicada do painel (id "ses_skye-...") e transmite a resposta linha
// a linha. Sessão, pasta e modelo ficam salvos no stateDir do shell.
// IPC: qs -c skye ipc call opencode send "prompt" | stop | newSession | status

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property string sessionId: "ses_skye-" + Math.random().toString(36).slice(2, 10)
    property string workingDir: Quickshell.env("HOME")
    property string model: ""
    property string binPath: "opencode"

    // histórico da aba: { id, text, kind } — kind: cmd | out | err | info
    property var lines: []
    property bool running: false
    property var history: []
    property bool _stopping: false
    property bool loaded: false
    property string _pendingDir: ""
    property string _prevDir: ""
    property int _nextId: 1

    readonly property string stateFile: Quickshell.stateDir + "/opencode.json"

    Process {
        id: binProc

        command: ["sh", "-c", "command -v opencode"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                const v = text.trim();
                if (v !== "")
                    root.binPath = v;
                else
                    root.addLine("opencode não encontrado no PATH", "err");
            }
        }
    }

    Process {
        id: loadProc

        command: ["cat", root.stateFile]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                let data = null;
                try {
                    data = JSON.parse(text);
                } catch (e) {
                    data = null;
                }
                if (data !== null) {
                    if (typeof data.sessionId === "string" && data.sessionId.startsWith("ses_"))
                        root.sessionId = data.sessionId;
                    if (typeof data.workingDir === "string" && data.workingDir !== "")
                        root.workingDir = data.workingDir;
                    if (typeof data.model === "string")
                        root.model = data.model;
                    root.loaded = true;
                    root.save();
                } else if (text.trim() === "") {
                    // primeira execução: grava o estado inicial
                    root.loaded = true;
                    root.save();
                } else {
                    // ilegível: preserva o arquivo em vez de sobrescrever com o padrão
                    root.loaded = true;
                    console.warn("[skye] opencode: estado ilegível em " + root.stateFile);
                }
            }
        }
    }

    function save() {
        const json = JSON.stringify({
            sessionId: root.sessionId,
            workingDir: root.workingDir,
            model: root.model
        });
        // escrita atômica (tmp + mv): uma recarga não pega o arquivo pela metade
        Quickshell.execDetached(["sh", "-c",
            "printf '%s' \"$1\" > '" + root.stateFile + ".tmp' && mv '" + root.stateFile + ".tmp' '" + root.stateFile + "'",
            "sh", json]);
    }

    function addLine(text, kind) {
        const clean = text
            .replace(/\u001b\[[0-9;?]*[a-zA-Z]/g, "")
            .replace(/\u001b\][^\u0007]*\u0007/g, "")
            .replace(/\u001b/g, "")
            .replace(/\r/g, "");
        if (text !== "" && clean.trim() === "")
            return;
        // o "$ ..." do opencode marca um comando de ferramenta
        if (kind === "out" && clean.startsWith("$ "))
            kind = "tool";

        const list = root.lines.slice(-499);
        const last = list.length > 0 ? list[list.length - 1] : null;
        // agrupa a saída do modelo num bloco só (vira um balão à esquerda)
        if (kind === "out") {
            if (last !== null && last.kind === "out") {
                list[list.length - 1] = { id: last.id, text: last.text + "\n" + clean, kind: "out" };
            } else if (clean !== "") {
                list.push({ id: root._nextId++, text: clean, kind: "out" });
            }
        } else {
            list.push({ id: root._nextId++, text: clean, kind: kind });
        }
        root.lines = list;
    }

    function send(prompt) {
        if (root.running)
            return;
        root.history = [...root.history, prompt].slice(-50);

        if (prompt === "/cd" || prompt === "cd") {
            root.changeDir(Quickshell.env("HOME"));
            return;
        }
        if (prompt === "/cd -" || prompt === "cd -") {
            if (root._prevDir !== "")
                root.changeDir(root._prevDir);
            else
                root.addLine("sem pasta anterior", "info");
            return;
        }
        if (prompt.startsWith("/cd ") || prompt.startsWith("cd ")) {
            root.changeDir(prompt.replace(/^\/?cd\s+/, ""));
            return;
        }
        if (prompt.startsWith("/model")) {
            const name = prompt.slice(6).trim();
            root.model = name;
            root.addLine(name === "" ? "modelo: padrão do opencode" : "modelo: " + name, "info");
            return;
        }
        if (prompt === "/new") {
            root.newSession();
            return;
        }

        root.addLine("❯ " + prompt, "cmd");
        // stdin vai para /dev/null: o pipe do Quickshell fica aberto e o
        // `opencode run` bloqueia lendo stdin (ele aceita entrada por pipe).
        runProc.command = ["sh", "-c", "exec \"$0\" \"$@\" < /dev/null", root.binPath, "run", "--auto", "-s", root.sessionId]
            .concat(root.model !== "" ? ["-m", root.model] : [])
            .concat([prompt]);
        root._stopping = false;
        root.running = true;
        runProc.running = true;
    }

    function stop() {
        if (!root.running)
            return;
        root._stopping = true;
        root.addLine("(parado)", "info");
        runProc.running = false;
    }

    function newSession() {
        root.sessionId = "ses_skye-" + Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
        root.lines = [];
        root.addLine("nova sessão: " + root.sessionId, "info");
    }

    function clearLines() {
        root.lines = [];
    }

    // Muda a pasta de trabalho e começa uma sessão nova ali: as sessões do
    // OpenCode pertencem ao diretório onde nasceram.
    function changeDir(raw) {
        let dir = raw.trim().replace(/^~(?=\/|$)/, Quickshell.env("HOME"));
        if (dir === "")
            return;
        if (!dir.startsWith("/"))
            dir = root.workingDir.replace(/\/+$/, "") + "/" + dir;
        root._pendingDir = dir;
        // `cd && pwd -P` valida e normaliza (resolve ".", ".." e symlinks)
        dirProc.command = ["sh", "-c", "cd \"$1\" 2>/dev/null && pwd -P", "sh", dir];
        dirProc.running = true;
    }

    Process {
        id: runProc

        workingDirectory: root.workingDir

        stdout: SplitParser {
            onRead: (line) => root.addLine(line, "out")
        }

        stderr: SplitParser {
            onRead: (line) => root.addLine(line, "err")
        }

        onExited: (code) => {
            root.running = false;
            if (code !== 0 && !root._stopping)
                root.addLine("(saiu com código " + code + ")", "info");
            root._stopping = false;
        }
    }

    Process {
        id: dirProc

        // saída vazia = pasta inexistente; caso contrário vem o caminho já
        // normalizado (sem ".", ".." ou barra sobrando)
        stdout: StdioCollector {
            onStreamFinished: {
                const dir = text.trim();
                if (dir !== "") {
                    root._prevDir = root.workingDir;
                    root.workingDir = dir;
                    root.newSession();
                    root.addLine("pasta: " + root.workingDir, "info");
                } else {
                    root.addLine("pasta não encontrada: " + root._pendingDir, "err");
                }
            }
        }
    }

    onSessionIdChanged: if (root.loaded) save()
    onWorkingDirChanged: if (root.loaded) save()
    onModelChanged: if (root.loaded) save()

    IpcHandler {
        target: "opencode"

        function send(prompt: string): void { root.send(prompt); }
        function stop(): void { root.stop(); }
        function newSession(): void { root.newSession(); }
        function clear(): void { root.clearLines(); }
        function status(): string {
            const last = root.lines.length > 0 ? root.lines[root.lines.length - 1].text : "";
            return "rodando=" + root.running + " sessao=" + root.sessionId
                 + " pasta=" + root.workingDir + " modelo=" + (root.model === "" ? "(padrao)" : root.model)
                 + " linhas=" + root.lines.length + " ultima=" + JSON.stringify(last.slice(0, 120));
        }
    }
}
