// Aviso do timer na ilha (ex.: "Foco!", "Pausa!").

import QtQuick
import qs.services

Row {
    id: root

    spacing: 8

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "\u{F13AB}" // nf-md-timer
        font.family: Theme.iconFont
        font.pixelSize: 16
        color: Theme.accent
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: TimerService.message
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: 13
        font.bold: true
    }
}
