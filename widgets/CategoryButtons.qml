// Botões circulares coloridos do lado direito da barra (só cores, sem ícones).
// Cada cor tem uma função:
// - Laranja: abre/fecha o painel de notificações.
// - Magenta: abre/fecha o Control Center.
// - Ciano: abre/fecha o painel de arquivos recentes (hub).
// O selecionado ganha brilho.

import QtQuick
import qs.services

Row {
    id: root

    spacing: 10

    // ---- notificações ----
    CategoryCircle {
        dotColor: Theme.accent
        selected: Notifications.centerOpen && Notifications.activeCategory === ""
        onActivated: Notifications.toggleAll()
        onHoveredChanged: Notifications.triggerHovered = hovered
    }

    // ---- control center ----
    CategoryCircle {
        dotColor: Theme.accentAlt
        selected: ControlCenter.open
        onActivated: ControlCenter.toggle()
    }

    // ---- recentes (hub de arquivos recentes) ----
    CategoryCircle {
        dotColor: Theme.accentCool
        selected: RecentFiles.open
        onActivated: RecentFiles.toggle()
        onHoveredChanged: RecentFiles.triggerHovered = hovered
    }
}
