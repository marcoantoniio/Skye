// Relógio central da barra.

import Quickshell
import QtQuick
import qs.services

Item {
    id: root

    implicitWidth: label.implicitWidth
    implicitHeight: Theme.barHeight

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Text {
        id: label
        anchors.centerIn: parent
        // data no idioma escolhido (Qt.formatDateTime usa o locale C)
        text: clock.date.toLocaleString(I18n.dateLocale, "ddd d MMM · HH:mm").replace(/\./g, "")
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: 13
        font.weight: Font.Medium
    }
}
