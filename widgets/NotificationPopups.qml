// Pilha de toasts de notificação, ancorada abaixo da barra.
// Noctalia/Quickshell: cada toast é um PopupWindow próprio.

import Quickshell
import qs.services

Variants {
    id: root

    property var panelWindow: null

    model: Notifications.popups

    NotificationPopup {
        required property var modelData

        panelWindow: root.panelWindow
    }
}
