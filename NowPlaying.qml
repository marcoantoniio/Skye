// Música tocando na ilha: capa do álbum + barrinhas animadas + título.

import QtQuick

Row {
    id: root

    spacing: 9

    // Capa do álbum
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 24
        height: 24
        radius: 6
        color: Theme.surfaceHover
        clip: true

        Image {
            anchors.fill: parent
            source: Music.artUrl
            sourceSize: Qt.size(48, 48)
            smooth: true
            fillMode: Image.PreserveAspectCrop
            visible: status === Image.Ready
        }
    }

    // Barrinhas (equalizador) — congelam quando pausado.
    // Otimização: em vez de 4 animações recalculando easing a cada frame (o
    // loop de render ficava solto em ~200 fps), um único Timer na taxa da
    // tela percorre uma tabela com o ciclo já calculado (4 -> 14 -> 4). Sem
    // animação ativa, o loop de render só roda quando o Timer muda as alturas.
    Row {
        id: bars

        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        // Um ciclo completo (InOutSine) em 256 posições: aproxima o from=0
        // e o "salto" não têm como acontecer — os valores são sempre 4..14.
        readonly property var table: {
            const t = [];
            for (let i = 0; i < 256; ++i)
                t.push(9 - 5 * Math.cos(2 * Math.PI * i / 256));
            return t;
        }

        property int frame: 0
        property real t0: Date.now()

        Timer {
            interval: 7          // ~144 Hz (taxa da tela principal, DP-1)
            repeat: true
            running: Music.playing
            onRunningChanged: if (running) bars.t0 = Date.now()
            onTriggered: bars.frame++
        }

        Repeater {
            model: 4

            Rectangle {
                required property int index

                anchors.verticalCenter: parent.verticalCenter
                width: 3
                radius: 1.5
                color: Theme.accent

                // altura lida da tabela na fase da barra (ciclo = 2 meias-ondas)
                height: {
                    bars.frame;   // dependência: reavalia a cada tick do Timer
                    const cyc = 2 * (260 + index * 60);
                    const el = Date.now() - bars.t0;
                    const ph = (((el % cyc) + cyc) % cyc) / cyc;
                    return bars.table[Math.floor(ph * 256) % 256];
                }
            }
        }
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, 150)
        text: Music.title
        color: Theme.foreground
        font.family: Theme.musicFontFamily
        font.pixelSize: 12
        font.weight: Font.Medium
        elide: Text.ElideRight
    }
}
