pragma Singleton

// Serviço de notificações: implementa o NotificationServer do freedesktop.
//
// - Notificações novas viram toasts (até 4) e ficam no histórico central.
// - "tracked" mantém no histórico mesmo após o toast sumir.
// - Cada aplicativo vira uma "categoria" com cor estável (mesma cor na barra
//   e nas abas do painel), como no shell original.
// - Controlável por IPC:
//   qs -c skye ipc call notifications toggle|open|openCategory|close|clearAll|getCount|toggleDnd|getDnd

import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

Singleton {
    id: root

    property bool centerOpen: false
    // Mouse em cima do painel (fecha quando sai da ilha e do painel)
    property bool panelHovered: false
    // Menu da bandeja do sistema aberto (segura o painel durante a escolha)
    property bool menuOpen: false
    property bool dnd: false
    property var popups: []
    property string activeCategory: ""

    readonly property alias trackedNotifications: server.trackedNotifications
    readonly property int count: server.trackedNotifications.values.length

    // Paleta usada para dar cor a cada categoria (app)
    readonly property var palette: [
        Theme.accent, Theme.accentAlt, Theme.accentCool, Theme.accentGreen, Theme.accentPurple
    ]

    function colorFor(name) {
        let hash = 0;
        for (let i = 0; i < name.length; ++i)
            hash = (hash * 31 + name.charCodeAt(i)) % 100000;
        return palette[hash % palette.length];
    }

    // Categorias (por appName), mais recentes primeiro
    readonly property var categories: {
        const list = server.trackedNotifications.values;
        const counts = ({});
        const order = [];
        for (let i = list.length - 1; i >= 0; --i) {
            const name = list[i].appName !== "" ? list[i].appName : "Outros";
            if (!(name in counts)) {
                counts[name] = 0;
                order.push(name);
            }
            counts[name] += 1;
        }
        const out = [];
        for (let i = 0; i < order.length; ++i)
            out.push({ name: order[i], count: counts[order[i]], color: colorFor(order[i]) });
        return out;
    }

    // Notificações filtradas pela categoria ativa ("" = todas)
    readonly property var filtered: {
        const list = server.trackedNotifications.values;
        const out = [];
        for (let i = 0; i < list.length; ++i) {
            if (activeCategory === "" || list[i].appName === activeCategory)
                out.push(list[i]);
        }
        return out;
    }

    function toggleCenter() {
        centerOpen = !centerOpen;
    }

    function openAll() {
        ControlCenter.open = false;
        RecentFiles.open = false;
        activeCategory = "";
        centerOpen = true;
    }

    function openCategory(name) {
        RecentFiles.open = false;
        activeCategory = name;
        centerOpen = true;
    }

    function toggleAll() {
        if (centerOpen && activeCategory === "")
            centerOpen = false;
        else
            openAll();
    }

    function closePopup(notification) {
        // O filtro também remove zumbis (notificação já destruída = null):
        // sem isso o toast fica preso na tela renderizando vazio.
        popups = popups.filter(n => n !== notification && n != null);
    }

    function dismiss(notification) {
        notification.tracked = false;
    }

    function clearAll() {
        // Cópia: apagar durante o loop encolhe trackedNotifications e pulava
        // itens (a lista era percorrida enquanto era modificada).
        const list = server.trackedNotifications.values.slice();
        for (let i = 0; i < list.length; ++i)
            list[i].tracked = false;
    }

    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        actionsSupported: true
        imageSupported: true
        bodyMarkupSupported: false

        onNotification: (notification) => {
            notification.tracked = true;

            // Notificações de conexão do Proton VPN (extensão no Zen) não
            // viram toast; continuam no histórico do painel.
            if (notification.summary === "Proton VPN")
                return;

            // Não perturbe: mantém no histórico, mas não mostra o toast.
            // Também não repopula toasts ao recarregar a config (hot reload).
            if (!root.dnd && !notification.lastGeneration)
                root.popups = [notification, ...root.popups].slice(0, 4);

            notification.closed.connect(() => {
                root.popups = root.popups.filter(n => n !== notification);
            });
        }
    }

    IpcHandler {
        target: "notifications"

        function toggle(): void { root.toggleCenter(); }
        function open(): void { root.openAll(); }
        function openCategory(name: string): void { root.openCategory(name); }
        function close(): void { root.centerOpen = false; }
        function clearAll(): void { root.clearAll(); }
        function getCount(): int { return root.count; }
        function toggleDnd(): void { root.dnd = !root.dnd; }
        function getDnd(): bool { return root.dnd; }
    }
}
