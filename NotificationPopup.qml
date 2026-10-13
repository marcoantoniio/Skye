// Um toast de notificação.
// - Clique no cartão fecha o toast (mantém no histórico).
// - Ações da notificação viram botões.
// - Some sozinho após expireTimeout (ou 6s).

import Quickshell
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts

PopupWindow {
    id: popup

    property var modelData
    property var panelWindow: null

    readonly property var notification: modelData
    readonly property int popupWidth: 380

    anchor.window: panelWindow
    anchor.rect.x: panelWindow ? panelWindow.width - popupWidth - Theme.barMargin : 0
    anchor.rect.y: {
        if (!panelWindow)
            return 0;
        const index = Math.max(0, Notifications.popups.indexOf(notification));
        return panelWindow.height + Theme.barMargin + index * (implicitHeight + Theme.spacing);
    }
    implicitWidth: popupWidth
    implicitHeight: card.implicitHeight
    color: "transparent"
    // Esconde zumbis (notificação destruída = null) e toasts já removidos da
    // pilha; sem isso a caixa preta vazia fica presa na tela.
    visible: popup.notification != null && Notifications.popups.indexOf(popup.notification) >= 0
    grabFocus: false

    Rectangle {
        id: card
        anchors.fill: parent
        implicitHeight: layout.implicitHeight + 24
        radius: Theme.radius
        color: Theme.surface
        border.width: 1
        border.color: Theme.border

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Notifications.closePopup(popup.notification)
        }

        RowLayout {
            id: layout
            anchors {
                fill: parent
                margins: 12
            }
            spacing: 10

            Image {
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                visible: source !== ""
                source: popup.notification
                        ? (popup.notification.appIcon !== ""
                           ? Quickshell.iconPath(popup.notification.appIcon, true)
                           : popup.notification.image)
                        : ""
                sourceSize: Qt.size(36, 36)
                smooth: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: popup.notification ? popup.notification.appName : ""
                    color: Theme.foregroundDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: popup.notification ? popup.notification.summary : ""
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    visible: popup.notification ? popup.notification.body !== "" : false
                    text: popup.notification ? popup.notification.body : ""
                    textFormat: Text.PlainText
                    color: Theme.foregroundDim
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: popup.notification ? popup.notification.actions.length > 0 : false
                    spacing: 6

                    Repeater {
                        model: popup.notification ? popup.notification.actions : []

                        delegate: Rectangle {
                            required property var modelData

                            implicitWidth: actionLabel.implicitWidth + 16
                            implicitHeight: 24
                            radius: 8
                            color: actionArea.containsMouse ? Theme.surfaceHover : "transparent"
                            border.width: 1
                            border.color: Theme.border

                            Text {
                                id: actionLabel
                                anchors.centerIn: parent
                                text: modelData.text
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }

                            MouseArea {
                                id: actionArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: modelData.invoke()
                            }
                        }
                    }
                }
            }
        }
    }

    Timer {
        running: true
        // expireTimeout vem do remetente; -1/0 = sem preferência -> 6s.
        interval: popup.notification && popup.notification.expireTimeout > 0
                  ? popup.notification.expireTimeout * 1000
                  : 6000
        // Chama sempre (mesmo com notificação nula) para limpar zumbis da pilha.
        onTriggered: Notifications.closePopup(popup.notification)
    }
}
