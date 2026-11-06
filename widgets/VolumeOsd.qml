// OSD de volume exibido na ilha quando o volume/mute muda (some sozinho).

import QtQuick
import qs.services

Row {
    id: root

    spacing: 8

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: Audio.osdMuted ? "\u{F0581}" : "\u{F057E}" // volume-off / volume-high
        font.family: Theme.iconFont
        font.pixelSize: 15
        color: Audio.osdMuted ? Theme.foregroundDim : Theme.foreground
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 130
        height: 6
        radius: 3
        color: Theme.surfaceHover

        Rectangle {
            width: Math.max(0, Math.min(1, Audio.osdVolume)) * parent.width
            height: parent.height
            radius: parent.radius
            color: Audio.osdMuted ? Theme.foregroundDim : Theme.accent

            Behavior on width {
                NumberAnimation { duration: 90 }
            }
        }
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: Audio.osdMuted ? I18n.tr("muted") : Math.round(Audio.osdVolume * 100) + "%"
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: 13
        font.weight: Font.Medium
    }
}
