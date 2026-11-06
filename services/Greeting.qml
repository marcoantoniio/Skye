pragma Singleton

// Saudação dinâmica com o nome do usuário (GECOS).
// Usada na ilha dinâmica (aparece no hover).

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property string userName: Quickshell.env("USER") || ""
    property int tick: 0

    readonly property string text: {
        root.tick;
        const h = new Date().getHours();
        const greet = h < 12 ? I18n.tr("goodMorning")
            : (h < 18 ? I18n.tr("goodAfternoon") : I18n.tr("goodEvening"));
        return greet + ", " + root.userName;
    }

    Process {
        id: userProc

        command: ["sh", "-c", "getent passwd \"$USER\" | cut -d: -f5 | cut -d, -f1"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                const name = text.trim();
                if (name.length > 0)
                    root.userName = name;
            }
        }
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.tick++
    }
}
