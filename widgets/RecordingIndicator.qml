// Indicador de gravação exibido na ilha no lugar do relógio:
// bolinha vermelha (pulsando) + "REC" + tempo + botões de pausar/continuar e parar.

import QtQuick
import qs.services

Row {
    id: root

    spacing: 8

    function formatTime(total) {
        const p = (n) => String(n).padStart(2, "0");
        const h = Math.floor(total / 3600);
        const m = Math.floor((total % 3600) / 60);
        const s = total % 60;
        return h > 0 ? h + ":" + p(m) + ":" + p(s) : p(m) + ":" + p(s);
    }

    component ActionButton: Rectangle {
        id: button

        property string glyph: ""
        property color glyphColor: Theme.foreground

        signal activated()

        anchors.verticalCenter: parent.verticalCenter
        width: 24
        height: 24
        radius: 12
        color: buttonArea.containsMouse ? Theme.surfaceHover : "transparent"

        Behavior on color {
            ColorAnimation { duration: 120 }
        }

        Text {
            anchors.centerIn: parent
            text: button.glyph
            color: button.glyphColor
            font.family: Theme.iconFont
            font.pixelSize: 13
        }

        MouseArea {
            id: buttonArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.activated()
        }
    }

    // Bolinha vermelha (pulsa gravando; congela quando pausado)
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 9
        height: 9
        radius: 4.5
        color: Theme.recording

        SequentialAnimation on opacity {
            running: Recorder.recording
            paused: Recorder.paused
            loops: Animation.Infinite

            NumberAnimation { from: 1.0; to: 0.35; duration: 620; easing.type: Easing.InOutSine }
            NumberAnimation { from: 0.35; to: 1.0; duration: 620; easing.type: Easing.InOutSine }
        }
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "REC"
        color: Theme.recording
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.weight: Font.Bold
        font.letterSpacing: 1.2
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.formatTime(Recorder.elapsed)
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: 13
        font.weight: Font.Medium
    }

    ActionButton {
        glyph: Recorder.paused ? "\u{F040A}" : "\u{F03E4}" // play / pause
        onActivated: Recorder.togglePause()
    }

    ActionButton {
        glyph: "\u{F04DB}" // stop
        glyphColor: Theme.recording
        onActivated: Recorder.stop()
    }
}
