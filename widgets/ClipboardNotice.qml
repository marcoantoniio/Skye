// Aviso rápido na ilha quando algo é copiado: ícone de prancheta + prévia
// do texto (aparece por ~2s no lugar do relógio/música).

import QtQuick
import qs.services

Row {
    id: root

    spacing: 7

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "\u{F014D}" // nf-md-clipboard
        color: Theme.accent
        font.family: Theme.iconFont
        font.pixelSize: 14
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, 170)
        text: Clipboard.lastItem.replace(/\s+/g, " ").trim()
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: 12
        elide: Text.ElideRight
    }
}
