// Botão do ar-condicionado na ilha (aparece no hover da pílula, à direita
// das três bolinhas). Desenho próprio de split horizontal (como um aparelho
// de parede real) com vento saindo da frente (defletor) na diagonal: traços
// que nascem na saída de ar e descem abrindo em leque.
//
// Animação leve no padrão do equalizador da música: em vez de animações
// recalculando easing a cada frame, um Timer na taxa da tela avança um índice
// e cada traço só lê posição/opacidade de uma tabela pré-calculada.
//
// Clicar abre o menu (AcMenu).

import QtQuick

Item {
    id: root

    property bool hovered: false

    signal activated()

    implicitWidth: 34
    implicitHeight: 26

    // Cor do "aparelho": destaque quando ligado, apagado quando desligado
    readonly property color ink: (Midea.online && Midea.power) ? Theme.accent : Theme.foregroundDim

    // Corpo do split (horizontal, de parede)
    Rectangle {
        id: body

        anchors {
            top: parent.top
            topMargin: 4
            left: parent.left
        }
        width: 26
        height: 10
        radius: 3
        color: "transparent"
        border.width: 1.5
        border.color: root.ink

        // Defletor (saída de ar na parte de baixo) — simétrico
        Rectangle {
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: 1.8
            }
            width: parent.width - 8
            height: 1.1
            radius: 0.55
            color: root.ink
        }
    }

    // Vento: traços que saem da frente do aparelho (no defletor) e descem na
    // diagonal — corrente esquerda abre à esquerda, direita à direita
    Item {
        id: wind

        anchors {
            top: body.bottom
            topMargin: 1
            horizontalCenter: body.horizontalCenter
        }
        width: 26
        height: 9
        opacity: (Midea.online && Midea.power) ? 1 : 0

        // Queda vertical do caminho (0 = saída de ar, drop = fundo do Item)
        readonly property real drop: 8

        // Posições da tabela avançadas por tick (MEDIUM = 2 ≈ 0,77 s por ciclo).
        // Modo fora da lista (o bridge pode mandar um número cru) usa MEDIUM.
        readonly property var speeds: ({ SILENT: 1, LOW: 1.5, AUTO: 2, MEDIUM: 2, HIGH: 3, MAX: 4 })
        property real speed: speeds[Midea.fan] || speeds.MEDIUM

        // Ciclo com 96 posições: cada uma guarda o centro (mid) e a metade
        // (half) do trecho visível do traço, em fração do caminho. A cabeça vai
        // de 0 a 1 e a cauda fica no máximo 0,4 atrás: o traço nasce na saída
        // e se alonga enquanto desce.
        readonly property var table: {
            const t = [];
            for (let i = 0; i < 96; ++i) {
                const head = i / 96;
                const tail = Math.max(0, head - 0.4);
                t.push({
                    mid: (head + tail) / 2,
                    half: (head - tail) / 2,
                    o: Math.min(1, head / 0.15) * Math.min(1, (1 - head) / 0.3)
                });
            }
            return t;
        }

        property real frame: 0

        Timer {
            interval: 16
            repeat: true
            running: Midea.online && Midea.power
            onTriggered: wind.frame += wind.speed
        }

        Behavior on opacity {
            NumberAnimation { duration: 160 }
        }

        Behavior on speed {
            NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
        }

        Repeater {
            model: 10 // 5 correntes × 2 traços, meio ciclo entre eles

            delegate: Rectangle {
                required property int index

                readonly property int dash: Math.floor(index / 5)
                readonly property real lane: index % 5 - 2 // -2 (esquerda) a 2 (direita)
                readonly property real spread: lane * 2.5 // quanto a corrente abre até o fundo
                readonly property var e: wind.table[Math.floor(wind.frame + Math.abs(lane) * 20 + dash * 48) % 96]

                width: 1.6
                height: 2 * e.half * Math.sqrt(spread * spread + wind.drop * wind.drop)
                radius: 0.8
                // Qt gira no sentido horário: o traço segue a direção do caminho
                rotation: -Math.atan2(spread, wind.drop) * 180 / Math.PI
                x: wind.width / 2 + lane * 3.5 + spread * e.mid - width / 2
                y: wind.drop * e.mid - height / 2
                opacity: e.o
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.5) }
                    GradientStop { position: 1; color: Theme.accent }
                }
            }
        }
    }

    HoverHandler {
        id: hover

        onHoveredChanged: root.hovered = hovered
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
