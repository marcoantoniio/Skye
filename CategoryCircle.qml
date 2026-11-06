// Botão circular de ação (usado na barra): só a cor, sem ícone nem anel.
// O normal tem um brilho (halo) em volta; o selecionado fica apagado e sem halo.

import QtQuick
import QtQuick.Shapes

Item {
    id: root

    property color dotColor: Theme.accentAlt
    property bool selected: false

    signal activated()

    implicitWidth: 10
    implicitHeight: 10

    // mouse em cima (usado para pré-aquecer os painéis caros)
    readonly property alias hovered: circleArea.containsMouse

    // Brilho em volta (halo) — some quando o botão está selecionado/apagado
    Shape {
        anchors.centerIn: parent
        width: 20
        height: 20
        opacity: (!root.selected && root.enabled) ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation { duration: 240; easing.type: Easing.OutQuint }
        }

        ShapePath {
            strokeColor: "transparent"

            fillGradient: RadialGradient {
                centerX: 10
                centerY: 10
                centerRadius: 10
                focalX: 10
                focalY: 10

                GradientStop {
                    position: 0.0
                    color: Qt.rgba(root.dotColor.r, root.dotColor.g, root.dotColor.b, 0.75)
                }
                GradientStop {
                    position: 0.5
                    color: Qt.rgba(root.dotColor.r, root.dotColor.g, root.dotColor.b, 0.35)
                }
                GradientStop {
                    position: 1.0
                    color: Qt.rgba(root.dotColor.r, root.dotColor.g, root.dotColor.b, 0.0)
                }
            }

            PathAngleArc {
                centerX: 10
                centerY: 10
                radiusX: 10
                radiusY: 10
                startAngle: 0
                sweepAngle: 360
            }
        }
    }

    // Círculo
    Rectangle {
        id: circle

        anchors.centerIn: parent
        width: 10
        height: 10
        radius: 5
        color: root.dotColor
        opacity: root.enabled ? (root.selected ? 0.25 : 1) : 0.4
        scale: circleArea.pressed ? 0.85 : (circleArea.containsMouse ? 1.2 : 1)

        Behavior on scale {
            NumberAnimation { duration: 170; easing.type: Easing.OutQuint }
        }
        Behavior on opacity {
            NumberAnimation { duration: 240; easing.type: Easing.OutQuint }
        }
    }

    MouseArea {
        id: circleArea
        anchors.fill: parent
        anchors.margins: -3
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
