// Aviso curto na ilha quando uma tarefa do OpenCode termina. Mesmo formato
// do strip do Vorssaint: marca do agente + resultado, sem roubar a tela.

import QtQuick
import qs.services

Item {
    id: root

    implicitWidth: row.implicitWidth
    implicitHeight: Theme.barHeight

    readonly property var notice: OpenCode.finishNotice
    readonly property color tint: root.notice === null ? Theme.accent
        : root.notice.outcome === "succeeded" ? Theme.accent
        : root.notice.outcome === "interrupted" ? Theme.foregroundDim : Theme.urgent

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 7

        OpenCodeMark {
            size: 15
            working: false
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: {
                if (root.notice === null)
                    return "";
                if (root.notice.outcome === "failed")
                    return "✗ " + I18n.tr("ocFailed");
                if (root.notice.outcome === "interrupted")
                    return "■ " + I18n.tr("ocInterrupted");
                let text = "✓ " + I18n.tr("ocFinished", [OpenCode.clock(root.notice.duration)]);
                if (root.notice.tokens > 0)
                    text += " · " + OpenCode.formatTokens(root.notice.tokens) + " " + I18n.tr("ocTokens");
                return text;
            }
            color: root.tint
            font.family: Theme.iconFont
            font.pixelSize: 12
            font.weight: Font.Medium
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (root.notice !== null)
                OpenCode.focusTabById(root.notice.tabId);
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
