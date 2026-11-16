// Indicador da ilha enquanto o OpenCode gera uma resposta: ícone de terminal
// + cronômetro na cor de destaque do tema. No espírito do strip de AI Agents
// do Vorssaint, o cronômetro conta desde o início da geração mais antiga.

import QtQuick
import qs.services

Item {
    id: root

    implicitWidth: row.implicitWidth
    implicitHeight: Theme.barHeight

    property real now: Date.now()
    readonly property var session: Agents.oldestRunning

    Timer {
        interval: 1000
        repeat: true
        running: OpenCode.runningNow && Agents.readout === "elapsed"
        onRunningChanged: if (running) root.now = Date.now()
        onTriggered: root.now = Date.now()
    }

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 7

        OpenCodeMark {
            size: 15
            working: OpenCode.runningNow
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Agents.readoutValue(root.session, root.now)
            color: Theme.accent
            font.family: Theme.iconFont
            font.pixelSize: 13
            font.weight: Font.Medium
            font.letterSpacing: 0.3
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            OpenCode.focusRunningTab();
            Notifications.centerOpen = false;
            RecentFiles.open = false;
            Music.panelOpen = false;
            Midea.panelOpen = false;
            Webcam.open = false;
            ControlCenter.tab = 3;
            ControlCenter.open = true;
        }
    }
}
