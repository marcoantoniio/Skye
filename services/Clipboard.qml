pragma Singleton

// Histórico do clipboard via wl-clipboard:
// - `wl-paste --watch` alimenta o histórico (base64 por linha no state dir,
//   com dedup e limite de 60 itens);
// - a UI lista os itens e copia de volta com `wl-copy`.
// Requer o pacote `wl-clipboard`; sem ele, `available` fica false.
//
// IPC: qs -c skye ipc call clipboard refresh|clear|copy <texto>

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property var items: []       // { b64, text }, mais novo primeiro
    property bool available: false

    // Fila interna de remoções: o Process de remoção é único, então uma
    // remoção nova espera a anterior terminar (senão era descartada e o item
    // reaparecia no refresh).
    property var removals: []

    // Feedback rápido na ilha (ícone + prévia) quando algo é copiado
    property string lastItem: ""
    property int lastSeq: 0
    property bool feedbackVisible: false

    readonly property string historyFile: Quickshell.stateDir + "/clipboard.txt"

    function refresh() {
        if (!readProc.running)
            readProc.running = true;
    }

    function copyItem(text) {
        setProc.command = ["wl-copy", text];
        setProc.running = true;
    }

    // remove um item do histórico (botão direito na aba do CC). Recebe a
    // linha base64 original: o texto exibido de um item binário (PNG etc.)
    // passa por decode com perdas e nunca casaria com o que está gravado.
    function removeItem(b64) {
        items = items.filter(i => i.b64 !== b64);
        removals.push(b64);
        runNextRemoval();
    }

    function runNextRemoval() {
        if (removeProc.running || removals.length === 0)
            return;
        // $1 é a própria linha do arquivo; o grep -v sai 1 quando não sobra
        // nenhuma linha (removendo o último item), então não pode abortar o
        // restante — senão o arquivo não é reescrito e o item volta no refresh
        removeProc.command = ["sh", "-c",
            "f='" + historyFile + "'; " +
            "grep -qxF \"$1\" \"$f\" 2>/dev/null || exit 0; " +
            "grep -vxF \"$1\" \"$f\" > \"$f.rm\"; " +
            "cat \"$f.rm\" > \"$f\"; rm -f \"$f.rm\"",
            "sh", removals.shift()];
        removeProc.running = true;
    }

    function clearHistory() {
        items = [];
        Quickshell.execDetached(["sh", "-c", ": > '" + historyFile + "'"]);
    }

    function startWatcher() {
        if (available && !watchProc.running)
            watchProc.running = true;
    }

    Component.onCompleted: {
        checkProc.running = true;
        followProc.running = true;
    }

    // vigia o histórico (tail -f): cada linha nova vira feedback na ilha
    Process {
        id: followProc

        command: ["sh", "-c",
            "touch '" + root.historyFile + "'; exec tail -n0 -f '" + root.historyFile + "'"]

        stdout: SplitParser {
            onRead: (line) => {
                if (line.length > 0)
                    root.showFeedback(line);
            }
        }

        onExited: followRetry.start()
    }

    Timer {
        id: followRetry

        interval: 2000
        onTriggered: if (!followProc.running) followProc.running = true
    }

    function showFeedback(b64) {
        if (decodeProc.running)
            decodeProc.running = false;
        decodeProc.command = ["sh", "-c", "printf '%s' \"$1\" | base64 -d", "sh", b64];
        decodeProc.running = true;
    }

    Process {
        id: decodeProc

        stdout: StdioCollector {
            onStreamFinished: {
                const txt = text.replace(/\n+$/, "");
                if (txt === "")
                    return;
                root.lastItem = txt;
                root.lastSeq = root.lastSeq + 1;
                root.feedbackVisible = true;
                feedbackTimer.restart();
            }
        }
    }

    Timer {
        id: feedbackTimer

        interval: 2200
        onTriggered: root.feedbackVisible = false
    }

    // disponibilidade do wl-clipboard (re-checa enquanto não tiver)
    Process {
        id: checkProc

        command: ["sh", "-c",
            "command -v wl-paste >/dev/null && command -v wl-copy >/dev/null && echo yes || echo no"]

        stdout: StdioCollector {
            onStreamFinished: {
                root.available = text.trim() === "yes";
                if (root.available)
                    root.startWatcher();
                else
                    checkAgain.start();
            }
        }
    }

    Timer {
        id: checkAgain

        interval: 8000
        onTriggered: if (!root.available) checkProc.running = true
    }

    // watcher: cada mudança no clipboard vira uma linha base64 no histórico.
    // Guarda o último conteúdo visto (.last) pra re-ofertas da mesma seleção
    // não re-adicionarem o que foi removido; temp próprio (.tmp).
    Process {
        id: watchProc

        command: ["wl-paste", "--watch", "sh", "-c",
            "b=$(base64 -w0); f='" + root.historyFile + "'; l='" + root.historyFile + ".last'; " +
            "[ -n \"$b\" ] && [ ${#b} -lt 200000 ] || exit 0; " +
            "[ \"$b\" = \"$(cat \"$l\" 2>/dev/null)\" ] && exit 0; " +
            "printf '%s' \"$b\" > \"$l\"; " +
            "{ grep -vxF \"$b\" \"$f\" 2>/dev/null; printf '%s\\n' \"$b\"; } > \"$f.tmp\" && " +
            "tail -n 60 \"$f.tmp\" > \"$f\" && rm -f \"$f.tmp\""]

        onExited: (code) => {
            if (code !== 0)
                watchRetry.start();
        }
    }

    Timer {
        id: watchRetry

        interval: 3000
        onTriggered: root.startWatcher()
    }

    // leitura: decodifica o histórico (mais novo primeiro)
    Process {
        id: readProc

        command: ["sh", "-c",
            "command -v wl-paste >/dev/null || exit 1; " +
            "python3 -c \"import base64,json; " +
            "ls=[{'b64':l,'text':base64.b64decode(l).decode('utf-8','replace')} " +
            "for l in open('" + root.historyFile + "',encoding='utf-8').read().splitlines() if l]; " +
            "print(json.dumps(ls[::-1][:60]))\" 2>/dev/null"]

        stdout: StdioCollector {
            onStreamFinished: {
                let list = null;
                try {
                    list = JSON.parse(text);
                } catch (e) {
                    list = null;
                }
                if (Array.isArray(list)) {
                    root.items = list;
                    root.available = true;
                }
            }
        }
    }

    Process {
        id: setProc
    }

    Process {
        id: removeProc

        onExited: root.runNextRemoval()
    }

    IpcHandler {
        target: "clipboard"

        function refresh(): void { root.refresh(); }
        function clear(): void { root.clearHistory(); }
        function copy(text: string): void { root.copyItem(text); }
    }
}
