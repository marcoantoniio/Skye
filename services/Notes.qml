pragma Singleton

// Notas do Control Center: várias notas com título e corpo, persistidas em
// ~/.local/share/skye/notes.json (fica salvo no computador entre reinícios).
//
// ListModel (e não um array) para que alterar o corpo de uma nota não recrie
// os chips do cabeçalho: o setProperty notifica só o papel alterado.

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    ListModel {
        id: notesModel
    }

    readonly property ListModel notes: notesModel
    property int current: 0
    // espelho do corpo da nota atual (para o painel não depender de get())
    property string currentBody: ""
    // incrementa quando as notas terminam de carregar do disco
    property int loadSeq: 0

    readonly property string notesDir: Quickshell.env("HOME") + "/.local/share/skye"
    readonly property string notesFile: notesDir + "/notes.json"

    onCurrentChanged: refreshCurrentBody()

    function refreshCurrentBody() {
        root.currentBody = (root.current >= 0 && root.current < notesModel.count)
            ? (notesModel.get(root.current).body || "")
            : "";
    }

    function addNote() {
        notesModel.append({ title: "", body: "" });
        root.current = notesModel.count - 1;
        root.save();
    }

    function removeNote(i) {
        if (i < 0 || i >= notesModel.count)
            return;
        notesModel.remove(i);
        if (notesModel.count === 0)
            notesModel.append({ title: "", body: "" });
        let cur = root.current;
        if (i < cur)
            cur = cur - 1;
        root.current = Math.max(0, Math.min(cur, notesModel.count - 1));
        root.loadSeq = root.loadSeq + 1; // recarrega os campos (nota pode ter mudado)
        refreshCurrentBody();
        root.save();
    }

    function update(title, body) {
        if (root.current < 0 || root.current >= notesModel.count)
            return;
        const n = notesModel.get(root.current);
        if (n.title !== title)
            notesModel.setProperty(root.current, "title", title);
        if (n.body !== body) {
            notesModel.setProperty(root.current, "body", body);
            root.currentBody = body;
        }
        saveTimer.restart();
    }

    function save() {
        const list = [];
        for (let i = 0; i < notesModel.count; i++) {
            const n = notesModel.get(i);
            list.push({ title: n.title || "", body: n.body || "" });
        }
        const json = JSON.stringify(list);
        writeProc.command = ["sh", "-c",
            "mkdir -p '" + notesDir + "' && printf '%s' \"$1\" > '" + notesFile + "'",
            "sh", json];
        writeProc.running = true;
    }

    Timer {
        id: saveTimer
        interval: 600
        onTriggered: root.save()
    }

    Process {
        id: writeProc
    }

    Process {
        id: readProc

        command: ["sh", "-c", "cat '" + notesFile + "' 2>/dev/null"]

        stdout: StdioCollector {
            onStreamFinished: {
                let list = null;
                try {
                    list = JSON.parse(text);
                } catch (e) {
                    list = null;
                }
                notesModel.clear();
                if (Array.isArray(list) && list.length > 0) {
                    for (let i = 0; i < list.length; ++i) {
                        notesModel.append({
                            title: list[i].title || "",
                            body: list[i].body || ""
                        });
                    }
                } else {
                    notesModel.append({ title: "", body: "" });
                }
                root.current = 0;
                refreshCurrentBody();
                root.loadSeq = root.loadSeq + 1;
            }
        }
    }

    Component.onCompleted: readProc.running = true
}
